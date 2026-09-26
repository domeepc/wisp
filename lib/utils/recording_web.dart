import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/shared_file.dart';

/// Browsers only share the microphone with https pages, so not with the
/// web app an installed app serves over plain http.
bool get canRecordHere => web.window.isSecureContext;

/// Browsers keep the recording in memory; the path is ignored.
Future<String> recordingPath(String extension) async => '';

/// The finished recording, handed over as a blob: URL.
Future<SharedFile> recordedFile(String url, String name) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final data = (await response.arrayBuffer().toDart).toDart.asUint8List();
  web.URL.revokeObjectURL(url);
  return SharedFile(name, data.length, source: () => Stream.value(data));
}
