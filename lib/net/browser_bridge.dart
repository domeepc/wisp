import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/transfer.dart';
import '../utils/random_name.dart';
import 'http_utils.dart';
import 'protocol.dart';

abstract final class BrowserApi {
  static const hello = '/api/wisp/v1/browser/hello';
  static const inbox = '/api/wisp/v1/browser/inbox';
  static const download = '/api/wisp/v1/browser/download';
  static const bye = '/api/wisp/v1/browser/bye';
}

/// Lets devices without the app use Wisp from a web browser.
///
/// Serves the web app at `/app/`, and keeps a session per open browser
/// tab. The web app checks its inbox every couple of seconds, which is
/// also how the app knows the browser is still there. Files "sent" to a browser wait in
/// its inbox until it downloads them. Browsers *sending* files use the
/// normal prepare-upload/upload endpoints, so that needs nothing here.
class BrowserBridge {
  BrowserBridge({required this.host, required this.onChanged});

  /// This device, and whether it takes files right now.
  final ({Device device, bool receiving}) Function() host;

  /// Browsers came, went or were renamed.
  final VoidCallback onChanged;

  /// The Flutter web app (path → contents), served under `/app/`. Empty
  /// unless it was built into the app (see tool/build_web_app.sh).
  Map<String, List<int>> appFiles = const {};

  final _sessions = <String, _BrowserSession>{};

  /// Open browser tabs, as devices for the Nearby list.
  List<Device> get devices => [for (final s in _sessions.values) s.device];

  bool owns(String deviceId) => _sessions.containsKey(deviceId);

  /// Puts [transfer]'s files in the browser's inbox. The transfer runs
  /// while the browser downloads and is done once every file was fetched.
  void share(Transfer transfer) {
    final session = _sessions[transfer.peer.id];
    if (session == null) {
      transfer.setStatus(
        TransferStatus.failed,
        error: '${transfer.peer.name} closed the page',
      );
      return;
    }
    for (final i in transfer.files.indexed.map((e) => e.$1)) {
      session.items.add(_Item(id: randomHex(8), transfer: transfer, index: i));
    }
    transfer.onCancel = () {
      session.items.removeWhere((item) => item.transfer == transfer);
      transfer.setStatus(TransferStatus.cancelled);
    };
  }

  /// Drops browsers that stopped checking in.
  void prune() {
    final cutoff = DateTime.now().subtract(deviceTimeout);
    final gone = _sessions.values
        .where((s) => s.lastSeen.isBefore(cutoff))
        .toList();
    for (final session in gone) {
      _end(session);
    }
  }

  void _end(_BrowserSession session) {
    _sessions.remove(session.device.id);
    for (final item in session.items) {
      item.transfer.setStatus(
        TransferStatus.failed,
        error: '${session.device.name} closed the page',
      );
    }
    onChanged();
  }

  /// Handles the web app and the browser API. Returns false for anything
  /// else, so the server can answer 404.
  Future<bool> handle(HttpRequest req) async {
    final path = req.uri.path;
    switch ((req.method, path)) {
      case ('GET', '/' || '/app'):
        req.response.redirect(Uri(path: '/app/'), status: 301);
        await req.response.close();
      case ('GET', _) when path.startsWith('/app/'):
        await _serveAppFile(req, path.substring('/app/'.length));
      case ('POST', BrowserApi.hello):
        await _hello(req);
      case ('GET', BrowserApi.inbox):
        await _inbox(req);
      case ('GET', BrowserApi.download):
        await _download(req);
      case ('POST', BrowserApi.bye):
        _end(_auth(req));
        await replyJson(req, 200, {});
      default:
        return false;
    }
    return true;
  }

