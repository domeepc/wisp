import 'package:flutter_test/flutter_test.dart';

import 'package:wisp/models/device.dart';
import 'package:wisp/models/shared_file.dart';
import 'package:wisp/models/transfer.dart';

void main() {
  Transfer transfer() => Transfer(
    direction: TransferDirection.receive,
    peer: const Device(id: 'p', name: 'Phone', platform: .android),
    files: const [SharedFile('a.bin', 1000), SharedFile('b.bin', 1000)],
    securityCode: 'AB12',
  )..setStatus(TransferStatus.running);

  test('progress is shown at most every 100 ms, but always shown', () async {
    final t = transfer();
    var notified = 0;
    int? shown;
    t.addListener(() {
      notified++;
      shown = t.bytesDone;
    });

    for (var i = 0; i < 10; i++) {
      t.addProgress(0, 100);
    }
    // The first piece right away, the rest held back...
    expect(notified, lessThanOrEqualTo(1));

    // ...and shown once the 100 ms are up, even with nothing more coming.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(shown, 1000);
    expect(t.fileBytesDone, [1000, 0]);
  });

  test('finishing shows the final state straight away', () {
    final t = transfer();
    t
      ..addProgress(0, 1000)
      ..addProgress(1, 1000);
    var notified = 0;
    t.addListener(() => notified++);
    t.setStatus(TransferStatus.done);
    expect(notified, 1);
    expect(t.bytesDone, 2000);
    expect(t.progress, 1);
  });
}
