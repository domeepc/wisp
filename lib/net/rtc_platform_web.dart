import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web/web.dart' as web;

/// "Chrome", "Safari"…
String? get browserName {
  final ua = web.window.navigator.userAgent;
  // Order matters: Edge and Opera also say Chrome; Chrome says Safari.
  if (ua.contains('Edg/')) return 'Edge';
  if (ua.contains('OPR/')) return 'Opera';
  if (ua.contains('SamsungBrowser')) return 'Samsung Internet';
  if (ua.contains('Firefox/') || ua.contains('FxiOS')) return 'Firefox';
  if (ua.contains('Chrome/') || ua.contains('CriOS')) return 'Chrome';
  if (ua.contains('Safari/')) return 'Safari';
  return 'Browser';
}

Future<Map<String, dynamic>> fetchJson(Uri url) async {
  final res = await web.window.fetch(url.toString().toJS).toDart;
  return jsonDecode((await res.text().toDart).toDart) as Map<String, dynamic>;
}

/// A file being received, saved through the browser's downloads at the end.
class ReceivedFile {
  ReceivedFile._(this._name);

  static Future<ReceivedFile> create(String? dir, String name) async =>
      ReceivedFile._(name);

  final String _name;
  // ponytail: held in memory until complete; stream to disk (File System
  // Access API) if big files become a problem.
  final _parts = <Uint8List>[];

  Future<void> add(Uint8List data) async => _parts.add(data);

  /// Browsers don't say where downloads go.
  Future<String?> close() async {
    save(_name, _parts);
    return null;
  }

  Future<void> abort() async => _parts.clear();

  @visibleForTesting
  static void Function(String name, List<Uint8List> parts) save = _download;

  static void _download(String name, List<Uint8List> parts) {
    final url = web.URL.createObjectURL(
      web.Blob([for (final p in parts) p.toJS].toJS),
    );
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    web.document.body!.append(link);
    link.click();
    link.remove();
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  }
}
