import 'dart:async';
import 'dart:io' show ProcessException;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../models/shared_file.dart';
import '../theme/tokens.dart';

/// Whether this device can record voice messages at all: browsers only
/// share the microphone with https (or localhost) pages.
bool get canRecordVoice =>
    !kIsWeb || Uri.base.scheme == 'https' || Uri.base.host == 'localhost';

/// Records a voice message. Returns it as a file, or null if the user
/// cancels or the microphone can't be used (the dialog says why).
Future<SharedFile?> recordVoice(BuildContext context) => showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _VoiceDialog(),
);

class _VoiceDialog extends StatefulWidget {
  const _VoiceDialog();

  @override
  State<_VoiceDialog> createState() => _VoiceDialogState();
}

class _VoiceDialogState extends State<_VoiceDialog> {
  final _recorder = AudioRecorder();
  final _clock = Stopwatch();
  Timer? _ticker;
  StreamSubscription<Amplitude>? _levels;

  /// Raw 16-bit samples, made into a .wav at the end: plays everywhere,
  /// and needs no encoder (Linux would need ffmpeg for anything else).
  var _config = const RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 44100,
    numChannels: 1,
  );
  final _pcm = BytesBuilder();
  Future<void>? _pcmDone;
  bool _started = false;
  String? _error;
  bool _saving = false;
  bool _finished = false;

  /// How loud it is now, 0 to 1.
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        return _fail('Wisp isn\'t allowed to use the microphone.');
      }
      // The platform may pick another rate; the .wav must say which.
      await _recorder.setOnConfigChanged((config) => _config = config);
      _pcmDone = (await _recorder.startStream(_config)).forEach(_pcm.add);
      if (!mounted) return;
      _levels = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) => setState(() => _level = _loudness(a.current)));
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => setState(() {}),
      );
      setState(() {
        _started = true;
        _clock.start();
      });
    } on ProcessException {
      // Linux records through parecord.
      _fail('Recording needs pulseaudio-utils installed.');
    } on Exception {
      _fail('Couldn\'t use the microphone.');
    }
  }

  /// Maps dBFS (-160 silent … 0 loudest) onto 0 to 1; speech sits
  /// around -30.
  static double _loudness(double dbfs) => ((dbfs + 50) / 50).clamp(0, 1);

  void _fail(String message) {
    _stopClock();
    if (mounted) setState(() => _error = message);
  }

  void _stopClock() {
    _clock.stop();
    _ticker?.cancel();
    _levels?.cancel();
  }

  Future<void> _done() async {
    setState(() => _saving = true);
    _stopClock();
    try {
      await _recorder.stop();
      await _pcmDone;
      _finished = true;
      if (_pcm.isEmpty) return _fail('Nothing was recorded.');
      final data = wav(
        _pcm.takeBytes(),
        sampleRate: _config.sampleRate,
        channels: _config.numChannels,
      );
      final file = SharedFile(
        _fileName(DateTime.now()),
        data.length,
        source: () => Stream.value(data),
      );
      if (mounted) Navigator.pop(context, file);
    } on Exception {
      _fail('Couldn\'t save the recording.');
    }
  }

  String _fileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Voice message ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}.wav';
  }

  @override
  void dispose() {
    _stopClock();
    final recorder = _recorder;
    final keep = _finished;
    unawaited(() async {
      // Cancelling also deletes the unfinished file.
      if (!keep) await recorder.cancel().catchError((_) {});
      await recorder.dispose();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final recording = _started && _error == null;
    final elapsed = _clock.elapsed;
    final time =
        '${elapsed.inMinutes}:'
        '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Text('Voice message'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: .min,
          children: [
            SizedBox.square(
              dimension: 96,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 64 + 32 * _level,
                  height: 64 + 32 * _level,
                  decoration: BoxDecoration(
                    color: _error != null
                        ? AppColors.surfaceMuted
                        : AppColors.dangerSoft,
                    shape: .circle,
                  ),
                  child: Icon(
                    _error != null ? Icons.mic_off_outlined : Icons.mic,
                    color: _error != null
                        ? AppColors.textSecondary
                        : AppColors.danger,
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error case final error?)
              Text(error, style: text.bodyMedium, textAlign: .center)
            else ...[
              Text(time, style: text.headlineMedium),
              Text(
                recording ? 'Recording…' : 'Starting the microphone…',
                style: text.bodyMedium,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_error != null ? 'Close' : 'Cancel'),
        ),
        if (_error == null)
          FilledButton(
            onPressed: recording && !_saving ? _done : null,
            child: const Text('Done'),
          ),
      ],
    );
  }
}

/// 16-bit PCM [samples] as a .wav file.
Uint8List wav(
  Uint8List samples, {
  required int sampleRate,
  required int channels,
}) {
  final header = ByteData(44);
  void tag(int at, String text) {
    for (final (i, c) in text.codeUnits.indexed) {
      header.setUint8(at + i, c);
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + samples.length, .little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, .little); // size of this "fmt " part
  header.setUint16(20, 1, .little); // plain PCM
  header.setUint16(22, channels, .little);
  header.setUint32(24, sampleRate, .little);
  header.setUint32(28, sampleRate * channels * 2, .little); // bytes a second
  header.setUint16(32, channels * 2, .little); // bytes a sample
  header.setUint16(34, 16, .little); // bits a sample
  tag(36, 'data');
  header.setUint32(40, samples.length, .little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(samples))
      .takeBytes();
}
