import 'package:flutter_test/flutter_test.dart';

import 'package:wisp/utils/format.dart';

void main() {
  test('formatBytes matches the mockup style', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(480 * 1024), '480 KB');
    expect(formatBytes(3355443), '3.2 MB');
    expect(formatBytes(41 * 1024 * 1024), '41 MB');
    expect(formatBytes(184 * 1024 * 1024), '184 MB');
  });
}
