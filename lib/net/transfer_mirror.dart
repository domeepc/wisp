import '../models/transfer.dart';

/// What changed in a [Transfer] running on a background isolate, sent over
/// to its twin on the main isolate, which the screens watch.
///
/// Transfers move their bytes on a background isolate so the work (TLS,
/// HTTP, disk) doesn't compete with drawing the screen. The networking code
/// there drives an ordinary [Transfer]; [mirrorTransfer] passes its changes
/// on as they're announced (at most every 100 ms, plus status changes).
class TransferUpdate {
  const TransferUpdate({
    required this.status,
    this.error,
    this.progress = const [],
    this.saved = const [],
  });

  final TransferStatus status;
  final String? error;

  /// `(file index, bytes done)` for the files that moved since last time.
  final List<(int, int)> progress;

  /// Files saved since last time.
  final List<String> saved;

  void applyTo(Transfer t) {
    for (final (i, bytes) in progress) {
      t.setFileProgress(i, bytes);
    }
    t.savedPaths.addAll(saved);
    if (status != t.status) t.setStatus(status, error: error);
  }
}

/// Sends [t]'s changes to [send] from now on. Stops by itself once [t] is
/// over.
void mirrorTransfer(Transfer t, void Function(TransferUpdate) send) {
  final sent = List.filled(t.files.length, 0);
  var savedCount = 0;
  var lastStatus = t.status;

  void onChange() {
    final progress = <(int, int)>[
      for (final (i, bytes) in t.fileBytesDone.indexed)
        if (bytes != sent[i]) (i, sent[i] = bytes),
    ];
    final saved = t.savedPaths.sublist(savedCount);
    savedCount = t.savedPaths.length;
    if (progress.isEmpty && saved.isEmpty && t.status == lastStatus) return;
    lastStatus = t.status;
    send(
      TransferUpdate(
        status: t.status,
        error: t.error,
        progress: progress,
        saved: saved,
      ),
    );
    if (!t.status.isActive) t.removeListener(onChange);
  }

  t.addListener(onChange);
}
