import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device.dart';
import 'protocol.dart';

/// Finds other Wisp devices on the local network with UDP multicast.
class Discovery {
  Discovery({required this.self, required this.onDevice});

  /// Current info about this device, or null while hidden (then nothing
  /// is announced, but others are still heard).
  final Device? Function() self;

  /// Called for every announcement from another device.
  final void Function(Device device) onDevice;

  RawDatagramSocket? _socket;
  Timer? _timer;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      // Lets two copies run on one computer while developing. Not
      // supported on Windows and Android.
      reusePort: Platform.isMacOS || Platform.isIOS || Platform.isLinux,
    );
    _socket = socket;

    // Join the group on every network interface, so it works no matter
    // which one the Wi-Fi is on.
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      try {
        socket.joinMulticast(multicastGroup, interface);
      } on SocketException {
        // Some virtual interfaces don't support multicast; skip them.
      }
    }

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram != null) _handle(datagram);
    });

    announce();
    _timer = Timer.periodic(announceEvery, (_) => announce());
  }

  void announce() {
    final me = self();
    final socket = _socket;
    if (me == null || socket == null) return;
    final packet = utf8.encode(
      jsonEncode({...me.toJson(), 'protocol': protocolVersion}),
    );
    try {
      socket.send(packet, multicastGroup, discoveryPort);
    } on SocketException {
      // Network went away (Wi-Fi off, etc.); try again next tick.
    }
  }

  void _handle(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map || json['protocol'] != protocolVersion) return;
      final device = Device.fromJson(json, host: datagram.address.address);
      if (device == null || device.id == self()?.id) return;
      onDevice(device);
    } on FormatException {
      // Not ours, or garbage; ignore.
    }
  }

  void stop() {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
  }
}
