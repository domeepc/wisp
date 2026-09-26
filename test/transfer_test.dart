import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wisp/models/device.dart';
import 'package:wisp/models/shared_file.dart';
import 'package:wisp/models/transfer.dart';
import 'package:wisp/net/client.dart';
import 'package:wisp/net/identity.dart';
import 'package:wisp/net/protocol.dart';
import 'package:wisp/net/server.dart';
import 'package:wisp/services/wisp_service.dart';
import 'package:wisp/utils/pick_files.dart';

/// Two Wisp services talking to each other over localhost.
void main() {
  late Directory tmp;
  late WispService a;
  late WispService b;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wisp_test');
    a = WispService(name: 'A', saveDir: '${tmp.path}/a', port: 0, pagePort: 0);
    b = WispService(name: 'B', saveDir: '${tmp.path}/b', port: 0, pagePort: 0);
    await a.start(discovery: false);
    await b.start(discovery: false);
    expect(a.startError, isNull);
    expect(b.startError, isNull);
  });

  tearDown(() async {
    await a.stop();
    await b.stop();
    await tmp.delete(recursive: true);
  });

  Device bAsSeenByA() => b.self.copyWith(host: '127.0.0.1');

  Future<void> finished(Transfer t) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (t.status.isActive) {
      if (DateTime.now().isAfter(deadline)) fail('Transfer never finished');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  File source(String name, String content) =>
      File('${tmp.path}/$name')..writeAsStringSync(content);

  test('sends files after the receiver accepts', () async {
    b.incoming.listen((request) {
      expect(request.offer.from.name, 'A');
      expect(request.offer.files.map((f) => f.name), ['hello.txt', 'evil.txt']);
      request.accept();
    });

    final sent = a.send(bAsSeenByA(), [
      SharedFile.fromPath(source('hello.txt', 'hello').path),
      // A malicious name must not escape the downloads folder.
      SharedFile.text('hi there', name: '../../evil.txt'),
    ]);
    await finished(sent);

    expect(sent.status, TransferStatus.done, reason: sent.error);
    expect(sent.progress, 1);
    expect(File('${tmp.path}/b/hello.txt').readAsStringSync(), 'hello');
    expect(File('${tmp.path}/b/evil.txt').readAsStringSync(), 'hi there');
    expect(File('${tmp.path}/evil.txt').existsSync(), isFalse);

    final received = b.transfers.single;
    expect(received.direction, TransferDirection.receive);
    expect(received.status, TransferStatus.done);
    expect(received.securityCode, sent.securityCode);
    expect(
      sent.securityCode,
      securityCode(b.self.fingerprint!, sent.sessionId),
    );
  });

  test('a big file arrives intact', () async {
    b.incoming.listen((r) => r.accept());
    final big = File('${tmp.path}/big.bin')
      ..writeAsBytesSync(List.generate(5 * 1024 * 1024, (i) => i % 251));

    final sent = a.send(bAsSeenByA(), [SharedFile.fromPath(big.path)]);
    await finished(sent);

    expect(sent.status, TransferStatus.done, reason: sent.error);
    expect(
      File('${tmp.path}/b/big.bin').readAsBytesSync(),
      big.readAsBytesSync(),
    );
  });

  test('same name twice gets a (1) suffix', () async {
    b.incoming.listen((r) => r.accept());
    final file = SharedFile.fromPath(source('notes.txt', 'x').path);

    await finished(a.send(bAsSeenByA(), [file]));
    await finished(a.send(bAsSeenByA(), [file]));

    expect(File('${tmp.path}/b/notes.txt').existsSync(), isTrue);
    expect(File('${tmp.path}/b/notes (1).txt').existsSync(), isTrue);
  });

  test('declining stops the transfer', () async {
    b.incoming.listen((r) => r.decline());

    final sent = a.send(bAsSeenByA(), [SharedFile.text('nope')]);
    await finished(sent);

    expect(sent.status, TransferStatus.declined);
    expect(Directory('${tmp.path}/b').existsSync(), isFalse);
  });

  test('a hidden device declines without asking', () async {
    b.visible = false;
    var asked = false;
    b.incoming.listen((_) => asked = true);

    final sent = a.send(bAsSeenByA(), [SharedFile.text('hello')]);
    await finished(sent);

    expect(sent.status, TransferStatus.declined);
    expect(asked, isFalse);
  });

  test('"always accept" skips the question next time', () async {
    var asked = 0;
    b.incoming.listen((r) {
      asked++;
      r.accept(always: true);
    });

    await finished(a.send(bAsSeenByA(), [SharedFile.text('one')]));
    final second = a.send(bAsSeenByA(), [SharedFile.text('two')]);
    await finished(second);

    expect(second.status, TransferStatus.done);
    expect(asked, 1);
  });

  test('cancelling while waiting closes the request on the receiver', () async {
    late Transfer sent;
    final request = b.incoming.first;

    sent = a.send(bAsSeenByA(), [SharedFile.text('hello')]);
    final incoming = await request;
    sent.cancel();

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!incoming.cancelled.value) {
      if (DateTime.now().isAfter(deadline)) fail('Receiver never noticed');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(sent.status, TransferStatus.cancelled);
  });

  test('uploads without a valid session are rejected', () async {
    final client = HttpClient();
    final req = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:${b.browserPort}${Api.upload}'
        '?sessionId=nope&fileId=0&token=nope',
      ),
    );
    req.write('sneaky');
    final res = await req.close();
    await res.drain<void>();
    client.close();

    expect(res.statusCode, 404);
    expect(Directory('${tmp.path}/b').existsSync(), isFalse);
  });

  test('register makes both sides know each other', () async {
    b.addDevice(a.self.copyWith(host: '127.0.0.1'));
    a.addDevice(bAsSeenByA());
    expect(a.devices.single.name, 'B');
    expect(b.devices.single.name, 'A');
  });

  test('safeFileName strips folders and bad characters', () {
    expect(safeFileName('../../etc/passwd'), 'passwd');
    expect(safeFileName(r'C:\Users\x\a.txt'), 'a.txt');
    expect(safeFileName('a<b>c?.txt'), 'a_b_c_.txt');
    expect(safeFileName('..'), 'file');
    expect(safeFileName(''), 'file');
  });

  test('folders arrive as folders, and can\'t climb out', () async {
    b.incoming.listen((r) => r.accept());

    final sent = a.send(bAsSeenByA(), [
      SharedFile.text('a', name: 'Photos/2024/a.txt'),
      SharedFile.text('b', name: 'Photos/../../../b.txt'),
    ]);
    await finished(sent);

    expect(sent.status, TransferStatus.done, reason: sent.error);
    expect(File('${tmp.path}/b/Photos/2024/a.txt').readAsStringSync(), 'a');
    expect(File('${tmp.path}/b/Photos/b.txt').readAsStringSync(), 'b');
  });

  test('a symlinked folder can\'t be used to write elsewhere', () async {
    final outside = Directory('${tmp.path}/outside')..createSync();
    Directory('${tmp.path}/b').createSync();
    Link('${tmp.path}/b/sneaky').createSync(outside.path);
    b.incoming.listen((r) => r.accept());

    final sent = a.send(bAsSeenByA(), [
      SharedFile.text('x', name: 'sneaky/evil.txt'),
    ]);
    await finished(sent);

    expect(sent.status, TransferStatus.failed);
    expect(outside.listSync(), isEmpty);
  });

  test('dropped folders become relative file names', () async {
    final folder = Directory('${tmp.path}/Trip/day1')
      ..createSync(recursive: true);
    File('${folder.path}/a.jpg').writeAsStringSync('a');
    File('${folder.path}/.DS_Store').writeAsStringSync('junk');
    final single = source('single.txt', 's');

    final files = await filesFromPaths(['${tmp.path}/Trip', single.path]);

    expect(files.map((f) => f.name), ['Trip/day1/a.jpg', 'single.txt']);
  });

  group('connect with code', () {
    test('adds the device on both sides', () async {
      final device = await a.connect('127.0.0.1:${b.self.port}');

      expect(device.name, 'B');
      // Learned from the certificate it presented.
      expect(device.fingerprint, b.self.fingerprint);
      expect(a.devices.single.name, 'B');
      expect(b.devices.single.name, 'A');
    });

    test('this device\'s code', () async {
      expect(WispService().connectCode, isNull); // not started yet
      a.localAddress = '192.168.1.24';
      expect(a.connectCode, '192.168.1.24:${a.self.port}');
    });

    test('explains what went wrong', () async {
      expect(() => a.connect('not a code!'), throwsA(isA<ConnectException>()));
      expect(
        () => a.connect('127.0.0.1:${a.self.port}'),
        throwsA(
          isA<ConnectException>().having(
            (e) => e.message,
            'message',
            contains('own code'),
          ),
        ),
      );
    });

    test('parseConnectCode', () {
      expect(parseConnectCode('192.168.1.24'), (
        host: '192.168.1.24',
        port: defaultServerPort,
      ));
      expect(parseConnectCode(' 10.0.0.5:4000 '), (
        host: '10.0.0.5',
        port: 4000,
      ));
      expect(parseConnectCode('24', localAddress: '192.168.1.110'), (
        host: '192.168.1.24',
        port: defaultServerPort,
      ));
      expect(parseConnectCode('24'), isNull); // no address to complete it
      expect(parseConnectCode('300', localAddress: '192.168.1.1'), isNull);
      expect(parseConnectCode('host/evil'), isNull);
      expect(parseConnectCode('1.2.3.4:99999'), isNull);
    });
  });

  test('settings survive a restart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = SharedPreferencesAsync();

    final first = WispService(
      prefs: prefs,
      saveDir: '${tmp.path}/first',
      port: 0,
      pagePort: 0,
    );
    await first.start(discovery: false);
    expect(first.startError, isNull);
    await first.rename('Studio Mac');
    expect(await first.setSaveDir(tmp.path), isTrue);
    expect(await first.setSaveDir('/definitely/not/here'), isFalse);
    await first.stop();

    final second = WispService(prefs: prefs, port: 0, pagePort: 0);
    await second.start(discovery: false);
    expect(second.startError, isNull);
    expect(second.self.id, first.self.id);
    expect(second.self.fingerprint, first.self.fingerprint);
    expect(second.self.name, 'Studio Mac');
    expect(second.saveDir, tmp.path);
    await second.stop();
  });

  test('safeRelativePath keeps folders but nothing sneaky', () {
    expect(safeRelativePath('Photos/2024/a.jpg'), 'Photos/2024/a.jpg');
    expect(safeRelativePath(r'Photos\a.jpg'), 'Photos/a.jpg');
    expect(safeRelativePath('../../etc/passwd'), 'etc/passwd');
    expect(safeRelativePath('/abs/./x.txt'), 'abs/x.txt');
    expect(safeRelativePath('../..'), 'file');
  });

  group('encryption', () {
    test(
      'the app port only speaks HTTPS, with the announced certificate',
      () async {
        expect(isFingerprint(b.self.fingerprint), isTrue);

        // Plain HTTP to the app port gets nowhere.
        final plain = HttpClient();
        await expectLater(() async {
          final req = await plain.getUrl(
            Uri.parse('http://127.0.0.1:${b.self.port}${Api.info}'),
          );
          await (await req.close()).drain<void>();
        }(), throwsA(anything));
        plain.close(force: true);

        // HTTPS works, and the certificate is the one B announced.
        String? seen;
        final tls =
            HttpClient(context: SecurityContext(withTrustedRoots: false))
              ..badCertificateCallback = (cert, host, port) {
                seen = certFingerprint(cert.der);
                return true;
              };
        final req = await tls.getUrl(
          Uri.parse('https://127.0.0.1:${b.self.port}${Api.info}'),
        );
        final res = await req.close();
        await res.drain<void>();
        tls.close();
        expect(res.statusCode, 200);
        expect(seen, b.self.fingerprint);
      },
    );

    test('a device with the wrong certificate is refused', () async {
      var asked = false;
      b.incoming.listen((r) {
        asked = true;
        r.accept();
      });

      // Pretend B announced a different certificate (someone posing as B).
      final impostor = bAsSeenByA().copyWith(fingerprint: 'a' * 64);
      final sent = a.send(impostor, [SharedFile.text('secret')]);
      await finished(sent);

      expect(sent.status, TransferStatus.failed);
      expect(sent.error, contains('Couldn\'t verify'));
      expect(asked, isFalse);
    });

    test('register refuses info that doesn\'t match the certificate', () async {
      // B claims a fingerprint that isn't its certificate's.
      final device = await WispClient(self: () => a.self)
          .register(bAsSeenByA().copyWith(fingerprint: 'b' * 64));
      expect(device, isNull);
    });
  });

  test('new devices get a random friendly name', () {
    final name = WispService().self.name;
    expect(name, matches(RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+$')));
  });
}
