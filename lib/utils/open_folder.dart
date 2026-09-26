import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether [openFolder] works here (desktop only).
bool get canOpenFolders =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// Opens [path] in Finder / Explorer / the Linux file manager.
Future<void> openFolder(String path) async {
  if (!canOpenFolders) return;
  final command = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'explorer'
      : 'xdg-open';
  await Process.run(command, [path]);
}
