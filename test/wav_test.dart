import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:wisp/models/shared_file.dart';
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

  testWidgets('a microphone that stops by itself is started again', (
    tester,
  ) async {
    final mic = _FakeMic();
    RecordPlatform.instance = mic;
    SharedFile? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await recordVoice(context),
            child: const Text('Record'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pump();
    expect(mic.takes, hasLength(1));

    // What Windows does when the mic drops out: stops, and only says so.
    mic.takes.last.add(Uint8List.fromList([1, 2]));
    mic.states.add(RecordState.stop);
    await tester.pump(const Duration(seconds: 1));
    expect(mic.takes, hasLength(2));

    mic.takes.last.add(Uint8List.fromList([3, 4]));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(result!.data!.sublist(44), [1, 2, 3, 4]);
  });
}

class _FakeMic extends RecordPlatform {
  final takes = <StreamController<Uint8List>>[];
  final states = StreamController<RecordState>.broadcast();

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
    // A real onCancel: without one, cancelling returns a future the test's
    // fake clock never completes.
  ) async => (takes..add(StreamController(onCancel: () async {}))).last.stream;

  @override
  Stream<RecordState> onStateChanged(String recorderId) => states.stream;

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}

  @override
  Future<bool> isRecording(String recorderId) async => true;

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -160, max: -160);

  @override
  Future<String?> stop(String recorderId) async => null;

  @override
  Future<void> cancel(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
