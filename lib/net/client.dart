import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device.dart';
import '../models/transfer.dart';
import 'identity.dart';
import 'protocol.dart';

/// The sending side: talks to other devices' [WispServer]s.
class WispClient {
  WispClient({required this.self});

  final Device Function() self;

  /// Tells [peer] about us. Returns its info, or null if it didn't answer
  /// (or presented the wrong certificate).
  Future<Device?> register(Device peer) =>
      _exchange(peer, Api.register, body: self().toJson());

  /// Asks [peer] who it is, without telling it about us.
  Future<Device?> info(Device peer) => _exchange(peer, Api.info);

  /// One request to [path] that answers with device info. If [peer]'s
  /// fingerprint isn't known yet (typed-in code), whatever certificate it
  /// presents is trusted from now on — its info must name that same one.
  Future<Device?> _exchange(
    Device peer,
    String path, {
    Map<String, Object?>? body,
  }) async {
    String? presented;
    final client = _pinnedClient(
      peer,
      const Duration(seconds: 3),
      onCertificate: (fp) => presented = fp,
    );
    try {
      final req = body == null
          ? await client.getUrl(_uri(peer, path))
          : await client.postUrl(_uri(peer, path));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 5));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      final device = Device.fromJson(jsonDecode(text), host: peer.host);
      if (device == null || device.fingerprint != presented) return null;
      return device;
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// An HTTPS client that only accepts [peer]'s own certificate. With no
  /// fingerprint to compare against, it accepts any and reports it.
  static HttpClient _pinnedClient(
    Device peer,
    Duration timeout, {
    void Function(String fingerprint)? onCertificate,
  }) {
    // No trusted roots: every certificate goes through the callback.
    return HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, host, port) {
        final fingerprint = certFingerprint(cert.der);
        onCertificate?.call(fingerprint);
        return peer.fingerprint == null || fingerprint == peer.fingerprint;
      };
  }

  /// Runs [transfer] to completion, updating its status and progress.
  /// Never throws — failures end up in `transfer.status`/`transfer.error`.
  Future<void> send(Transfer transfer) async {
    final peer = transfer.peer;
    final sessionId = transfer.sessionId;
    if (peer.fingerprint == null) {
      transfer.setStatus(
        TransferStatus.failed,
        error: 'Couldn\'t verify ${peer.name}',
      );
      return;
    }
    final client = _pinnedClient(peer, const Duration(seconds: 5));
    HttpClientRequest? current;
    var cancelled = false;

    transfer.onCancel = () {
      cancelled = true;
      current?.abort();
      client.close(force: true);
      transfer.setStatus(TransferStatus.cancelled);
      _notifyCancel(peer, sessionId);
    };

    try {
      // 1. Offer the files and wait for the other person to decide.
      final req = current = await client.postUrl(_uri(peer, Api.prepareUpload));
      req.headers.contentType = ContentType.json;
      req.write(
        jsonEncode({
          'sessionId': sessionId,
          'code': transfer.securityCode,
          'info': self().toJson(),
          'files': [
            for (final (i, f) in transfer.files.indexed)
              {'id': '$i', 'name': f.name, 'size': f.bytes},
          ],
        }),
      );
      final res = await req.close().timeout(
        acceptTimeout + const Duration(seconds: 10),
      );
      final body = await res.transform(utf8.decoder).join();
      switch (res.statusCode) {
        case 200:
          break;
        case 403:
          transfer.setStatus(TransferStatus.declined);
          return;
        case 409:
          transfer.setStatus(
            TransferStatus.failed,
            error: '${peer.name} is busy with another request',
          );
          return;
        default:
          throw HttpException('Unexpected reply (${res.statusCode})');
      }
      final tokens = (jsonDecode(body) as Map)['tokens'] as Map;
      transfer.setStatus(TransferStatus.running);

      // 2. Upload the files one by one.
      for (final (i, file) in transfer.files.indexed) {
        if (cancelled) return;
        final req = current = await client.postUrl(
          _uri(peer, Api.upload, {
            'sessionId': sessionId,
            'fileId': '$i',
            'token': '${tokens['$i']}',
          }),
        );
        req.contentLength = file.bytes;
        req.headers.contentType = ContentType.binary;
        await req.addStream(
          file.openRead().map((chunk) {
            transfer.addProgress(i, chunk.length);
            return chunk;
          }),
        );
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode == 410) {
          transfer.setStatus(
            TransferStatus.cancelled,
            error: 'Cancelled on ${peer.name}',
          );
          return;
        }
        if (res.statusCode != 200) {
          throw HttpException('Upload failed (${res.statusCode})');
        }
      }
      transfer.setStatus(TransferStatus.done);
    } catch (e) {
      if (!cancelled) {
        transfer.setStatus(TransferStatus.failed, error: _describe(e, peer));
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _notifyCancel(Device peer, String sessionId) async {
    final client = _pinnedClient(peer, const Duration(seconds: 3));
    try {
      final req = await client.postUrl(
        _uri(peer, Api.cancel, {'sessionId': sessionId}),
      );
      await (await req.close()).drain<void>();
    } on Exception {
      // Best effort; the other side will notice the dropped connection.
    } finally {
      client.close(force: true);
    }
  }

  static Uri _uri(Device peer, String path, [Map<String, String>? query]) =>
      Uri(
        scheme: 'https',
        host: peer.host,
        port: peer.port,
        path: path,
        queryParameters: query,
      );

  static String _describe(Object e, Device peer) => switch (e) {
    TimeoutException() => '${peer.name} didn\'t answer',
    // Includes HandshakeException: the certificate didn't match.
    TlsException() =>
      'Couldn\'t verify ${peer.name} — it isn\'t using the certificate it '
          'announced',
    SocketException() => 'Couldn\'t reach ${peer.name}',
    HttpException() => 'Lost connection to ${peer.name}',
    _ => 'Transfer failed',
  };
}
