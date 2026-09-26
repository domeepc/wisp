import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/device.dart';
import '../models/shared_file.dart';
import '../models/transfer.dart';
import 'http_utils.dart';
import 'identity.dart';
import 'protocol.dart';

/// Someone wants to send us files; waiting for the user to decide.
class Offer {
  Offer({
    required this.sessionId,
    required this.from,
    required this.files,
    required this.securityCode,
  });

  final String sessionId;
  final Device from;

  /// Names and sizes only — the bytes arrive after accepting.
  final List<SharedFile> files;
  final String securityCode;
}

/// The receiving side: other devices send files here.
///
/// Two listeners: HTTPS for other Wisp apps (everything), and plain HTTP
/// for browsers (the page plus the upload endpoints — nothing else).
class WispServer {
  WispServer({
    required this.self,
    required this.onRegister,
    required this.onOffer,
    required this.onOfferCancelled,
    this.extraRoutes,
  });

  /// Handles requests the file protocol doesn't know (the browser page).
  /// Returns false to fall through to a 404.
  final Future<bool> Function(HttpRequest req)? extraRoutes;

  final Device Function() self;
  final void Function(Device device) onRegister;

  /// Asks the user. Returns the receiving [Transfer] if accepted, or null
  /// if declined (or this device is hidden).
  final Future<Transfer?> Function(Offer offer) onOffer;

  /// The sender gave up before the user decided.
  final void Function(String sessionId) onOfferCancelled;

  HttpServer? _secure;
  HttpServer? _plain;
  final _sessions = <String, _Session>{};
  String? _pendingOfferId;

  /// The HTTPS port other apps connect to.
  int get port => _secure?.port ?? 0;

  /// The plain-HTTP port for the browser page.
  int get browserPort => _plain?.port ?? 0;

