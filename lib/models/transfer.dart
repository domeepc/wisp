import 'package:flutter/foundation.dart';

import 'device.dart';
import 'shared_file.dart';

enum TransferDirection { send, receive }

enum TransferStatus {
  /// Sender is waiting for the receiver to accept.
  waiting,
  running,
  done,
  declined,
  cancelled,
  failed;

  bool get isActive => this == waiting || this == running;
}

/// One batch of files going to or coming from [peer]. Screens listen to it
/// for progress; the networking code updates it.
class Transfer extends ChangeNotifier {
  Transfer({
    required this.direction,
    required this.peer,
    required this.files,
    required this.securityCode,
    this.sessionId = '',
    this.saveDir,
  }) : fileBytesDone = List.filled(files.length, 0),
       createdAt = DateTime.now();

  final TransferDirection direction;
  final Device peer;
  final List<SharedFile> files;

  /// Short code both devices show so people can check they match.
  final String securityCode;

  /// Identifies the transfer between the two devices.
  final String sessionId;

  /// Where received files are written.
  final String? saveDir;

  final DateTime createdAt;
  final List<int> fileBytesDone;

  /// Receiving only: where each finished file was saved.
  final List<String> savedPaths = [];

  TransferStatus _status = TransferStatus.waiting;
  TransferStatus get status => _status;

  DateTime? finishedAt;
  String? error;

  /// Bytes per second, smoothed.
  double speed = 0;

  /// Set by the networking code; called by [cancel].
  VoidCallback? onCancel;

  late final int totalBytes = files.fold(0, (sum, f) => sum + f.bytes);

  int get bytesDone => fileBytesDone.fold(0, (sum, b) => sum + b);

  double get progress => totalBytes == 0
      ? (status == TransferStatus.done ? 1 : 0)
      : bytesDone / totalBytes;

  void cancel() => onCancel?.call();

  void setStatus(TransferStatus status, {String? error}) {
    if (!_status.isActive) return; // finished transfers stay finished
    _status = status;
    this.error = error;
    if (!status.isActive) {
      finishedAt = DateTime.now();
      speed = 0;
    }
    notifyListeners();
  }

  // Progress arrives in small chunks; rebuilding the UI for every chunk is
  // wasteful, so notify at most every 100 ms and sample speed every 500 ms.
  DateTime _lastNotify = DateTime(0);
  DateTime _sampleAt = DateTime.now();
  int _sampleBytes = 0;

  /// Raises file [fileIndex]'s progress to [bytes], if that's more than
  /// before — for downloads that may be repeated or restarted.
  void setFileProgress(int fileIndex, int bytes) {
    final more = bytes - fileBytesDone[fileIndex];
    if (more > 0) addProgress(fileIndex, more);
  }

  void addProgress(int fileIndex, int bytes) {
    fileBytesDone[fileIndex] += bytes;
    final now = DateTime.now();

    final elapsed = now.difference(_sampleAt).inMilliseconds;
    if (elapsed >= 500) {
      final done = bytesDone;
      final instant = (done - _sampleBytes) * 1000 / elapsed;
      speed = speed == 0 ? instant : speed * 0.6 + instant * 0.4;
      _sampleAt = now;
      _sampleBytes = done;
    }

    final fileFinished = fileBytesDone[fileIndex] >= files[fileIndex].bytes;
    if (fileFinished || now.difference(_lastNotify).inMilliseconds >= 100) {
      _lastNotify = now;
      notifyListeners();
    }
  }
}
