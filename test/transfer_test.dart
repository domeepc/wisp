import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:wisp/models/device.dart';
import 'package:wisp/models/shared_file.dart';
import 'package:wisp/models/transfer.dart';
import 'package:wisp/net/client.dart';
import 'package:wisp/net/device_code.dart';
import 'package:wisp/net/identity.dart';
import 'package:wisp/net/protocol.dart';
import 'package:wisp/net/server.dart';
import 'package:wisp/net/signaling.dart';
import 'package:wisp/services/wisp_service.dart';
import 'package:wisp/utils/pick_files.dart';

/// Two Wisp services talking to each other over localhost.
void main() {
  late Directory tmp;
  late WispService a;
  late WispService b;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wisp_test');
    a = WispService(name: 'A', saveDir: '${tmp.path}/a', port: 0);
    b = WispService(name: 'B', saveDir: '${tmp.path}/b', port: 0);
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

  group('mid-transfer', () {
    // Big enough to still be going when the test steps in.
    late File big;
    setUp(() {
      big = File('${tmp.path}/big.bin')
        ..writeAsBytesSync(List.filled(64 * 1024 * 1024, 7));
      b.incoming.listen((r) => r.accept());
    });

    Future<void> until(bool Function() done, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) fail('Never: $what');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('the sender cancelling stops both sides', () async {
      final sent = a.send(bAsSeenByA(), [SharedFile.fromPath(big.path)]);
      await until(() => sent.bytesDone > 0, 'sending');
      sent.cancel();
      expect(sent.status, TransferStatus.cancelled);

      final received = b.transfers.single;
      await until(() => !received.status.isActive, 'receiver stopped');
      expect(received.status, isNot(TransferStatus.done));
      // The half-received file is cleaned up.
      await until(
        () => Directory('${tmp.path}/b').listSync().isEmpty,
        'partial file removed',
      );
    });

    test('the receiver cancelling stops both sides', () async {
      final sent = a.send(bAsSeenByA(), [SharedFile.fromPath(big.path)]);
      await until(() => b.transfers.isNotEmpty, 'offer');
      final received = b.transfers.single;
      await until(() => received.bytesDone > 0, 'receiving');
      received.cancel();
      expect(received.status, TransferStatus.cancelled);

      await until(() => !sent.status.isActive, 'sender stopped');
      expect(sent.status, isNot(TransferStatus.done));
    });

    test('stopping the app fails what it was receiving', () async {
      a.send(bAsSeenByA(), [SharedFile.fromPath(big.path)]);
      await until(() => b.transfers.isNotEmpty, 'offer');
      final received = b.transfers.single;
      await until(() => received.bytesDone > 0, 'receiving');
      await b.stop();
      expect(received.status, TransferStatus.failed);
    });
  });

  test('files only the main isolate can read are still sent', () async {
    b.incoming.listen((r) => r.accept());
    final data = List.generate(300 * 1024, (i) => i % 251);
    final sent = a.send(bAsSeenByA(), [
      SharedFile('stream.bin', data.length, source: () => Stream.value(data)),
      SharedFile.text('and some text'),
    ]);
    await finished(sent);

    expect(sent.status, TransferStatus.done, reason: sent.error);
    expect(File('${tmp.path}/b/stream.bin').readAsBytesSync(), data);
    expect(b.transfers.single.progress, 1);
  });

  test('uploads without a valid session are rejected', () async {
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    final req = await client.postUrl(
      Uri.parse(
        'https://127.0.0.1:${b.self.port}${Api.upload}'
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
    String codeOf(WispService s) =>
        encodeDeviceCode('127.0.0.1', port: s.self.port!)!;

    test('adds the device on both sides', () async {
      final device = await a.connect(codeOf(b));

      expect(device.name, 'B');
      // Learned from the certificate it presented.
      expect(device.fingerprint, b.self.fingerprint);
      expect(a.devices.single.name, 'B');
      expect(b.devices.single.name, 'A');
    });

    test('this device\'s code', () async {
      expect(WispService().connectCode, isNull); // not started yet
      a.localAddress = '192.168.1.24';
      final code = a.connectCode!;
      expect(code, isNot(contains('192')));
      expect(decodeDeviceCode(code), (host: '192.168.1.24', port: a.self.port));
    });

    test('connects with the other device\'s code', () async {
      b.localAddress = '127.0.0.1';
      final device = await a.connect(b.connectCode!.toLowerCase());
      expect(device.id, b.self.id);
    });

    test('explains what went wrong', () async {
      expect(() => a.connect('not a code!'), throwsA(isA<ConnectException>()));
      expect(
        () => a.connect(codeOf(a)),
        throwsA(
          isA<ConnectException>().having(
            (e) => e.message,
            'message',
            contains('own code'),
          ),
        ),
      );
    });
  });

  group('device codes', () {
    test('usual ports make a short code', () {
      final code = encodeDeviceCode('192.168.1.24')!;
      expect(code, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')));
      expect(decodeDeviceCode(code), (
        host: '192.168.1.24',
        port: defaultServerPort,
      ));
    });

    test('other ports make a longer one', () {
      final code = encodeDeviceCode('10.0.0.5', port: 40000)!;
      expect(code.replaceAll('-', ''), hasLength(12));
      expect(decodeDeviceCode(code), (host: '10.0.0.5', port: 40000));
    });

    test('typing is forgiving', () {
      final code = encodeDeviceCode('192.168.1.24')!;
      final sloppy = code
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('0', 'o')
          .replaceAll('1', 'l');
      expect(decodeDeviceCode(sloppy)?.host, '192.168.1.24');
    });

    test('a typo is caught, not sent somewhere else', () {
      final code = encodeDeviceCode('192.168.1.24')!.replaceAll('-', '');
      var caught = 0;
      for (var i = 0; i < code.length; i++) {
        final wrong = code[i] == 'X' ? 'Y' : 'X';
        final typo = code.replaceRange(i, i + 1, wrong);
        if (decodeDeviceCode(typo) == null) caught++;
      }
      expect(caught, code.length);
    });

    test('neighbours get different-looking codes', () {
      final a = encodeDeviceCode('192.168.1.24')!;
      final b = encodeDeviceCode('192.168.1.25')!;
      expect(a.substring(0, 4), isNot(b.substring(0, 4)));
    });

    test('only IPv4 addresses', () {
      expect(encodeDeviceCode('fe80::1'), isNull);
      expect(encodeDeviceCode('my-pc.local'), isNull);
      expect(decodeDeviceCode('192.168.1.24'), isNull);
      expect(decodeDeviceCode('ABCD'), isNull);
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
    );
    await first.start(discovery: false);
    expect(first.startError, isNull);
    await first.rename('Studio Mac');
    expect(await first.setSaveDir(tmp.path), isTrue);
    expect(await first.setSaveDir('/definitely/not/here'), isFalse);
    await first.stop();

    final second = WispService(prefs: prefs, port: 0);
    await second.start(discovery: false);
    expect(second.startError, isNull);
    expect(second.self.id, first.self.id);
    expect(second.self.fingerprint, first.self.fingerprint);
    expect(second.self.name, 'Studio Mac');
    expect(second.saveDir, tmp.path);
    await second.stop();
  });

  test('offered files are checked and made safe', () {
    final files = parseOfferedFiles([
      {'name': '../../etc/passwd', 'size': 3},
      {'name': 'Photos/a.jpg', 'size': 0},
    ])!;
    expect([for (final f in files) f.name], ['etc/passwd', 'Photos/a.jpg']);
    expect(parseOfferedFiles([]), isNull);
    expect(parseOfferedFiles('x'), isNull);
    expect(
      parseOfferedFiles([
        {'name': 'a', 'size': -1},
      ]),
      isNull,
    );
    expect(
      parseOfferedFiles([
        {'name': 'a'},
      ]),
      isNull,
    );
  });

  test('both ends of WebRTC get the same security code', () {
    const a = 'v=0\r\na=fingerprint:sha-256 AA:BB\r\n';
    const b = 'v=0\r\na=fingerprint:sha-256 CC:DD\r\n';
    expect(rtcSecurityCode(a, b), rtcSecurityCode(b, a));
    expect(rtcSecurityCode(a, b), hasLength(4));
    expect(rtcSecurityCode(a, b), isNot(rtcSecurityCode(a, a)));
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
