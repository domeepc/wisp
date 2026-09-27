import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/shared_file.dart';

/// The browser's own file picker, opened where the user last tapped: iOS
/// shows its Photo Library / Choose File menu next to the input.
///
/// file_picker gives up if the page regains focus before the files
/// arrive (phones are slow to hand them over), writes the media filter
/// wrong, and reads every file into memory up front. This reads files
/// only while sending them.
Future<List<SharedFile>> pickWebFiles({required bool media}) {
  final done = Completer<List<SharedFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = media ? 'image/*,video/*' : ''
    // Safari anchors its menu to the input, but treats a fully
    // transparent or tiny one as not there and opens the menu from the
    // whole page instead (a dark blob, then a menu at the top). So it's a
    // finger-sized box around the tap, just short of transparent.
    ..style.cssText =
        'position:fixed;left:${_tapX - _anchor / 2}px;'
        'top:${_tapY - _anchor / 2}px;width:${_anchor}px;height:${_anchor}px;'
        'opacity:0.02;color:transparent;background:transparent;border:0;'
        'margin:0;padding:0;font-size:0;z-index:2147483647;'
        'pointer-events:none';
  void finish(List<SharedFile> files) {
    input.remove();
    if (!done.isCompleted) done.complete(files);
  }

  input
    ..onchange = ((web.Event _) {
      final list = input.files;
      finish([
        for (var i = 0; i < (list?.length ?? 0); i++)
          if (list!.item(i) case final f?)
            SharedFile(f.name, f.size, source: () => _read(f)),
      ]);
    }).toJS
    // ponytail: browsers without the cancel event (Safari before 16.4)
    // never finish a cancelled pick; harmless, the next tap starts anew.
    ..oncancel = ((web.Event _) => finish(const [])).toJS;
  web.document.body!.append(input);
  input.click();
  return done.future;
}

double _tapX = 0, _tapY = 0;

/// Size of the box the menu opens from, in CSS pixels.
const _anchor = 44.0;

/// Remembers where each tap lands, for [pickWebFiles]. Call at startup.
void trackTaps() => web.window.addEventListener(
  'pointerdown',
  ((web.PointerEvent e) {
    _tapX = e.clientX.toDouble();
    _tapY = e.clientY.toDouble();
  }).toJS,
  true.toJS,
);

/// A picked file, 1 MB at a time.
Stream<List<int>> _read(web.File file) async* {
  const chunk = 1024 * 1024;
  for (var at = 0; at < file.size; at += chunk) {
    final part = await file.slice(at, at + chunk).arrayBuffer().toDart;
    yield Uint8List.view(part.toDart);
  }
}
