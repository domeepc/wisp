import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisp/widgets/voice_dialog.dart';

void main() {
  test('samples become a playable .wav', () {
    final file = wav(Uint8List(100), sampleRate: 44100, channels: 1);
    final h = ByteData.sublistView(file);
    expect(file.length, 144);
    expect(String.fromCharCodes(file.sublist(0, 4)), 'RIFF');
    expect(h.getUint32(4, .little), 136);
    expect(String.fromCharCodes(file.sublist(8, 16)), 'WAVEfmt ');
    expect(h.getUint32(24, .little), 44100);
    expect(h.getUint32(28, .little), 88200);
    expect(String.fromCharCodes(file.sublist(36, 40)), 'data');
    expect(h.getUint32(40, .little), 100);
  });
}
