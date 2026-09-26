import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// The signaling server (server/), set when building:
/// `--dart-define=SIGNALING_URL=wss://wisp-signal.<you>.workers.dev`.
/// Empty turns everything that needs the internet off.
const signalingUrl = String.fromEnvironment('SIGNALING_URL');

/// Someone in our room on the signaling server: a device on the same
/// network. [lan] is set for installed apps: their own web app.
typedef RoomPeer = ({
  String id,
  String name,
  String platform,
  String? detail,
  Uri? lan,
});

/// A connection to the signaling server. Says who we are, keeps up with
/// who else is in our room, and passes messages to them. Reconnects by
/// itself until [stop]ped.
class Signaling {
  Signaling({required this.self, this.onPeers, this.onSignal, Uri? url})
    : url = url ?? Uri.parse(signalingUrl);

  final Uri url;

  /// Our entry in the room: id, name, platform, and detail or lan.
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
  final lan = json['lan'];
  return (
    id: id,
    name: name,
    platform: json['platform'] as String? ?? 'browser',
    detail: json['detail'] as String?,
    lan: lan is String ? Uri.tryParse(lan) : null,
  );
}
