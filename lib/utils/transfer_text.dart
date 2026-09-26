import '../models/device.dart';
import '../models/transfer.dart';
import 'format.dart';

/// "12 photos", "3 files", or the file name when there's just one.
String describeFiles(Transfer t) {
  if (t.files.length == 1) return t.files.single.name;
  final noun = t.files.every((f) => f.isImage) ? 'photos' : 'files';
  return '${t.files.length} $noun';
}

/// One-line summary, e.g. "Sending 3 files to Living room PC".
String transferTitle(Transfer t) {
  final what = describeFiles(t);
  final peer = t.peer.name;
  final sending = t.direction == TransferDirection.send;
  return switch (t.status) {
    TransferStatus.waiting when toBrowser(t) => 'Waiting for $peer to download',
    TransferStatus.waiting => 'Waiting for $peer to accept',
    TransferStatus.running =>
      sending ? 'Sending $what to $peer' : 'Receiving $what from $peer',
    TransferStatus.done => sending ? 'Sent $what to $peer' : '$what from $peer',
    TransferStatus.declined => '$peer declined $what',
    TransferStatus.cancelled => 'Cancelled · $what',
    TransferStatus.failed => t.error ?? 'Transfer failed',
  };
}

/// Second line: live progress while running, otherwise when and how big.
String transferSubtitle(Transfer t) {
  if (t.status == TransferStatus.running) {
    final percent = '${(t.progress * 100).round()}%';
    return t.speed > 0 ? '$percent · ${formatBytes(t.speed)}/s' : percent;
  }
  if (t.status == TransferStatus.waiting) {
    return toBrowser(t)
        ? 'They\'re asked in their browser'
        : t.securityCode.isEmpty
        ? 'Connecting…'
        : 'Security code ${t.securityCode}';
  }
  final when = formatWhen(t.finishedAt ?? t.createdAt);
  return '$when · ${formatBytes(t.totalBytes)}';
}

/// Sending to a browser tab: the files wait there until downloaded, and
/// there's no security code to compare.
bool toBrowser(Transfer t) =>
    t.direction == TransferDirection.send &&
    t.peer.platform == DevicePlatform.browser;
