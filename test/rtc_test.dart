// Browser to browser over WebRTC, through a real signaling server. Run with
// the server up (cd server && npx wrangler dev --port 8787):
//   flutter test --platform chrome test/rtc_test.dart \
//     --dart-define=SIGNALING_URL=ws://127.0.0.1:8787
@TestOn('browser')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/models/device.dart';
import 'package:wisp/models/shared_file.dart';
import 'package:wisp/models/transfer.dart';
import 'package:wisp/net/rtc_peers.dart';
import 'package:wisp/net/rtc_platform_web.dart';
import 'package:wisp/net/server.dart' show Offer;
import 'package:wisp/net/signaling.dart';

void main() {
  test('a file goes from one browser to another', () async {
    final saved = <String, List<int>>{};
    ReceivedFile.save = (name, parts) =>
        saved[name] = [for (final p in parts) ...p];

    Offer? offered;
    Transfer? received;
    RtcPeers peer(String id, String name) {
      return RtcPeers(
        self: () => Device(id: id, name: name, platform: .browser),
        onChanged: () {},
        onOffer: (offer) async {
          offered = offer;
          return received = Transfer(
            direction: TransferDirection.receive,
            peer: offer.from,
            files: offer.files,
            securityCode: offer.securityCode,
            sessionId: offer.sessionId,
          );
        },
      )..paused = false;
    }

    final a = peer('rtc-a', 'Laptop');
    final b = peer('rtc-b', 'Phone');
    addTearDown(() {
      a.stop();
      b.stop();
    });
    await _until(() => a.owns('rtc-b') && b.owns('rtc-a'), 'both in the room');

    // Bigger than one chunk, and than the send buffer, to test both.
    final big = Uint8List.fromList(
      List.generate(3 * 1024 * 1024, (i) => i % 251),
    );
    final t = Transfer(
      direction: TransferDirection.send,
      peer: a.devices.single,
      files: [
        SharedFile.text('hello over webrtc', name: 'hi.txt'),
        SharedFile('big.bin', big.length, source: () => Stream.value(big)),
        const SharedFile('empty.txt', 0, source: Stream.empty),
      ],
      securityCode: '',
      sessionId: 'rtc-test-session-0001',
    );
    unawaited(a.send(t));
    await _until(() => !t.status.isActive, 'send');

    expect(t.status, TransferStatus.done, reason: t.error);
    expect(offered!.from.name, 'Laptop');
    expect(t.securityCode, hasLength(4));
    expect(offered!.securityCode, t.securityCode);
    expect(received!.status, TransferStatus.done);
    expect(String.fromCharCodes(saved['hi.txt']!), 'hello over webrtc');
    expect(saved['big.bin'], big);
    expect(saved['empty.txt'], isEmpty);
  }, skip: signalingUrl.isEmpty ? 'needs --dart-define=SIGNALING_URL' : null);
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
