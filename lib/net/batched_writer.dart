import 'dart:io';
import 'dart:typed_data';

/// Writes a file being received in 1 MB batches. The network hands data
/// over in small pieces (around 16 KB over HTTPS, 64 KB over WebRTC), and
/// waiting on the disk for each one slows the transfer and keeps the app
/// busy with bookkeeping instead of drawing.
class BatchedWriter {
  BatchedWriter(this._out);

  static const _batch = 1024 * 1024;

  final RandomAccessFile _out;
  // No copy: every piece from the network is a new list.
  final _pending = BytesBuilder(copy: false);

  Future<void> add(List<int> data) async {
    _pending.add(data);
    if (_pending.length >= _batch) await flush();
  }

  /// Writes what's waiting. Call it before [close] to keep the file.
  Future<void> flush() async {
    if (_pending.isEmpty) return;
    await _out.writeFrom(_pending.takeBytes());
  }

  /// Closes the file; anything not [flush]ed is dropped.
  Future<void> close() {
    _pending.clear();
    return _out.close();
  }
}
