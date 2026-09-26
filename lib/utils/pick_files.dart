import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/shared_file.dart';
import '../widgets/text_input_dialog.dart';
import 'web_pick_stub.dart' if (dart.library.js_interop) 'web_pick_web.dart';

export 'web_pick_stub.dart'
    if (dart.library.js_interop) 'web_pick_web.dart'
    show trackTaps;

/// Opens the system file picker. [media] limits it to photos and videos.
/// Returns an empty list if the user cancels.
Future<List<SharedFile>> pickFiles({bool media = false}) async {
  if (kIsWeb) return pickWebFiles(media: media);
  final picked = await FilePicker.pickFiles(
    type: media ? FileType.media : FileType.any,
  );
  return [
    for (final f in picked)
      SharedFile(
        f.name,
        f.lengthSync() ?? await f.length() ?? 0,
        // On Android picked files can be content:// URIs with no path.
        source: switch (f.path) {
          final path? => File(path).openRead,
          null => f.readAsByteStream,
        },
      ),
  ];
}

/// Asks for a folder, e.g. where to save received files. Null if cancelled.
Future<String?> pickFolder({String? title}) =>
    FilePicker.getDirectoryPath(dialogTitle: title);

/// Turns dropped paths into files. Folders are walked, and their files keep
/// the folder in their name ("Photos/2024/a.jpg") so the other device can
/// rebuild it.
Future<List<SharedFile>> filesFromPaths(Iterable<String> paths) async {
  const junk = {'.DS_Store', 'Thumbs.db', 'desktop.ini'};
  final files = <SharedFile>[];
  for (final path in paths) {
    if (await FileSystemEntity.isDirectory(path)) {
      final root = p.dirname(path);
      final entries = Directory(path).list(recursive: true, followLinks: false);
      await for (final entry in entries) {
        if (entry is! File || junk.contains(p.basename(entry.path))) continue;
        files.add(
          SharedFile(
            p.split(p.relative(entry.path, from: root)).join('/'),
            await entry.length(),
            source: entry.openRead,
          ),
        );
      }
    } else if (await FileSystemEntity.isFile(path)) {
      files.add(SharedFile.fromPath(path));
    }
  }
  return files;
}

/// Files dropped in a browser: no paths, so they're read from memory.
/// (Browsers hand over dropped folders as empty entries; they're skipped.)
Future<List<SharedFile>> filesFromDropped(List<DropItem> items) async => [
  for (final item in items)
    if (item is! DropItemDirectory)
      SharedFile(item.name, await item.length(), source: item.openRead),
];

/// The clipboard's text as a .txt file, or null if there's no text.
Future<SharedFile?> clipboardAsFile() async {
  final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  if (text == null || text.isEmpty) return null;
  return SharedFile.text(text, name: 'Clipboard.txt');
}

/// Asks the user to type some text. Returns it as a .txt file, or null if
/// they cancel.
Future<SharedFile?> askForText(BuildContext context) async {
  final text = await showTextInputDialog(
    context,
    title: 'Send text',
    confirmLabel: 'Next',
    hint: 'Type or paste text',
    maxLines: 8,
  );
  if (text == null || text.trim().isEmpty) return null;
  return SharedFile.text(text);
}
