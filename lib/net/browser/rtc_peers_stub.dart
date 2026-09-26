import 'package:flutter/foundation.dart';

import '../../models/device.dart';
import '../../models/transfer.dart';
import '../server.dart' show Offer;

/// WebRTC only exists in browsers; see rtc_peers_web.dart.
class RtcPeers {
  RtcPeers({
    required Device Function() self,
    required VoidCallback onChanged,
    required Future<Transfer?> Function(Offer offer) onOffer,
  }) {
    throw UnsupportedError('WebRTC needs a browser');
  }

  List<Device> get devices => const [];
  bool owns(String id) => false;
  bool isInstalled(String id) => false;
  void handOff(String id) {}
  void start() {}
  void stop() {}
  void renamed() {}
  set paused(bool value) {}
  Future<void> send(Transfer transfer) async {}
}
