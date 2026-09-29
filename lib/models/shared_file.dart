import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A file (or piece of text) picked for sending.
class SharedFile {
  const SharedFile(this.name, this.bytes, {this.path, this.data, this.source});

  /// A file on disk.
  factory SharedFile.fromPath(String path) => SharedFile(
    File(path).uri.pathSegments.last,
    File(path).lengthSync(),
    path: path,
  );

  /// Contents already in memory, like a voice recording.
  factory SharedFile.data(String name, Uint8List data) =>
      SharedFile(name, data.length, data: data);

  /// Text sent as a .txt file.
  factory SharedFile.text(String text, {String name = 'Text.txt'}) =>
      SharedFile.data(name, utf8.encode(text));

  final String name;
  final int bytes;

  /// Where it is on disk, if it is.
  final String? path;

  /// The contents, if they're in memory.
  final Uint8List? data;

  /// Opens the contents for reading, when they're neither on disk nor in
  /// memory (a browser's file, an Android content:// URI). Null for
  /// placeholder files in tests.
  final Stream<List<int>> Function()? source;

  /// On disk or in memory: a background isolate can read it too. (Other
  /// sources may need the main isolate's plugins.)
  bool get portable => source == null && (path != null || data != null);

  Stream<List<int>> openRead() {
    if (path case final path?) return File(path).openRead();
    if (data case final data?) return Stream.value(data);
    return source?.call() ?? (throw StateError('$name has no data source'));
  }

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
