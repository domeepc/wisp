import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/device.dart';
import '../models/transfer.dart';
import 'rtc_platform_io.dart'
    if (dart.library.js_interop) 'rtc_platform_web.dart';
import 'server.dart' show Offer, parseOfferedFiles;
import 'signaling.dart';

export 'rtc_platform_io.dart'
    if (dart.library.js_interop) 'rtc_platform_web.dart'
    show browserName;

/// Devices in our room on the signaling server (the same network), and
/// WebRTC data channels to them. The web app finds everyone this way;
/// installed apps find browsers, and devices the Wi-Fi hides.
///
/// Files go straight between the devices, encrypted by WebRTC. The
/// security code comes from both ends' DTLS fingerprints, so if the
/// signaling server meddled, the codes wouldn't match.
class RtcPeers {
  RtcPeers({
    required this.self,
    required this.onChanged,
    required this.onOffer,
  }) {
    _signaling = Signaling(
      self: () => {
        'id': self().id,
        'name': self().name,
        'platform': self().platform.name,
        'detail': self().detail,
      },
      onPeers: _onPeers,
      onSignal: _onSignal,
    );
  }

  final Device Function() self;
  final VoidCallback onChanged;

  /// Asks the user about files sent to us; null means declined.
  final Future<Transfer?> Function(Offer offer) onOffer;

  late final Signaling _signaling;
  var _peers = <String, RoomPeer>{};
  final _sessions = <String, _Session>{};
  bool _asking = false;

  List<Device> get devices => [for (final p in _peers.values) _device(p)];

  bool owns(String id) => _peers.containsKey(id);

  /// Paused (hidden): out of the room, so nobody sees us.
  set paused(bool value) {
    if (value) return _signaling.stop();
    _signaling.start();
    // Fetched ahead, so a transfer doesn't wait for it (see _iceServers).
    unawaited(_iceServers());
  }

  void stop() {
    _signaling.stop();
    _sessions.values.toList().forEach(_end);
  }

  void renamed() => _signaling.announce();

  void _onPeers(List<RoomPeer> peers) {
    final me = self().id;
    _peers = {
      for (final p in peers)
        if (p.id != me) p.id: p,
    };
    onChanged();
  }

  static Device _device(RoomPeer p) => Device(
    id: p.id,
    name: p.name,
    platform: DevicePlatform.fromName(p.platform),
    detail: p.detail,
  );