  Future<void> _serveAppFile(HttpRequest req, String name) async {
    final bytes = appFiles[name.isEmpty ? 'index.html' : name];
    if (bytes == null) {
      throw HttpError(
        404,
        appFiles.isEmpty
            ? 'The web app isn\'t built into this app'
            : 'Not found',
      );
    }
    final type = switch (name.split('.').last) {
      '' || 'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'json' => ContentType.json,
      'wasm' => ContentType('application', 'wasm'),
      'png' => ContentType('image', 'png'),
      'otf' => ContentType('font', 'otf'),
      'ttf' => ContentType('font', 'ttf'),
      _ => ContentType.binary,
    };
    req.response
      ..headers.contentType = type
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..headers.set('Referrer-Policy', 'no-referrer')
      // Flutter compiles WebAssembly and sets inline styles, and the app
      // talks to the other devices (plain http on the LAN), the signaling
      // server and its relay list, reads picked files (blob: URLs), and
      // fetches fallback fonts when there's internet.
      ..headers.set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; "
            "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
            "font-src 'self' data:; "
            "connect-src 'self' blob: http: https: wss:; "
            "worker-src 'self' blob:; object-src 'none'; base-uri 'self'; "
            "frame-ancestors 'none'; form-action 'none'",
      )
      ..add(bytes);
    await req.response.close();
  }

  Future<void> _hello(HttpRequest req) async {
    final body = await readJson(req);
    if (body is! Map) throw const HttpError(400, 'Bad request');
    final requestedName = _clean(body['name'], 40);
    final detail = _clean(body['detail'], 30);
    final id = body['id'];

    var session = id is String ? _sessions[id] : null;
    // Someone else's id without its token gets a fresh session instead.
    if (session != null && session.token != body['token']) session = null;

    // A page without a name yet gets a random one, which it then keeps.
    final name = requestedName ?? (session?.device.name) ?? randomDeviceName();

    if (session == null) {
      final newId = id is String && _validId.hasMatch(id) && !owns(id)
          ? id // keeps "always accept" working when the page comes back
          : randomHex(8);
      session = _BrowserSession(token: randomHex(16));
      _sessions[newId] = session;
      session.device = _device(newId, name, detail, req);
      onChanged();
    } else {
      final changed =
          session.device.name != name || session.device.detail != detail;
      session.device = _device(session.device.id, name, detail, req);
      if (changed) onChanged();
    }
    session.lastSeen = DateTime.now();

    await replyJson(req, 200, {
      'id': session.device.id,
      'token': session.token,
      'name': name,
      'host': _hostJson(),
    });
  }

  Future<void> _inbox(HttpRequest req) async {
    final session = _auth(req);
    session.lastSeen = DateTime.now();

    final items = [
      for (final item in session.items)
        if (item.transfer.status != TransferStatus.cancelled) _itemJson(item),
    ];
    await replyJson(req, 200, {'host': _hostJson(), 'items': items});
  }

  Future<void> _download(HttpRequest req) async {
    final session = _auth(req);
    final itemId = req.uri.queryParameters['item'];
    final item = session.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) throw const HttpError(404, 'No such file');

    final transfer = item.transfer;
    final file = transfer.files[item.index];
    if (transfer.status == TransferStatus.waiting) {
      transfer.setStatus(TransferStatus.running);
    }

    req.response
      // Always a download, never shown inline: an .html file shown on this
      // address could otherwise run scripts with the page's access.
      ..headers.contentType = ContentType.binary
      ..headers.set('Content-Disposition', contentDisposition(file.name))
      ..headers.set('X-Content-Type-Options', 'nosniff')
      ..headers.set('Cache-Control', 'no-store')
      ..contentLength = file.bytes;

    var sent = 0;
    try {
      await req.response.addStream(
        file.openRead().map((chunk) {
          sent += chunk.length;
          transfer.setFileProgress(item.index, sent);
          return chunk;
        }),
      );
      await req.response.close();
    } on Exception {
      return; // the browser cancelled or went away; it can try again
    }
    if (sent >= file.bytes) _delivered(item);
  }

  void _delivered(_Item item) {
    if (item.delivered) return;
    item.delivered = true;
    final transfer = item.transfer;
    transfer.setFileProgress(item.index, transfer.files[item.index].bytes);
    final all = _sessions.values
        .expand((s) => s.items)
        .where((i) => i.transfer == transfer);
    if (all.every((i) => i.delivered)) {
      transfer
        ..setStatus(TransferStatus.running)
        ..setStatus(TransferStatus.done);
    }
  }

  _BrowserSession _auth(HttpRequest req) {
    final q = req.uri.queryParameters;
    final session = _sessions[q['id']];
    if (session == null || q['token'] != session.token) {
      throw const HttpError(403, 'Unknown session');
    }
    return session;
  }

  Map<String, Object?> _hostJson() {
    final h = host();
    return {
      'id': h.device.id,
      'name': h.device.name,
      'platform': h.device.platform.name,
      'receiving': h.receiving,
    };
  }

  static Map<String, Object?> _itemJson(_Item item) {
    final file = item.transfer.files[item.index];
    return {
      'item': item.id,
      // Files sent together share a batch, so they're offered together.
      'batch': item.transfer.sessionId,
      'name': file.name,
      'size': file.bytes,
    };
  }

  static Device _device(
    String id,
    String name,
    String? detail,
    HttpRequest req,
  ) => Device(
    id: id,
    name: name,
    platform: DevicePlatform.browser,
    detail: detail,
    host: remoteAddress(req),
  );

  static final _validId = RegExp(r'^[0-9a-f]{8,32}$');

  /// Trims [value] and drops control characters; null if nothing's left.
  static String? _clean(Object? value, int maxLength) {
    if (value is! String) return null;
    var s = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    if (s.length > maxLength) s = s.substring(0, maxLength);
    return s.isEmpty ? null : s;
  }
}

/// `attachment; filename="…"; filename*=UTF-8''…` for [name]. The plain
/// name is ASCII-only with quotes and backslashes removed; the starred one
/// carries the real name for browsers that understand it (all current
/// ones). Folders in the name are dropped — browsers ignore them anyway.
String contentDisposition(String name) {
  final base = name.split('/').last;
  final ascii = base
      .replaceAll(RegExp(r'[^\x20-\x7e]'), '_')
      .replaceAll(RegExp(r'["\\]'), '_');
  final encoded = Uri.encodeComponent(base)
      .replaceAll("'", '%27')
      .replaceAll('(', '%28')
      .replaceAll(')', '%29');
  return 'attachment; filename="$ascii"; filename*=UTF-8\'\'$encoded';
}

class _BrowserSession {
  _BrowserSession({required this.token});

  final String token;
  late Device device;
  DateTime lastSeen = DateTime.now();
  final items = <_Item>[];
}

class _Item {
  _Item({required this.id, required this.transfer, required this.index});

  final String id;
  final Transfer transfer;
  final int index;
  bool delivered = false;
}
