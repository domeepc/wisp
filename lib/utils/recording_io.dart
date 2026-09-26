import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/shared_file.dart';

/// Apps can always ask for the microphone.
bool get canRecordHere => true;

/// Where to write a new recording: the temporary folder, which the system
/// cleans up.
Future<String> recordingPath(String extension) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  return p.join(dir.path, 'wisp-voice-$stamp.$extension');
}

/// The finished recording at [path], sent as [name].
Future<SharedFile> recordedFile(String path, String name) async {
  final file = File(path);
  return SharedFile(name, await file.length(), source: file.openRead);
}
