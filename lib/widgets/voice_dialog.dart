import 'dart:async';
import 'dart:io' show ProcessException;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../models/shared_file.dart';
import '../theme/tokens.dart';
import '../utils/recording_io.dart'
    if (dart.library.js_interop) '../utils/recording_web.dart';

/// Whether this device can record voice messages at all.
bool get canRecordVoice => canRecordHere;

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

  /// The file's extension, once recording has started.
  String? _extension;
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
      final (encoder, extension) = await _format();
      await _recorder.start(
        RecordConfig(encoder: encoder, numChannels: 1),
        path: await recordingPath(extension),
      );
      if (!mounted) return;
      _levels = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) => setState(() => _level = _loudness(a.current)));
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => setState(() {}),
      );
      setState(() {
        _extension = extension;
        _clock.start();
      });
    } on ProcessException {
      // Linux records through parecord and ffmpeg.
      _fail('Recording needs ffmpeg and pulseaudio-utils installed.');
    } on Exception {
      _fail('Couldn\'t use the microphone.');
    }
  }

  /// AAC (.m4a) plays everywhere; browsers without it record Opus.
  Future<(AudioEncoder, String)> _format() async {
    final formats = [
      (AudioEncoder.aacLc, 'm4a'),
      (AudioEncoder.opus, kIsWeb ? 'webm' : 'ogg'),
      (AudioEncoder.wav, 'wav'),
    ];
    for (final format in formats) {
      if (await _recorder.isEncoderSupported(format.$1)) return format;
    }
    return formats.last;
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
      final path = await _recorder.stop();
      _finished = true;
      if (path == null) return _fail('Nothing was recorded.');
      final file = await recordedFile(path, _fileName(DateTime.now()));
      if (mounted) Navigator.pop(context, file);
    } on Exception {
      _fail('Couldn\'t save the recording.');
    }
  }

  String _fileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Voice message ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}.$_extension';
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
    final recording = _extension != null && _error == null;
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