  /// Sends [t]'s files to someone in the room.
  Future<void> send(Transfer t) async {
    if (!owns(t.peer.id)) {
      return t.setStatus(TransferStatus.failed, error: '${t.peer.name} left');
    }
    final s = _open(t.sessionId, t.peer.id);
    t.onCancel = () {
      s.sendJson({'type': 'cancel'});
      _end(s);
      t.setStatus(TransferStatus.cancelled);
    };
    try {
      final pc = await s.pc;
      s.attach(await pc.createDataChannel('wisp', RTCDataChannelInit()));
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _signal(s, {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
      await s.opened.timeout(const Duration(seconds: 20));
      t.setSecurityCode(await _code(pc));
      s.sendJson({
        'type': 'offer',
        'files': [
          for (final f in t.files) {'name': f.name, 'size': f.bytes},
        ],
      });
      // Until they tap Accept or Decline.
      if ((await s.nextJson())['type'] != 'accept') {
        return t.setStatus(TransferStatus.declined);
      }
      t.setStatus(TransferStatus.running);
      for (final (i, file) in t.files.indexed) {
        var sent = 0;
        await for (final chunk in file.openRead()) {
          for (var at = 0; at < chunk.length; at += _chunkSize) {
            if (!t.status.isActive) return;
            final end = min(at + _chunkSize, chunk.length);
            await s.roomToSend(end - at);
            await s.channel!.send(
              RTCDataChannelMessage.fromBinary(_piece(chunk, at, end)),
            );
            sent += end - at;
            t.setFileProgress(i, sent);
          }
        }
      }
      // Done when they have it all, not when it left here.
      if ((await s.nextJson())['type'] != 'got') throw const _Lost();
      t.setStatus(TransferStatus.done);
    } on Object {
      if (t.status.isActive) {
        t.setStatus(
          TransferStatus.failed,
          error: 'Lost connection to ${t.peer.name}',
        );
      }
    } finally {
      _end(s);
    }
  }

  /// Someone is sending to us: runs the whole transfer.
  Future<void> _receive(_Session s) async {
    Transfer? t;
    try {
      final offer = await s.nextJson().timeout(const Duration(seconds: 30));
      final peer = _peers[s.peer];
      final files = offer['type'] == 'offer'
          ? parseOfferedFiles(offer['files'])
          : null;
      if (peer == null || files == null) return;
      // One question at a time.
      if (_asking) return s.sendJson({'type': 'decline'});
      _asking = true;
      try {
        t = await onOffer(
          Offer(
            sessionId: s.id,
            from: _device(peer),
            files: files,
            securityCode: await _code(await s.pc),
          ),
        );
      } finally {
        _asking = false;
      }
      if (t == null) return s.sendJson({'type': 'decline'});
      final transfer = t;
      transfer.onCancel = () {
        s.sendJson({'type': 'cancel'});
        _end(s);
        transfer.setStatus(TransferStatus.cancelled);
      };
      s.sendJson({'type': 'accept'});
      transfer.setStatus(TransferStatus.running);
      // Files come one after another, each exactly as big as offered.
      for (final (i, file) in files.indexed) {
        final out = await ReceivedFile.create(transfer.saveDir, file.name);
        var ok = false;
        try {
          for (var got = 0; got < file.bytes;) {
            final part = await s.nextBinary();
            got += part.length;
            if (got > file.bytes) throw const _Lost();
            await out.add(part);
            transfer.setFileProgress(i, got);
          }
          ok = true;
        } finally {
          if (!ok) await out.abort();
        }
        if (await out.close() case final path?) transfer.savedPaths.add(path);
      }
      s.sendJson({'type': 'got'});
      transfer.setStatus(TransferStatus.done);
      // Give "got" time to leave before closing.
      await Future<void>.delayed(const Duration(seconds: 1));
    } on Object {
      if (t != null && t.status.isActive) {
        t.setStatus(
          TransferStatus.failed,
          error: 'Lost connection to ${t.peer.name}',
        );
      }
    } finally {
      _end(s);
    }
  }

  void _onSignal(String from, Object? data) {
    if (data is! Map || data['s'] is! String) return;
    final id = data['s'] as String;
    final sdp = data['sdp'];
    var s = _sessions[id];
    if (s == null) {
      // A new transfer to us starts with their offer.
      if (sdp is! Map || sdp['type'] != 'offer' || !owns(from)) return;
      if (_sessions.length >= 8) return; // someone flooding the room
      s = _open(id, from);
      _receive(s);
    }
    if (s.peer != from) return;
    final session = s;
    // In order: candidates can't be added before the description is set.
    session.steps = session.steps
        .then((_) async {
          final pc = await session.pc;
          if (sdp is Map) {
            await pc.setRemoteDescription(
              RTCSessionDescription(
                sdp['sdp'] as String,
                sdp['type'] as String,
              ),
            );
            if (sdp['type'] == 'offer') {
              final answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);
              _signal(session, {
                'sdp': {'type': answer.type, 'sdp': answer.sdp},
              });
            }
          }
          if (data['ice'] case final Map ice) {
            await pc.addCandidate(
              RTCIceCandidate(
                ice['candidate'] as String?,
                ice['sdpMid'] as String?,
                ice['sdpMLineIndex'] as int?,
              ),
            );
          }
        })
        .catchError((Object _) {});
  }

  _Session _open(String id, String peer) {
    final s = _sessions[id] = _Session(id, peer);
    s.pc = _connect(s);
    return s;
  }

  Future<RTCPeerConnection> _connect(_Session s) async {
    final pc = await createPeerConnection(await _iceServers());
    pc.onIceCandidate = (c) {
      if (c.candidate?.isEmpty ?? true) return;
      _signal(s, {
        'ice': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };
    pc.onDataChannel = s.attach;
    return pc;
  }

  /// STUN, plus the signaling server's TURN relay if it has one. Asking
  /// takes a round trip or two (the server asks Cloudflare for relay
  /// logins), which both ends used to wait for on every transfer before
  /// the other side even heard of it. So it's kept for an hour; the
  /// logins last a day.
  Future<Map<String, dynamic>> _iceServers() {
    final age = DateTime.now().difference(_iceAt);
    if (_ice == null || age > const Duration(hours: 1)) {
      _iceAt = DateTime.now();
      _ice = _fetchIceServers();
    }
    return _ice!;
  }

  Future<Map<String, dynamic>>? _ice;
  DateTime _iceAt = DateTime(0);

  Future<Map<String, dynamic>> _fetchIceServers() async {
    final url = _signaling.url;
    try {
      return await fetchJson(
        url.replace(
          scheme: url.scheme == 'wss' ? 'https' : 'http',
          path: '/ice',
        ),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      _iceAt = DateTime(0); // ask again next time
      // Devices that can see each other still connect.
      return {
        'iceServers': [
          {'urls': 'stun:stun.cloudflare.com:3478'},
        ],
      };
    }
  }

  void _end(_Session s) {
    _sessions.remove(s.id);
    s.close();
  }

  void _signal(_Session s, Map<String, Object?> data) =>
      _signaling.signal(s.peer, {'s': s.id, ...data});

  static Future<String> _code(RTCPeerConnection pc) async => rtcSecurityCode(
    (await pc.getLocalDescription())?.sdp,
    (await pc.getRemoteDescription())?.sdp,
  );
}

/// 64 KB: what every browser's data channels take in one message.
const _chunkSize = 64 * 1024;

/// Exactly bytes [at] to [end] of [chunk], in a buffer of their own: some
/// browsers send a view's whole underlying buffer. Copies only if it has
/// to; a copy of every piece costs, in the web app most of all (there,
/// copying into a new list goes byte by byte between Dart and the
/// browser).
Uint8List _piece(List<int> chunk, int at, int end) {
  if (chunk is! Uint8List) return Uint8List.fromList(chunk.sublist(at, end));
  final whole =
      at == 0 &&
      end == chunk.length &&
      chunk.offsetInBytes == 0 &&
      chunk.buffer.lengthInBytes == end;
  return whole ? chunk : chunk.sublist(at, end);
}

class _Lost implements Exception {
  const _Lost();
}

/// One transfer's connection, and the messages arriving on it in order.
class _Session {
  _Session(this.id, this.peer);

  final String id;
  final String peer;
  late final Future<RTCPeerConnection> pc;
  RTCDataChannel? channel;
  Future<void> steps = Future.value();

  final _opened = Completer<void>();

  /// Only the sender waits for this; the receiver waits for the offer.
  late final Future<void> opened = _opened.future..ignore();
  final _messages = StreamController<RTCDataChannelMessage>();
  late final _next = StreamIterator(_messages.stream);

  void attach(RTCDataChannel c) {
    channel = c
      ..onMessage = (m) {
        if (!_messages.isClosed) _messages.add(m);
      }
      ..onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !_opened.isCompleted) {
          _opened.complete();
        }
        if (state == RTCDataChannelState.RTCDataChannelClosed) close();
      };
  }

  void sendJson(Map<String, Object?> msg) {
    if (channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      channel!.send(RTCDataChannelMessage(jsonEncode(msg)));
    }
  }

  Future<Map<String, Object?>> nextJson() async {
    final msg = await _nextMessage();
    if (msg.isBinary) throw const _Lost();
    final json = jsonDecode(msg.text);
    if (json is! Map<String, Object?> || json['type'] == 'cancel') {
      throw const _Lost();
    }
    return json;
  }

  /// The next piece of a file. A text message here means they cancelled.
  Future<Uint8List> nextBinary() async {
    final msg = await _nextMessage();
    if (!msg.isBinary) throw const _Lost();
    return msg.binary;
  }

  Future<RTCDataChannelMessage> _nextMessage() async {
    if (!await _next.moveNext()) throw const _Lost();
    return _next.current;
  }

  /// Bytes about to be sent since we last looked at the queue.
  int _unchecked = 0;

  /// Waits while too much is queued, so a big file doesn't pile up. In the
  /// apps, asking how much is queued is a trip to the platform side and
  /// back, so it's asked every 256 KB rather than for every piece.
  Future<void> roomToSend(int bytes) async {
    if (_messages.isClosed) throw const _Lost();
    _unchecked += bytes;
    if (_unchecked < 256 * 1024) return;
    _unchecked = 0;
    while (await channel!.getBufferedAmount() > 1024 * 1024) {
      if (_messages.isClosed) throw const _Lost();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_messages.isClosed) throw const _Lost();
  }

  void close() {
    if (_messages.isClosed) return;
    if (!_opened.isCompleted) _opened.completeError(const _Lost());
    _messages.close();
    pc
        .then((pc) async {
          await pc.close();
          await pc.dispose();
        })
        .catchError((Object _) {});
  }
}
