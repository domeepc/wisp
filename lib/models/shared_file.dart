import 'dart:convert';
import 'dart:io';

/// A file (or piece of text) picked for sending.
class SharedFile {
  const SharedFile(this.name, this.bytes, {this.source});

  /// A file on disk.
  factory SharedFile.fromPath(String path) {
    final file = File(path);
    return SharedFile(
      file.uri.pathSegments.last,
      file.lengthSync(),
      source: file.openRead,
    );
  }

  /// Text sent as a .txt file.
  factory SharedFile.text(String text, {String name = 'Text.txt'}) {
    final data = utf8.encode(text);
    return SharedFile(name, data.length, source: () => Stream.value(data));
  }

  final String name;
  final int bytes;

  /// Opens the contents for reading. Null for placeholder files in tests.
  final Stream<List<int>> Function()? source;

  Stream<List<int>> openRead() =>
      source?.call() ?? (throw StateError('$name has no data source'));

  bool get isImage {
    final lower = name.toLowerCase();
    return const [
      '.jpg',
      '.jpeg',
      '.png',
      '.heic',
      '.gif',
      '.webp',
    ].any(lower.endsWith);
  }
}

int totalBytes(List<SharedFile> files) =>
    files.fold(0, (sum, f) => sum + f.bytes);
