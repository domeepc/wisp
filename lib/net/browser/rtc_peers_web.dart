import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;
import 'package:web/web.dart' as web;

import '../../models/device.dart';
import '../../models/shared_file.dart';
import '../../models/transfer.dart';
import '../server.dart' show Offer;
import '../signaling.dart';

/// Devices on the same network, found through the signaling server, for
/// the web app on its own (GitHub Pages, no Wisp device serving it).
///
/// Installed apps are in the room too, but a website isn't allowed to
/// reach them, so tapping one opens its own web app instead ([handOff]).
/// Other browsers get files straight over a WebRTC data channel, which
/// WebRTC encrypts. The security code comes from both ends' DTLS
/// fingerprints, so if the signaling server meddled, the codes wouldn't
/// match.
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
        'platform': DevicePlatform.browser.name,
        'detail': self().detail,
      },
      onPeers: _onPeers,
      onSignal: _onSignal,
    );
  }

  final Device Function() self;
  final VoidCallback onChanged;
  final Future<Transfer?> Function(Offer offer) onOffer;

  late final Signaling _signaling;
  var _peers = <String, RoomPeer>{};
  final _sessions = <String, _Session>{};

  List<Device> get devices => [for (final p in _peers.values) _device(p)];

  /// Browsers, which we send to ourselves.
  bool owns(String id) => _peers.containsKey(id) && _peers[id]!.lan == null;

  void start() => _signaling.start();

  void stop() {
    _signaling.stop();
    _sessions.values.toList().forEach(_end);
  }

  void renamed() => _signaling.announce();

  /// Hidden: leave the room, so nobody sees us.
  set paused(bool value) => value ? _signaling.stop() : _signaling.start();

  /// An installed app, which we can't reach from here: see [handOff].
  bool isInstalled(String id) => _peers[id]?.lan != null;

  /// Opens an installed device's own web app, which can reach it.
  void handOff(String id) {
    if (_peers[id]?.lan case final lan?) {
      web.window.location.href = lan.replace(path: '/app/').toString();
    }
  }

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

  /// Sends [t]'s files to a browser in the room.
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
      s.attach(
        s.pc.createDataChannel('wisp', web.RTCDataChannelInit(ordered: true)),
      );
      await s.pc.setLocalDescription().toDart;
      _signal(s, {'sdp': _description(s.pc.localDescription!)});
      await s.opened.timeout(const Duration(seconds: 20));
      t.setSecurityCode(_code(s.pc));
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
          final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
          for (var at = 0; at < bytes.length; at += _chunkSize) {
            if (!t.status.isActive) return;
            final end = at + _chunkSize < bytes.length
                ? at + _chunkSize
                : bytes.length;
            await s.roomToSend();
            s.channel!.send(Uint8List.sublistView(bytes, at, end).toJS);
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
      await s.opened.timeout(const Duration(seconds: 20));
      final offer = await s.nextJson();
      final peer = _peers[s.peer];
      if (offer['type'] != 'offer' || peer == null) return;
      final files = [
        for (final f in offer['files'] as List)
          SharedFile((f as Map)['name'] as String, f['size'] as int),
      ];
      t = await onOffer(
        Offer(
          sessionId: s.id,
          from: _device(peer),
          files: files,
          securityCode: _code(s.pc),
        ),
      );
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
        // ponytail: each file is held in memory until it's complete; stream
        // to disk (File System Access API) if big files become a problem.
        final parts = <ByteBuffer>[];
        var got = 0;
        while (got < file.bytes) {
          final part = await s.nextBinary();
          parts.add(part);
          got += part.lengthInBytes;
          transfer.setFileProgress(i, got);
        }
        save(file.name, parts);
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
      // A new transfer to us starts with an offer.
      if (sdp is! Map || sdp['type'] != 'offer' || !owns(from)) return;
      s = _open(id, from);
      s.pc.ondatachannel = ((web.RTCDataChannelEvent e) => s!.attach(
        e.channel,
      )).toJS;
      _receive(s);
    }
    if (s.peer != from) return;
    final session = s;
    // In order: candidates can't be added before the description is set.
    session.steps = session.steps
        .then((_) async {
          if (sdp is Map) {
            await session.pc
                .setRemoteDescription(
                  web.RTCSessionDescriptionInit(
                    type: sdp['type'] as String,
                    sdp: sdp['sdp'] as String,
                  ),
                )
                .toDart;
            if (sdp['type'] == 'offer') {
              await session.pc.setLocalDescription().toDart;
              _signal(session, {
                'sdp': _description(session.pc.localDescription!),
              });
            }
          }
          if (data['ice'] case final Map ice) {
            await session.pc
                .addIceCandidate(
                  web.RTCIceCandidateInit(
                    candidate: ice['candidate'] as String,
                    sdpMid: ice['sdpMid'] as String?,
                    sdpMLineIndex: ice['sdpMLineIndex'] as int?,
                  ),
                )
                .toDart;
          }
        })
        .catchError((Object _) {});
  }

  _Session _open(String id, String peer) {
    final pc = web.RTCPeerConnection(
      web.RTCConfiguration(
        iceServers: [
          web.RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS),
        ].toJS,
      ),
    );
    final s = _sessions[id] = _Session(id, peer, pc);
    pc.onicecandidate = ((web.RTCPeerConnectionIceEvent e) {
      final c = e.candidate;
      if (c == null) return;
      _signal(s, {
        'ice': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    }).toJS;
    return s;
  }

  void _end(_Session s) {
    _sessions.remove(s.id);
    s.close();
  }

  void _signal(_Session s, Map<String, Object?> data) =>
      _signaling.signal(s.peer, {'s': s.id, ...data});

  static Map<String, String> _description(web.RTCSessionDescription d) => {
    'type': d.type,
    'sdp': d.sdp,
  };

  /// The same four characters on both ends, from both DTLS fingerprints.
  static String _code(web.RTCPeerConnection pc) {
    final fingerprints = [
      for (final d in [pc.localDescription, pc.remoteDescription])
        RegExp(r'a=fingerprint:(\S+ \S+)').firstMatch(d?.sdp ?? '')?.group(1) ??
            '',
    ]..sort();
    final hash = sha256.convert(utf8.encode(fingerprints.join('|')));
    return hash.toString().substring(0, 4).toUpperCase();
  }

  /// Saves a received file: through the browser's downloads.
  @visibleForTesting
  static void Function(String name, List<ByteBuffer> parts) save = _download;

  static void _download(String name, List<ByteBuffer> parts) {
    final url = web.URL.createObjectURL(
      web.Blob([for (final p in parts) p.toJS].toJS),
    );
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    web.document.body!.append(link);
    link.click();
    link.remove();
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  }
}

