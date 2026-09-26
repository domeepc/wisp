/// Human-readable file size: 480 KB, 3.2 MB, 184 MB.
/// One decimal below 10, whole numbers above — like the mockups.
String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final number = unit > 0 && size < 10
      ? size.toStringAsFixed(1)
      : size.round().toString();
  return '$number ${units[unit]}';
}

/// "About 4 s", "About 2 min".
String formatTimeLeft(double seconds) {
  if (seconds < 60) return 'About ${seconds.ceil()} s';
  if (seconds < 3600) return 'About ${(seconds / 60).ceil()} min';
  return 'About ${(seconds / 3600).ceil()} h';
}

/// "Just now", "2 min ago", "Today, 15:04", "Yesterday, 21:17", "3/9/2026".
String formatWhen(DateTime time, {DateTime? now}) {
  now ??= DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';

  String hhmm() =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return 'Today, ${hhmm()}';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, ${hhmm()}';
  }
  return '${time.day}/${time.month}/${time.year}';
}
