// Installed apps announce themselves on the signaling server. Run with the
// server up (cd server && npx wrangler dev --port 8787):
//   flutter test test/presence_test.dart \
//     --dart-define=SIGNALING_URL=ws://127.0.0.1:8787
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/net/signaling.dart';
import 'package:wisp/services/wisp_service.dart';

void main() {
  test('an installed app shows up with its web app address', () async {
    final tmp = await Directory.systemTemp.createTemp('wisp_presence');
    final app = WispService(
      name: 'Desk PC',
      saveDir: tmp.path,
      port: 0,
      pagePort: 0,
      loadWebFiles: () async => {},
    );
    await app.start(discovery: false);
    app.localAddress = '192.168.1.24';
    await app.setShowOnWeb(true); // announces with the address

    var peers = <RoomPeer>[];
    final watcher = Signaling(
      self: () => {'id': 'watcher', 'name': 'Browser'},
      onPeers: (p) => peers = p,
    )..start();
    addTearDown(() async {
      watcher.stop();
      await app.stop();
      await tmp.delete(recursive: true);
    });

    await _until(() => peers.any((p) => p.id == app.self.id), 'app in room');
    final seen = peers.firstWhere((p) => p.id == app.self.id);
    expect(seen.name, 'Desk PC');
    expect(seen.lan, Uri.parse('http://192.168.1.24:${app.browserPort}'));

    await app.setShowOnWeb(false);
    await _until(() => peers.every((p) => p.id != app.self.id), 'app gone');
  }, skip: signalingUrl.isEmpty ? 'needs --dart-define=SIGNALING_URL' : null);
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