/// 64 KB: what every browser's data channels take in one message.
const _chunkSize = 64 * 1024;

class _Lost implements Exception {
  const _Lost();
}

/// One transfer's connection, and the messages arriving on it in order.
class _Session {
  _Session(this.id, this.peer, this.pc);

  final String id;
  final String peer;
  final web.RTCPeerConnection pc;
  web.RTCDataChannel? channel;
  Future<void> steps = Future.value();

  final _opened = Completer<void>();
  Future<void> get opened => _opened.future;
  final _messages = StreamController<Object>();
  late final _next = StreamIterator(_messages.stream);
  Completer<void>? _drained;

  void attach(web.RTCDataChannel c) {
    channel = c
      ..binaryType = 'arraybuffer'
      ..bufferedAmountLowThreshold = 256 * 1024;
    c.onopen = ((web.Event _) {
      if (!_opened.isCompleted) _opened.complete();
    }).toJS;
    c.onmessage = ((web.MessageEvent e) {
      final data = e.data;
      _messages.add(
        data.isA<JSString>()
            ? (data as JSString).toDart
            : (data as JSArrayBuffer).toDart,
      );
    }).toJS;
    c.onbufferedamountlow = ((web.Event _) => _drain()).toJS;
    c.onclose = ((web.Event _) => close()).toJS;
  }

  void sendJson(Map<String, Object?> msg) {
    if (channel?.readyState == 'open') channel!.send(jsonEncode(msg).toJS);
  }

  Future<Map<String, Object?>> nextJson() async {
    final msg = await _nextMessage();
    if (msg is! String) throw const _Lost();
    final json = jsonDecode(msg) as Map<String, Object?>;
    if (json['type'] == 'cancel') throw const _Lost();
    return json;
  }

  /// The next piece of a file. A text message here means they cancelled.
  Future<ByteBuffer> nextBinary() async {
    final msg = await _nextMessage();
    if (msg is! ByteBuffer) throw const _Lost();
    return msg;
  }

  Future<Object> _nextMessage() async {
    if (!await _next.moveNext()) throw const _Lost();
    return _next.current;
  }

  /// Waits while too much is queued, so a big file doesn't pile up.
  Future<void> roomToSend() async {
    final c = channel!;
    if (c.readyState != 'open') throw const _Lost();
    if (c.bufferedAmount < 1024 * 1024) return;
    _drained = Completer();
    await _drained!.future;
  }

  void _drain() {
    final drained = _drained;
    _drained = null;
    drained?.complete();
  }

  void close() {
    if (!_opened.isCompleted) _opened.completeError(const _Lost());
    _drain();
    if (!_messages.isClosed) _messages.close();
    channel?.close();
    pc.close();
  }
}
