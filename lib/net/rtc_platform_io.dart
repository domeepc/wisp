import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'server.dart' show WispServer;

/// Apps have no browser name to show.
String? get browserName => null;

Future<Map<String, dynamic>> fetchJson(Uri url) async {
  final client = HttpClient();
  try {
    final res = await (await client.getUrl(url)).close();
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// A file being received, written into [dir] as it arrives.
class ReceivedFile {
  ReceivedFile._(this._file, this._out);

  static Future<ReceivedFile> create(String? dir, String name) async {
    final file = WispServer.createUnique(dir!, name);
    return ReceivedFile._(file, await file.open(mode: FileMode.write));
  }

  final File _file;
  final RandomAccessFile _out;

  Future<void> add(Uint8List data) => _out.writeFrom(data);

  /// Where it was saved.
  Future<String?> close() async {
    await _out.close();
    return _file.path;
  }

  Future<void> abort() async {
    await _out.close();
    await _file.delete().catchError((_) => _file);
  }
}
