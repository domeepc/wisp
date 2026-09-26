import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:wisp/models/device.dart';
import 'package:wisp/models/shared_file.dart';
import 'package:wisp/models/transfer.dart';
import 'package:wisp/net/browser/browser_http.dart';
import 'package:wisp/net/browser/web_links.dart';
import 'package:wisp/services/wisp_service.dart';

/// [BrowserHttp] for tests, on dart:io instead of a browser.
class _IoBrowserHttp implements BrowserHttp {
  /// Contents of every "download" the web client started.
  final downloads = <String>[];

  @override
  String get browserName => 'TestBrowser';

  @override
  Future<({int status, String body})> send(
    String method,
    Uri url, {
    String? json,
    void Function(void Function() abort)? onStart,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, url);
      onStart?.call(() => req.abort());
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(json);
      }
      final res = await req.close();
      return (
        status: res.statusCode,
        body: await res.transform(utf8.decoder).join(),
      );
    } on Exception catch (e) {
      throw BrowserHttpException('$e');
    } finally {
      client.close();
    }
  }

  @override
  Future<int> upload(
    Uri url,
    Uint8List bytes, {
    required void Function(int sent) onProgress,
    void Function(void Function() abort)? onStart,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(url);
      onStart?.call(() => req.abort());
      req
        ..contentLength = bytes.length
        ..add(bytes);
      final res = await req.close();
      await res.drain<void>();
      onProgress(bytes.length);
      return res.statusCode;
    } finally {
      client.close();
    }
  }

  @override
  void download(Uri url) {
    send('GET', url).then((res) => downloads.add(res.body));
  }
}

/// The Wisp app "in a browser" (web mode) talking to a normal Wisp app.
void main() {
  late Directory tmp;
  late WispService host;
  late WispService web;
  late _IoBrowserHttp http;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wisp_web_test');
    host = WispService(
      name: 'Bright Fox',
      saveDir: tmp.path,
      port: 0,
      pagePort: 0,
      loadWebFiles: () async => {},
    );
    await host.start(discovery: false);
    http = _IoBrowserHttp();
    web = WispService(name: 'Merry Hedgehog', browserHttp: http);
    await web.start();
  });

  tearDown(() async {
    await web.stop();
    await host.stop();
    await tmp.delete(recursive: true);
  });

  Future<void> until(bool Function() done, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $what');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<Device> connect() => web.connect('127.0.0.1:${host.browserPort}');

  test('connects by address; both sides see each other', () async {
    expect(web.isWebClient, isTrue);
    expect(web.self.platform, DevicePlatform.browser);

    final device = await connect();

    expect(device.name, 'Bright Fox');
    expect(device.id, host.self.id);
    expect(web.devices.single.name, 'Bright Fox');
    final browser = host.devices.single;
    expect(browser.name, 'Merry Hedgehog');
    expect(browser.subtitle, 'Browser · TestBrowser');
    // It keeps its own id there, so "always accept" survives restarts.
    expect(browser.id, web.self.id);
  });

  test('a wrong address explains itself', () async {
    await expectLater(
      web.connect('127.0.0.1:1'),
      throwsA(isA<ConnectException>()),
    );
    await expectLater(
      web.connect('not an address!'),
      throwsA(isA<ConnectException>()),
    );
  });

  test('sends files through the normal accept flow', () async {
    final device = await connect();
    Transfer? received;
    host.incoming.listen((request) async {
      expect(request.offer.from.name, 'Merry Hedgehog');
      request.accept();
      received = await request.transfer;
    });

    final sent = web.send(device, [
      SharedFile.text('from the browser', name: 'web.txt'),
    ]);
    await until(() => !sent.status.isActive, 'send');

    expect(sent.status, TransferStatus.done, reason: sent.error);
    expect(File('${tmp.path}/web.txt').readAsStringSync(), 'from the browser');
    expect(received?.securityCode, sent.securityCode);
    expect(sent.securityCode, hasLength(4));
  });

  test('declined sends say so', () async {
    final device = await connect();
    host.incoming.listen((request) => request.decline());

    final sent = web.send(device, [SharedFile.text('nope')]);
    await until(() => !sent.status.isActive, 'send');

    expect(sent.status, TransferStatus.declined);
  });

  test('files shared with the browser are offered, then downloaded', () async {
    await connect();
    final shared = host.send(host.devices.single, [
      SharedFile.text('one', name: 'a.txt'),
      SharedFile.text('two', name: 'b.txt'),
    ]);

    final request = await web.incoming.first.timeout(
      const Duration(seconds: 8),
    );
    expect(request.offer.from.name, 'Bright Fox');
    expect(request.offer.files.map((f) => f.name), ['a.txt', 'b.txt']);
    expect(request.offer.securityCode, isEmpty);

    request.accept();
    final transfer = (await request.transfer)!;
    await until(() => http.downloads.length == 2, 'downloads');
    await until(() => transfer.status == TransferStatus.done, 'done');

    expect(http.downloads, unorderedEquals(['one', 'two']));
    expect(shared.status, TransferStatus.done);
  });

  test('a declined share isn\'t downloaded or asked again', () async {
    await connect();
    host.send(host.devices.single, [SharedFile.text('x', name: 'x.txt')]);

    var asked = 0;
    web.incoming.listen((request) {
      asked++;
      request.decline();
    });
    await until(() => asked == 1, 'offer');
    await Future<void>.delayed(WebLinks.pollEvery * 2);

    expect(asked, 1);
    expect(http.downloads, isEmpty);
  });

  test('parseBrowserAddress', () {
    expect(
      parseBrowserAddress('192.168.1.24'),
      Uri.parse('http://192.168.1.24:53319'),
    );
    // The app's own code (HTTPS port) maps to the browser port.
    expect(
      parseBrowserAddress('192.168.1.24:53318'),
      Uri.parse('http://192.168.1.24:53319'),
    );
    expect(
      parseBrowserAddress('http://192.168.1.24:4000/'),
      Uri.parse('http://192.168.1.24:4000'),
    );
    expect(parseBrowserAddress('https://192.168.1.24'), isNull);
    expect(parseBrowserAddress('bad host!'), isNull);
    expect(parseBrowserAddress(''), isNull);
  });
}
