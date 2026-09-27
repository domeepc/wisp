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

/// The receiving side: other Wisp apps send files here, over HTTPS.
class WispServer {
  WispServer({
    required this.self,
    required this.onRegister,
    required this.onOffer,
    required this.onOfferCancelled,
  });

  final Device Function() self;
  final void Function(Device device) onRegister;

  /// Asks the user. Returns the receiving [Transfer] if accepted, or null
  /// if declined (or this device is hidden).
  final Future<Transfer?> Function(Offer offer) onOffer;

  /// The sender gave up before the user decided.
  final void Function(String sessionId) onOfferCancelled;

  HttpServer? _secure;
  final _sessions = <String, _Session>{};
  String? _pendingOfferId;

  /// The port other apps connect to.
  int get port => _secure?.port ?? 0;

  /// Listens on [port], or on any free one if it's taken (e.g. a second
  /// copy of the app on the same computer).
  Future<void> start({required int port, required SecurityContext tls}) async {
    try {
      _secure = await HttpServer.bindSecure(InternetAddress.anyIPv4, port, tls);
    } on SocketException {
      _secure = await HttpServer.bindSecure(InternetAddress.anyIPv4, 0, tls);
    }
    _secure!.listen(_handle);
  }

  Future<void> stop() async {
    await _secure?.close(force: true);
    _secure = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch ((req.method, req.uri.path)) {
        case ('GET', Api.info):
          await replyJson(req, 200, self().toJson());
        case ('POST', Api.register):
          await _register(req);
        case ('POST', Api.prepareUpload):
          await _prepareUpload(req);
        case ('POST', Api.upload):
          await _upload(req);
        case ('POST', Api.cancel):
          await _cancel(req);
        default:
          await replyJson(req, 404, {'error': 'Not found'});
      }
    } on HttpError catch (e) {
      await tryReplyJson(req, e.status, {'error': e.message});
    } catch (e) {
      await tryReplyJson(req, 500, {'error': 'Internal error'});
    }
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

  Future<void> _prepareUpload(HttpRequest req) async {
    final body = await readJson(req);
    if (body is! Map) throw const HttpError(400, 'Bad request');

    final sessionId = body['sessionId'];
    final from = Device.fromJson(body['info'], host: remoteAddress(req));
    final rawFiles = body['files'];
    final files = parseOfferedFiles(rawFiles);
    final fileIds = [
      if (files != null)
        for (final f in rawFiles as List)
          if ((f as Map)['id'] case final String id) id,
    ];
    if (sessionId is! String ||
        sessionId.length < 16 ||
        sessionId.length > 64 ||
        from == null ||
        files == null ||
        fileIds.length != files.length) {
      throw const HttpError(400, 'Bad request');
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
          // It comes from our own certificate, so it only matches the
          // sender's if they really connected to us.
          securityCode: securityCode(self().fingerprint ?? '', sessionId),
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
    final file = createUnique(transfer.saveDir!, transfer.files[index].name);
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
  static File createUnique(String dir, String relative) {
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

/// The files someone offers, `[{name, size}, …]`: names made safe, and
/// null if anything is off.
List<SharedFile>? parseOfferedFiles(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > 10000) return null;
  final files = <SharedFile>[];
  for (final f in raw) {
    if (f case {'name': final String name, 'size': final int size}
        when size >= 0) {
      files.add(SharedFile(safeRelativePath(name), size));
    } else {
      return null;
    }
  }
  return files;
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
