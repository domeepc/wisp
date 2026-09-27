import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The signaling server (server/), set when building:
/// `--dart-define=SIGNALING_URL=wss://wisp-signal.<you>.workers.dev`.
/// Empty turns everything that needs the internet off.
const signalingUrl = String.fromEnvironment('SIGNALING_URL');

/// The web app (GitHub Pages), for devices without the app: it finds this
/// one through the signaling server.
const webAppUrl = 'https://domeepc.github.io/wisp/';

/// Someone in our room on the signaling server: a device on the same
/// network.
typedef RoomPeer = ({String id, String name, String platform, String? detail});

/// A connection to the signaling server. Says who we are, keeps up with
/// who else is in our room, and passes messages to them. Reconnects by
/// itself until [stop]ped.
class Signaling {
  Signaling({required this.self, this.onPeers, this.onSignal, Uri? url})
    : url = url ?? Uri.parse(signalingUrl);

  final Uri url;

  /// Our entry in the room: id, name, platform and detail.
  final Map<String, Object?> Function() self;
  final void Function(List<RoomPeer> peers)? onPeers;
  final void Function(String from, Object? data)? onSignal;

  WebSocketChannel? _channel;
  Timer? _ping;
  Timer? _retry;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _retry?.cancel();
    _ping?.cancel();
    _channel?.sink.close();
    _channel = null;
    onPeers?.call(const []);
  }

  /// Tells the room about us again, e.g. after a rename.
  void announce() => _send({'type': 'hello', 'peer': self()});

  void signal(String to, Object? data) =>
      _send({'type': 'signal', 'to': to, 'data': data});

  Future<void> _connect() async {
    final channel = _channel = WebSocketChannel.connect(url);
    try {
      await channel.ready;
    } catch (_) {
      _lost(channel);
      return;
    }
    if (_channel != channel) return channel.sink.close(); // stopped meanwhile
    channel.stream.listen(
      _onMessage,
      onDone: () => _lost(channel),
      onError: (_) {},
    );
    announce();
    // Idle connections get closed along the way otherwise.
    _ping = Timer.periodic(
      const Duration(seconds: 30),
      (_) => channel.sink.add('ping'),
    );
  }

  void _lost(WebSocketChannel channel) {
    if (_channel != channel) return;
    _ping?.cancel();
    _channel = null;
    onPeers?.call(const []);
    if (_running) _retry = Timer(const Duration(seconds: 5), _connect);
  }

  void _onMessage(Object? raw) {
    if (raw is! String || raw == 'pong') return;
    final Object? msg;
    try {
      msg = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (msg is! Map) return;
    switch (msg['type']) {
      case 'peers':
        onPeers?.call([
          for (final p in msg['peers'] as List? ?? const []) ?_peer(p),
        ]);
      case 'signal':
        if (msg['from'] case final String from) {
          onSignal?.call(from, msg['data']);
        }
    }
  }

  void _send(Map<String, Object?> msg) => _channel?.sink.add(jsonEncode(msg));
}

RoomPeer? _peer(Object? json) {
  if (json is! Map) return null;
  final (id, name) = (json['id'], json['name']);
  if (id is! String || name is! String) return null;
  return (
    id: id,
    name: name,
    platform: json['platform'] as String? ?? 'browser',
    detail: json['detail'] as String?,
  );
}

/// A WebRTC transfer's security code: the same four characters on both
/// ends, from both DTLS fingerprints. If the signaling server swapped
/// them, the codes wouldn't match.
String rtcSecurityCode(String? localSdp, String? remoteSdp) {
  final fingerprints = [
    for (final sdp in [localSdp, remoteSdp])
      RegExp(r'a=fingerprint:(\S+ \S+)').firstMatch(sdp ?? '')?.group(1) ?? '',
  ]..sort();
  final hash = sha256.convert(utf8.encode(fingerprints.join('|')));
  return hash.toString().substring(0, 4).toUpperCase();
}
