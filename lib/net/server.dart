import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/device.dart';
import '../models/shared_file.dart';
import '../models/transfer.dart';
import 'batched_writer.dart';
import 'http_utils.dart';
import 'identity.dart';
import 'protocol.dart';
import 'transfer_mirror.dart';

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
///
/// The server itself runs on a background isolate (see [_ServerCore]), so
/// taking in files — TLS, HTTP, writing to disk — doesn't compete with
/// drawing the screen. This side answers its questions (who are we, does
/// the user accept?) and keeps the screens' [Transfer]s up to date.
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

  Isolate? _isolate;
  SendPort? _commands;
  Completer<void>? _exited;
  int _port = 0;

  /// Receiving transfers, by session id.
  final _transfers = <String, Transfer>{};

  /// The port other apps connect to.
  int get port => _port;

  /// Listens on [port], or on any free one if it's taken (e.g. a second
  /// copy of the app on the same computer).
  Future<void> start({required int port, required Identity identity}) async {
    final messages = ReceivePort();
    final ready = Completer<void>();
    final exited = _exited = Completer<void>();
    messages.listen((msg) {
      switch (msg) {
        case ('ready', final SendPort commands, final int port):
          _commands = commands;
          _port = port;
          ready.complete();
        case ('failed', final String error):
          if (!ready.isCompleted) ready.completeError(error);
        case ('self', final int id, _):
          _reply(id, self());
        case ('register', final Device device):
          onRegister(device);
        case ('offer', final int id, final Offer offer):
          _offer(id, offer);
        case ('offerCancelled', final String sessionId):
          onOfferCancelled(sessionId);
        case ('update', final String sessionId, final TransferUpdate update):
          final transfer = _transfers[sessionId];
          if (transfer == null) return;
          update.applyTo(transfer);
          if (!update.status.isActive) _transfers.remove(sessionId);
        case null: // the isolate is gone
          messages.close();
          _commands = null;
          for (final t in _transfers.values) {
            t.setStatus(TransferStatus.failed, error: 'Connection lost');
          }
          _transfers.clear();
          if (!ready.isCompleted) ready.completeError('Server stopped');
          exited.complete();
      }
    });
    _isolate = await Isolate.spawn(
      _serve,
      (reply: messages.sendPort, port: port, identity: identity),
      onExit: messages.sendPort,
      debugName: 'Wisp server',
    );
    await ready.future;
  }

  Future<void> stop() async {
    final commands = _commands;
    _commands = null;
    if (commands == null) return;
    commands.send('stop');
    await _exited!.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => _isolate?.kill(),
    );
  }

  Future<void> _offer(int id, Offer offer) async {
    Transfer? accepted;
    try {
      accepted = await onOffer(offer);
    } catch (_) {
      // Counts as declined.
    }
    if (accepted case final transfer?) {
      _transfers[offer.sessionId] = transfer;
      transfer.onCancel = () {
        _commands?.send(('cancel', offer.sessionId));
        transfer.setStatus(TransferStatus.cancelled);
      };
    }
    _reply(id, (accepted != null, accepted?.saveDir));
  }

  void _reply(int id, Object? value) => _commands?.send(('reply', id, value));

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

typedef _ServeJob = ({SendPort reply, int port, Identity identity});

/// The background isolate: runs the server, and asks [WispServer] on the
/// main isolate whatever only it knows.
Future<void> _serve(_ServeJob job) async {
  final commands = ReceivePort();
  final replies = <int, Completer<Object?>>{};
  var nextId = 0;
  Future<Object?> ask(String what, [Object? about]) {
    final id = nextId++;
    job.reply.send((what, id, about));
    return (replies[id] = Completer()).future;
  }

  final transfers = <String, Transfer>{};
  final core = _ServerCore(
    self: () async => await ask('self') as Device,
    onRegister: (device) => job.reply.send(('register', device)),
    onOffer: (offer) async {
      final (accepted, saveDir) = await ask('offer', offer) as (bool, String?);
      if (!accepted) return null;
      final id = offer.sessionId;
      final transfer = transfers[id] = Transfer(
        direction: TransferDirection.receive,
        peer: offer.from,
        files: offer.files,
        securityCode: offer.securityCode,
        sessionId: id,
        saveDir: saveDir,
      );
      mirrorTransfer(transfer, (update) {
        if (!update.status.isActive) transfers.remove(id);
        job.reply.send(('update', id, update));
      });
      return transfer;
    },
    onOfferCancelled: (id) => job.reply.send(('offerCancelled', id)),
  );

  commands.listen((msg) async {
    switch (msg) {
      case ('reply', final int id, final Object? value):
        replies.remove(id)?.complete(value);
      case ('cancel', final String sessionId):
        transfers[sessionId]?.cancel();
      case 'stop':
        await core.stop();
        Isolate.exit();
    }
  });
  try {
    await core.start(port: job.port, tls: job.identity.serverContext);
    job.reply.send(('ready', commands.sendPort, core.port));
  } catch (e) {
    job.reply.send(('failed', '$e'));
    Isolate.exit();
  }
}

/// The server itself, on the background isolate.
class _ServerCore {
  _ServerCore({
    required this.self,
    required this.onRegister,
    required this.onOffer,
    required this.onOfferCancelled,
  });

  final Future<Device> Function() self;
  final void Function(Device device) onRegister;
  final Future<Transfer?> Function(Offer offer) onOffer;
  final void Function(String sessionId) onOfferCancelled;

  HttpServer? _secure;
  final _sessions = <String, _Session>{};
  String? _pendingOfferId;

  int get port => _secure?.port ?? 0;

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
          await replyJson(req, 200, (await self()).toJson());
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
    final me = await self();
    if (device.id != me.id) onRegister(device);
    await replyJson(req, 200, me.toJson());
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
          securityCode: securityCode(
            (await self()).fingerprint ?? '',
            sessionId,
          ),
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
    final file = WispServer.createUnique(
      transfer.saveDir!,
      transfer.files[index].name,
    );
    final out = BatchedWriter(await file.open(mode: FileMode.write));
    var received = 0;
    var ok = false;
    try {
      await for (final chunk in req) {
        if (session.cancelled) throw const HttpError(410, 'Cancelled');
        received += chunk.length;
        if (received > expected) throw const HttpError(400, 'Too much data');
        await out.add(chunk);
        transfer.addProgress(index, chunk.length);
      }
      if (received != expected) throw const HttpError(400, 'Incomplete');
      await out.flush();
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