  /// Listens on the given ports, or on any free ones if they're taken
  /// (e.g. a second copy of the app on the same computer).
  Future<void> start({
    required int port,
    required int browserPort,
    required SecurityContext tls,
  }) async {
    try {
      _secure = await HttpServer.bindSecure(InternetAddress.anyIPv4, port, tls);
    } on SocketException {
      _secure = await HttpServer.bindSecure(InternetAddress.anyIPv4, 0, tls);
    }
    try {
      _plain = await HttpServer.bind(InternetAddress.anyIPv4, browserPort);
    } on SocketException {
      _plain = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _secure!.listen((req) => _handle(req, secure: true));
    _plain!.listen((req) => _handle(req, secure: false));
  }

  Future<void> stop() async {
    await _secure?.close(force: true);
    await _plain?.close(force: true);
    _secure = null;
    _plain = null;
  }

  Future<void> _handle(HttpRequest req, {required bool secure}) async {
    try {
      if (!secure && await _cors(req)) return;
      switch ((req.method, req.uri.path)) {
        case ('GET', Api.info) when secure:
          await replyJson(req, 200, self().toJson());
        case ('POST', Api.register) when secure:
          await _register(req);
        case ('POST', Api.prepareUpload):
          await _prepareUpload(req, secure: secure);
        case ('POST', Api.upload):
          await _upload(req);
        case ('POST', Api.cancel):
          await _cancel(req);
        default:
          if (!secure && (await extraRoutes?.call(req) ?? false)) return;
          await replyJson(req, 404, {'error': 'Not found'});
      }
    } on HttpError catch (e) {
      await tryReplyJson(req, e.status, {'error': e.message});
    } catch (e) {
      await tryReplyJson(req, 500, {'error': 'Internal error'});
    }
  }

  /// Lets the Wisp app running in a browser (served from somewhere else,
  /// e.g. `flutter run -d chrome`) use the browser port. Only pages on
  /// this computer or the local network — anything else is refused, so a
  /// website can't make your browser send offers or connect as a device.
  /// Returns true if it already answered (a preflight).
  Future<bool> _cors(HttpRequest req) async {
    final origin = req.headers.value('origin');
    if (origin == null) return false; // not from a web page
    if (!isLocalOrigin(origin)) {
      throw const HttpError(403, 'Origin not allowed');
    }

    req.response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Vary', 'Origin');
    if (req.method != 'OPTIONS') return false;

    req.response
      ..statusCode = HttpStatus.noContent
      ..headers.set('Access-Control-Allow-Methods', 'GET, POST')
      ..headers.set('Access-Control-Allow-Headers', 'Content-Type')
      ..headers.set('Access-Control-Max-Age', '600');
    if (req.headers.value('access-control-request-private-network') == 'true') {
      req.response.headers.set('Access-Control-Allow-Private-Network', 'true');
    }
    await req.response.close();
    return true;
  }

  Future<void> _register(HttpRequest req) async {
    final device = Device.fromJson(
      await readJson(req),
      host: remoteAddress(req),
    );
    if (device == null) throw const HttpError(400, 'Bad device info');
    if (device.id != self().id) onRegister(device);
    await replyJson(req, 200, self().toJson());
  }

  Future<void> _prepareUpload(HttpRequest req, {required bool secure}) async {
    final body = await readJson(req);
    if (body is! Map) throw const HttpError(400, 'Bad request');

    final sessionId = body['sessionId'];
    final code = body['code'];
    final from = Device.fromJson(body['info'], host: remoteAddress(req));
    final rawFiles = body['files'];
    if (sessionId is! String ||
        sessionId.length < 16 ||
        sessionId.length > 64 ||
        code is! String ||
        code.length > 8 ||
        from == null ||
        rawFiles is! List ||
        rawFiles.isEmpty ||
        rawFiles.length > 10000) {
      throw const HttpError(400, 'Bad request');
    }

    final fileIds = <String>[];
    final files = <SharedFile>[];
    for (final f in rawFiles) {
      if (f is! Map) throw const HttpError(400, 'Bad file');
      final (id, name, size) = (f['id'], f['name'], f['size']);
      if (id is! String || name is! String || size is! int || size < 0) {
        throw const HttpError(400, 'Bad file');
      }
      fileIds.add(id);
      files.add(SharedFile(safeRelativePath(name), size));
    }

    // One question at a time.
    if (_pendingOfferId != null) throw const HttpError(409, 'Busy');
    _pendingOfferId = sessionId;
    final Transfer? accepted;
    try {
      accepted = await onOffer(
        Offer(
          sessionId: sessionId,
          from: from,
          files: files,
          // Over HTTPS the code comes from our own certificate, so it only
          // matches the sender's if they really connected to us. Browsers
          // (plain HTTP) can't check certificates; show their code as is.
          securityCode: secure
              ? securityCode(self().fingerprint ?? '', sessionId)
              : code,
        ),
      );
    } finally {
      _pendingOfferId = null;
    }
    if (accepted == null) throw const HttpError(403, 'Declined');
    final transfer = accepted;

    final session = _Session(
      transfer: transfer,
      host: remoteAddress(req),
      fileIndex: {for (final (i, id) in fileIds.indexed) id: i},
      tokens: {for (final id in fileIds) id: randomHex(16)},
    );
    _sessions[sessionId] = session;
    transfer.onCancel = () {
      session.cancelled = true;
      _sessions.remove(sessionId);
      transfer.setStatus(TransferStatus.cancelled);
    };
    transfer.setStatus(TransferStatus.running);

    await replyJson(req, 200, {'tokens': session.tokens});
  }

  Future<void> _upload(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final session = _sessions[q['sessionId']];
    if (session == null || session.host != remoteAddress(req)) {
      throw const HttpError(404, 'No such session');
    }
    final fileId = q['fileId'];
    final index = session.fileIndex[fileId];
    if (index == null || q['token'] != session.tokens[fileId]) {
      throw const HttpError(403, 'Bad token');
    }
    if (!session.started.add(index)) {
      throw const HttpError(409, 'Already uploaded');
    }

    final transfer = session.transfer;
    final expected = transfer.files[index].bytes;
    final file = _createUnique(transfer.saveDir!, transfer.files[index].name);
    final out = await file.open(mode: FileMode.write);
    var received = 0;
    var ok = false;
    try {
      await for (final chunk in req) {
        if (session.cancelled) throw const HttpError(410, 'Cancelled');
        received += chunk.length;
        if (received > expected) throw const HttpError(400, 'Too much data');
        await out.writeFrom(chunk);
        transfer.addProgress(index, chunk.length);
      }
      if (received != expected) throw const HttpError(400, 'Incomplete');
      ok = true;
    } on HttpError catch (e) {
      if (!session.cancelled) {
        transfer.setStatus(TransferStatus.failed, error: e.message);
      }
      rethrow;
    } on HttpException {
      // Sender disconnected mid-file.
      if (!session.cancelled) {
        transfer.setStatus(TransferStatus.failed, error: 'Connection lost');
      }
      rethrow;
    } finally {
      await out.close();
      if (!ok) await file.delete().catchError((_) => file);
    }

    transfer.savedPaths.add(file.path);
    if (transfer.savedPaths.length == transfer.files.length) {
      _sessions.remove(q['sessionId']);
      transfer.setStatus(TransferStatus.done);
    }
    await replyJson(req, 200, {});
  }

  Future<void> _cancel(HttpRequest req) async {
    final sessionId = req.uri.queryParameters['sessionId'];
    final session = _sessions[sessionId];
    if (session != null && session.host == remoteAddress(req)) {
      session.cancelled = true;
      _sessions.remove(sessionId);
      session.transfer.setStatus(
        TransferStatus.cancelled,
        error: 'Cancelled by ${session.transfer.peer.name}',
      );
    } else if (sessionId != null && sessionId == _pendingOfferId) {
      onOfferCancelled(sessionId);
    }
    await replyJson(req, 200, {});
  }

  /// Creates [relative] (a [safeRelativePath]) inside [dir], adding
  /// ` (1)`, ` (2)`… to the file name if it already exists.
  static File _createUnique(String dir, String relative) {
    final segments = relative.split('/');
    final name = segments.removeLast();
    final parent = Directory(p.joinAll([dir, ...segments]))
      ..createSync(recursive: true);

    // A folder that already existed could be a symlink pointing elsewhere.
    final root = Directory(dir).resolveSymbolicLinksSync();
    final real = parent.resolveSymbolicLinksSync();
    if (real != root && !p.isWithin(root, real)) {
      throw const HttpError(400, 'Bad path');
    }

    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var n = 0; ; n++) {
      final file = File(p.join(parent.path, n == 0 ? name : '$base ($n)$ext'));
      try {
        file.createSync(exclusive: true);
        return file;
      } on FileSystemException {
        if (!file.existsSync()) rethrow; // a real error, not a name clash
      }
    }
  }
}

