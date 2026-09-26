import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:wisp/models/device.dart';
import 'package:wisp/models/shared_file.dart';
import 'package:wisp/models/transfer.dart';
import 'package:wisp/net/browser_bridge.dart';
import 'package:wisp/net/http_utils.dart';
import 'package:wisp/net/protocol.dart';
import 'package:wisp/services/wisp_service.dart';

/// Talks to a real [WispService] the way the browser page's app.js does.
void main() {
  late Directory tmp;
  late WispService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wisp_browser_test');
    service = WispService(
      name: 'MacBook Pro',
      saveDir: tmp.path,
      port: 0,
      pagePort: 0,
      loadWebFiles: () async => {
        for (final name in webFileNames)
          name: File('assets/web/$name').readAsBytesSync(),
        // A stand-in for the web app tool/build_web_app.sh packs in.
        'app/index.html': utf8.encode('<title>Wisp</title>'),
        'app/canvaskit/canvaskit.wasm': [0, 97, 115, 109],
      },
    );
    await service.start(discovery: false);
    expect(service.startError, isNull);
  });

  tearDown(() async {
    await service.stop();
    await tmp.delete(recursive: true);
  });

  Future<({int status, HttpHeaders headers, List<int> body})> call(
    String method,
    String path, {
    Object? json,
    List<int>? bytes,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${service.browserPort}$path'),
      );
      req.followRedirects = false;
      headers.forEach(req.headers.set);
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(json));
      }
      if (bytes != null) {
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close();
      final body = await res.fold<List<int>>([], (all, b) => all..addAll(b));
      return (status: res.statusCode, headers: res.headers, body: body);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> callJson(
    String method,
    String path, {
    Object? json,
  }) async {
    final res = await call(method, path, json: json);
    expect(res.status, 200, reason: utf8.decode(res.body));
    return jsonDecode(utf8.decode(res.body)) as Map<String, dynamic>;
  }

  /// Opens the page: returns the session's query string.
  Future<String> hello({String name = 'iPad', String detail = 'Safari'}) async {
    final body = await callJson(
      'POST',
      BrowserApi.hello,
      json: {'name': name, 'detail': detail},
    );
    return 'id=${body['id']}&token=${body['token']}';
  }

  Future<List<dynamic>> inbox(String auth) async =>
      (await callJson('GET', '${BrowserApi.inbox}?$auth'))['items']
          as List<dynamic>;

  test('serves the page with a strict security policy', () async {
    final page = await call('GET', '/');
    expect(page.status, 200);
    expect(page.headers.contentType?.mimeType, 'text/html');
    expect(
      page.headers.value('content-security-policy'),
      contains("script-src 'self'"),
    );
    expect(utf8.decode(page.body), contains('Shared with you'));

    final script = await call('GET', '/web/app.js');
    expect(script.status, 200);
    expect(script.headers.contentType?.mimeType, 'text/javascript');

    expect((await call('GET', '/web/nope.js')).status, 404);
    expect((await call('GET', '/web/../pubspec.yaml')).status, 404);
  });

  test('a browser shows up as a device and leaves on bye', () async {
    final auth = await hello(name: 'iPad', detail: 'Safari');

    final device = service.devices.single;
    expect(device.name, 'iPad');
    expect(device.subtitle, 'Browser · Safari');
    expect(device.host, '127.0.0.1');

    final res = await call('POST', '${BrowserApi.bye}?$auth');
    expect(res.status, 200);
    expect(service.devices, isEmpty);
  });

  test('the inbox needs the right token', () async {
    final auth = await hello();
    final id = RegExp('id=([^&]+)').firstMatch(auth)!.group(1);

    final res = await call('GET', '${BrowserApi.inbox}?id=$id&token=wrong');
    expect(res.status, 403);

    // Claiming someone's id without their token gets a new session.
    final other = await callJson(
      'POST',
      BrowserApi.hello,
      json: {'id': id, 'name': 'Sneaky'},
    );
    expect(other['id'], isNot(id));
    expect(service.devices.map((d) => d.name), containsAll(['iPad', 'Sneaky']));
  });

  test('files sent to a browser can be downloaded', () async {
    final auth = await hello();
    final source = File('${tmp.path}/report.pdf')
      ..writeAsBytesSync(List.generate(200000, (i) => i % 256));

    final transfer = service.send(service.devices.single, [
      SharedFile.fromPath(source.path),
    ]);
    expect(transfer.status, TransferStatus.waiting);

    final items = await inbox(auth);
    expect(items.single['name'], 'report.pdf');
    expect(items.single['kind'], 'file');
    expect(items.single['size'], 200000);

    final download = await call(
      'GET',
      '${BrowserApi.download}?$auth&item=${items.single['item']}',
    );
    expect(download.status, 200);
    expect(download.body, source.readAsBytesSync());
    expect(download.headers.contentType?.mimeType, 'application/octet-stream');
    expect(
      download.headers.value('content-disposition'),
      startsWith('attachment; filename="report.pdf"'),
    );
    expect(transfer.status, TransferStatus.done);
    expect(transfer.progress, 1);
  });

  test('text shows up inline and counts as delivered', () async {
    final auth = await hello();
    final transfer = service.send(service.devices.single, [
      SharedFile.text('https://github.com/\nsecond line'),
    ]);

    final item = (await inbox(auth)).single;
    expect(item['kind'], 'text');
    expect(item['text'], 'https://github.com/\nsecond line');
    expect(transfer.status, TransferStatus.done);
  });

  test('cancelling on the app takes the files back', () async {
    final auth = await hello();
    final transfer = service.send(service.devices.single, [
      const SharedFile('a.txt', 1),
    ]);
    expect(await inbox(auth), hasLength(1));

    transfer.cancel();
    expect(transfer.status, TransferStatus.cancelled);
    expect(await inbox(auth), isEmpty);
  });

  test('closing the page fails what it never downloaded', () async {
    final auth = await hello();
    final transfer = service.send(service.devices.single, [
      const SharedFile('a.txt', 1),
    ]);

    await call('POST', '${BrowserApi.bye}?$auth');
    expect(transfer.status, TransferStatus.failed);
    expect(transfer.error, 'iPad closed the page');
  });

  test('a browser can send files through the normal accept flow', () async {
    await hello();
    final browserId = service.devices.single.id;
    service.incoming.listen((request) {
      expect(request.offer.from.name, 'iPad');
      expect(request.offer.from.platform, DevicePlatform.browser);
      request.accept();
    });

    // What app.js sends.
    final sessionId = randomHex(16);
    final prepared = await callJson(
      'POST',
      Api.prepareUpload,
      json: {
        'sessionId': sessionId,
        'code': 'AB12',
        'info': {
          'id': browserId,
          'name': 'iPad',
          'platform': 'browser',
          'detail': 'Safari',
          'port': 0,
        },
        'files': [
          {'id': '0', 'name': 'photo.jpg', 'size': 5},
        ],
      },
    );
    final token = (prepared['tokens'] as Map)['0'];
    final upload = await call(
      'POST',
      '${Api.upload}?sessionId=$sessionId&fileId=0&token=$token',
      bytes: utf8.encode('hello'),
    );

    expect(upload.status, 200);
    expect(File('${tmp.path}/photo.jpg').readAsStringSync(), 'hello');
  });

  test('contentDisposition is safe for any file name', () {
    expect(
      contentDisposition('report.pdf'),
      'attachment; filename="report.pdf"; filename*=UTF-8\'\'report.pdf',
    );
    final evil = contentDisposition('a"b\\c\r\nSet-Cookie: x.html');
    expect(evil, isNot(contains('\r')));
    expect(evil, isNot(contains('\n')));
    expect(
      evil,
      startsWith('attachment; filename="a_b_c__Set-Cookie: x.html"'),
    );
    expect(
      contentDisposition('Trip/Zürich ✓.pdf'),
      'attachment; filename="Z_rich _.pdf"; '
      'filename*=UTF-8\'\'Z%C3%BCrich%20%E2%9C%93.pdf',
    );
  });

  test('the browser address', () {
    service.localAddress = '192.168.1.24';
    expect(service.browserUrl, 'http://192.168.1.24:${service.browserPort}');
  });

  test('the web app is served under /app/', () async {
    service.localAddress = '192.168.1.24';
    expect(
      service.webAppUrl,
      'http://192.168.1.24:${service.browserPort}/app/',
    );

    final redirect = await call('GET', '/app');
    expect(redirect.status, 301);
    expect(redirect.headers.value('location'), '/app/');

    final index = await call('GET', '/app/');
    expect(index.status, 200);
    expect(utf8.decode(index.body), '<title>Wisp</title>');
    expect(index.headers.contentType?.mimeType, 'text/html');
    expect(
      index.headers.value('content-security-policy'),
      contains("'wasm-unsafe-eval'"),
    );

    final wasm = await call('GET', '/app/canvaskit/canvaskit.wasm');
    expect(wasm.headers.contentType?.mimeType, 'application/wasm');
    expect(wasm.body, [0, 97, 115, 109]);

    expect((await call('GET', '/app/missing.js')).status, 404);
    // The simple page is still at the root.
    expect(utf8.decode((await call('GET', '/')).body), contains('Wisp'));
  });

  test('a page without a name gets a random one', () async {
    final body = await callJson(
      'POST',
      BrowserApi.hello,
      json: {'detail': 'Chrome'},
    );

    expect(body['name'], matches(RegExp(r'^[A-Z][a-z]+ [A-Z][a-z]+$')));
    expect(service.devices.single.name, body['name']);
  });

  test('the file protocol isn\'t reachable over plain HTTP', () async {
    expect((await call('GET', Api.info)).status, 404);
    expect((await call('POST', Api.register, json: {})).status, 404);
  });

  group('the Wisp app in a browser, served from elsewhere', () {
    test('local pages may call the API (CORS)', () async {
      final preflight = await call(
        'OPTIONS',
        BrowserApi.hello,
        headers: {
          'Origin': 'http://localhost:5000',
          'Access-Control-Request-Method': 'POST',
          'Access-Control-Request-Private-Network': 'true',
        },
      );
      expect(preflight.status, 204);
      expect(
        preflight.headers.value('access-control-allow-origin'),
        'http://localhost:5000',
      );
      expect(
        preflight.headers.value('access-control-allow-private-network'),
        'true',
      );

      final hello = await call(
        'POST',
        BrowserApi.hello,
        json: {'name': 'Web'},
        headers: {'Origin': 'http://192.168.1.50:8080'},
      );
      expect(hello.status, 200);
      expect(
        hello.headers.value('access-control-allow-origin'),
        'http://192.168.1.50:8080',
      );
    });

    test('websites on the internet are refused', () async {
      final res = await call(
        'POST',
        BrowserApi.hello,
        json: {'name': 'Evil'},
        headers: {'Origin': 'https://evil.example'},
      );
      expect(res.status, 403);
      expect(res.headers.value('access-control-allow-origin'), isNull);
      expect(service.devices, isEmpty);
    });

    test('isLocalOrigin', () {
      expect(isLocalOrigin('http://localhost:1234'), isTrue);
      expect(isLocalOrigin('http://127.0.0.1'), isTrue);
      expect(isLocalOrigin('http://192.168.1.5:80'), isTrue);
      expect(isLocalOrigin('https://10.0.0.2'), isTrue);
      expect(isLocalOrigin('http://172.20.1.1'), isTrue);
      expect(isLocalOrigin('http://172.32.1.1'), isFalse);
      expect(isLocalOrigin('https://example.com'), isFalse);
      expect(isLocalOrigin('http://192.168.1.5.evil.com'), isFalse);
      expect(isLocalOrigin('null'), isFalse);
    });
  });
}