/// Makes a file name from another device safe to save: no folders (so
/// "../../x" can't escape the downloads folder), no characters Windows
/// rejects, not empty.
String safeFileName(String name) {
  var safe = name
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_')
      .trim();
  if (safe.length > 200) safe = safe.substring(safe.length - 200);
  if (safe.isEmpty || safe == '.' || safe == '..') safe = 'file';
  return safe;
}

/// Like [safeFileName] but keeps folders, so a dropped folder arrives as a
/// folder: "Photos/2024/a.jpg". Every part is cleaned, and "..", "." and
/// empty parts are dropped, so the path always stays inside the downloads
/// folder.
String safeRelativePath(String path) {
  final parts = [
    for (final part in path.replaceAll('\\', '/').split('/'))
      if (part.trim().isNotEmpty && part.trim() != '.' && part.trim() != '..')
        safeFileName(part),
  ];
  if (parts.isEmpty) return 'file';
  // Deeply nested paths are almost certainly an attack or a mistake.
  return parts.skip(parts.length > 20 ? parts.length - 20 : 0).join('/');
}

class _Session {
  _Session({
    required this.transfer,
    required this.host,
    required this.fileIndex,
    required this.tokens,
  });

  final Transfer transfer;

  /// Only the device that made the offer may upload.
  final String host;
  final Map<String, int> fileIndex;
  final Map<String, String> tokens;
  final Set<int> started = {};
  bool cancelled = false;
}
