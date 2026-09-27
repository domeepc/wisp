import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:wisp/main.dart';
import 'package:wisp/models/device.dart';
import 'package:wisp/models/shared_file.dart';
import 'package:wisp/models/transfer.dart';
import 'package:wisp/net/browser/browser_http.dart';
import 'package:wisp/net/server.dart';
import 'package:wisp/screens/home_screen.dart';
import 'package:wisp/screens/incoming_sheet.dart';
import 'package:wisp/screens/send_screen.dart';
import 'package:wisp/screens/transfer_screen.dart';
import 'package:wisp/services/wisp_service.dart';
import 'package:wisp/theme/app_theme.dart';

const _devices = [
  Device(id: 'mac', name: 'MacBook Pro', platform: .macos, port: 1),
  Device(id: 'pc', name: 'Living room PC', platform: .windows, port: 1),
  Device(id: 'pixel', name: "Ana's Pixel 8", platform: .android, port: 1),
  Device(id: 'ipad', name: 'iPad', platform: .browser, detail: 'Safari'),
];

const _files = [
  SharedFile('IMG_2041.jpg', 3355443),
  SharedFile('IMG_2042.jpg', 3040870),
  SharedFile('notes.pdf', 480 * 1024),
];

/// A service that never touches the network, pre-filled with devices.
WispService _service({bool withDevices = true}) {
  final service = WispService(name: 'Test phone');
  if (withDevices) _devices.forEach(service.addDevice);
  return service;
}

/// Runs the app at a given logical window size. Layout overflows make the
/// test fail, so these double as "does every screen fit" checks.
Future<void> _pumpApp(
  WidgetTester tester,
  Size size,
  WispService service,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(WispApp(service: service));
}

/// Pumps a single screen with the theme and service around it.
Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen,
  WispService service,
) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    WispScope(
      service: service,
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
}

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);

void main() {
  testWidgets('phone: lists nearby devices', (tester) async {
    await _pumpApp(tester, _phone, _service());
    expect(find.text('NEARBY · 4'), findsOneWidget);
    expect(find.text('MacBook Pro'), findsOneWidget);
    expect(find.text('Browser · Safari'), findsOneWidget);
  });

  testWidgets('phone: every send type fits on a small phone', (tester) async {
    await _pumpApp(tester, const Size(360, 640), _service());
    for (final label in ['Files', 'Photos', 'Text', 'Paste', 'Voice']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('phone: a clipboard the browser won\'t share opens the text '
      'box instead', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? throw PlatformException(code: 'paste_fail')
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpApp(tester, _phone, _service());
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(find.text('Send text'), findsOneWidget);
    expect(find.text('Couldn\'t open the file picker'), findsNothing);
  });

  testWidgets('phone: shows a placeholder with nobody around', (tester) async {
    await _pumpApp(tester, _phone, _service(withDevices: false));
    expect(find.text('Looking for devices…'), findsOneWidget);
  });

  testWidgets('phone: latest transfer shows in the banner', (tester) async {
    final service = _service();
    final transfer = Transfer(
      direction: TransferDirection.receive,
      peer: _devices.first,
      files: _files.take(2).toList(),
      securityCode: 'AB12',
      saveDir: '/tmp',
    )..setStatus(TransferStatus.running);
    service.addTransfer(transfer);
    await _pumpApp(tester, _phone, service);

    expect(find.text('Receiving 2 photos from MacBook Pro'), findsOneWidget);
    transfer.setStatus(TransferStatus.done);
    await tester.pump();
    expect(find.text('2 photos from MacBook Pro'), findsOneWidget);
  });

  testWidgets('send screen shows files and devices', (tester) async {
    await _pumpScreen(tester, const SendScreen(files: _files), _service());
    expect(find.text('3 items ready'), findsOneWidget);
    expect(find.text('6.6 MB total'), findsOneWidget);
    expect(find.text('Living room PC'), findsOneWidget);
  });

  testWidgets('send screen: picked files can be removed', (tester) async {
    await _pumpScreen(tester, const SendScreen(files: _files), _service());
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump();
    expect(find.text('2 items ready'), findsOneWidget);
    expect(find.text('IMG_2041.jpg'), findsNothing);

    await tester.tap(find.byTooltip('Remove').first);
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump();
    expect(find.text('Nothing selected'), findsOneWidget);
    // Nothing to send, so the devices do nothing.
    await tester.tap(find.text('Living room PC'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing selected'), findsOneWidget);
  });

  testWidgets('transfer screen follows a transfer', (tester) async {
    final transfer = Transfer(
      direction: TransferDirection.send,
      peer: _devices.first,
      files: _files,
      securityCode: 'AB12',
    );
    await _pumpScreen(tester, TransferScreen(transfer: transfer), _service());
    expect(find.widgetWithText(AppBar, 'Waiting'), findsOneWidget);
    expect(find.text('AB12'), findsOneWidget);

    transfer
      ..setStatus(TransferStatus.running)
      ..addProgress(0, _files[0].bytes);
    await tester.pump();
    expect(find.widgetWithText(AppBar, 'Sending'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget); // first file's status

    transfer.setStatus(TransferStatus.done);
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
  });

  testWidgets('transfer screen explains a decline', (tester) async {
    final transfer = Transfer(
      direction: TransferDirection.send,
      peer: _devices.first,
      files: _files,
      securityCode: 'AB12',
    )..setStatus(TransferStatus.declined);
    await _pumpScreen(tester, TransferScreen(transfer: transfer), _service());
    expect(find.text('MacBook Pro declined the files.'), findsOneWidget);
  });

  group('incoming sheet', () {
    IncomingRequest request() => IncomingRequest(
      Offer(
        sessionId: 'session',
        from: _devices.first,
        files: const [
          SharedFile('report.pdf', 2516582),
          SharedFile('demo-video.mp4', 184 * 1024 * 1024),
        ],
        securityCode: '4F9A',
      ),
    );

    Future<void> open(WidgetTester tester, IncomingRequest r) async {
      await _pumpApp(tester, _phone, _service());
      showIncomingSheet(tester.element(find.byType(HomeScreen)), request: r);
      await tester.pumpAndSettle();
    }

    testWidgets('accept with "always accept"', (tester) async {
      final r = request();
      await open(tester, r);
      expect(find.text('wants to send you 2 files · 186 MB'), findsOneWidget);
      expect(find.text('4F9A'), findsOneWidget);

      await tester.tap(find.text('Always accept from this device'));
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(r.alwaysAccept, isTrue);
      expect(find.text('4F9A'), findsNothing);
    });

    testWidgets('closes when the sender cancels', (tester) async {
      final r = request();
      await open(tester, r);
      r.cancelled.value = true;
      await tester.pumpAndSettle();
      expect(find.text('4F9A'), findsNothing);
    });
  });

  testWidgets('desktop: devices and transfer history', (tester) async {
    final service = _service()
      ..addTransfer(
        Transfer(
          direction: TransferDirection.send,
          peer: _devices[1],
          files: _files,
          securityCode: 'AB12',
        )..setStatus(TransferStatus.running),
      )
      ..addTransfer(
        Transfer(
          direction: TransferDirection.send,
          peer: _devices[0],
          files: const [SharedFile('budget.xlsx', 120 * 1024)],
          securityCode: 'CD34',
        )..setStatus(TransferStatus.done),
      );
    await _pumpApp(tester, _desktop, service);

    expect(find.text('Nearby devices'), findsOneWidget);
    expect(find.text('Select files first'), findsNWidgets(4));
    expect(find.text('Sending 3 photos to Living room PC'), findsNothing);
    expect(find.text('Sending 3 files to Living room PC'), findsOneWidget);
    expect(find.text('Sent budget.xlsx to MacBook Pro'), findsOneWidget);
    expect(find.text('Send again'), findsOneWidget);
  });

  testWidgets('narrow window falls back to the phone layout', (tester) async {
    await _pumpApp(tester, const Size(800, 900), _service());
    expect(find.text('Nearby devices'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('settings: rename this device', (tester) async {
    final service = _service();
    await _pumpApp(tester, _phone, service);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Save files to'), findsOneWidget);

    await tester.tap(find.text('Test phone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Kitchen tablet');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(service.self.name, 'Kitchen tablet');
    expect(find.text('Kitchen tablet'), findsOneWidget);
  });

  testWidgets('connect dialog explains a bad code', (tester) async {
    await _pumpApp(tester, _desktop, _service());

    await tester.tap(find.text('Connect with code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not a code!');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('doesn\'t look right'), findsOneWidget);
  });

  testWidgets('connect dialog shows a code and a QR, never the IP', (
    tester,
  ) async {
    final service = _service()
      ..self = _service().self.copyWith(port: 53318)
      ..localAddress = '192.168.1.24'
      ..browserPort = 53319;
    await _pumpApp(tester, _desktop, service);

    await tester.tap(find.text('Connect with code'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(service.connectCode!), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('192.168'), findsNothing);
  });

  testWidgets('sending to a browser waits for the download', (tester) async {
    final transfer = Transfer(
      direction: TransferDirection.send,
      peer: _devices.last, // the iPad browser
      files: _files,
      securityCode: 'AB12',
    );
    await _pumpScreen(tester, TransferScreen(transfer: transfer), _service());

    expect(find.text('Waiting for download'), findsOneWidget);
    expect(find.textContaining('asked in their browser'), findsOneWidget);
    expect(find.text('AB12'), findsNothing);
  });

  testWidgets('in a browser, the app asks to connect instead', (tester) async {
    final service = WispService(name: 'Web', browserHttp: _NoNetwork());
    await _pumpApp(tester, _phone, service);

    expect(find.text('Connect to a Wisp device'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Other device\'s code'), findsOneWidget);
    expect(find.text('THIS DEVICE\'S CODE'), findsNothing);
  });

  group('toasts', () {
    // A toast's animation starts on the frame it first appears.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('incoming files: live progress, then done', (tester) async {
      final service = _service();
      await _pumpApp(tester, _phone, service);
      final t = Transfer(
        direction: TransferDirection.receive,
        peer: _devices.first,
        files: _files,
        securityCode: 'AB12',
        saveDir: '/tmp',
      )..setStatus(TransferStatus.running);
      service.addTransfer(t);
      await settle(tester);

      expect(find.text('Receiving 3 files'), findsOneWidget);
      // Stays while it's running.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Receiving 3 files'), findsOneWidget);

      for (final (i, f) in _files.indexed) {
        t.setFileProgress(i, f.bytes);
      }
      t.setStatus(TransferStatus.done);
      await settle(tester);
      expect(find.text('Received 3 files'), findsOneWidget);
      expect(find.text('Show in folder'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'View'), findsOneWidget);

      // Then goes away by itself.
      await tester.pump(const Duration(seconds: 8));
      await settle(tester);
      expect(find.text('Received 3 files'), findsNothing);
    });

    testWidgets('someone opening Wisp in a browser', (tester) async {
      final service = _service(withDevices: false);
      await _pumpApp(tester, _phone, service);

      service.addDevice(_devices.last);
      await settle(tester);

      expect(find.text('iPad joined from a browser'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await settle(tester);
      expect(find.text('iPad joined from a browser'), findsNothing);
    });

    testWidgets('devices on the Wi-Fi don\'t get one', (tester) async {
      final service = _service(withDevices: false);
      await _pumpApp(tester, _phone, service);

      service.addDevice(_devices.first);
      await settle(tester);

      expect(find.textContaining('MacBook Pro'), findsOneWidget); // the list
      expect(find.byTooltip('Dismiss'), findsNothing);
    });

    testWidgets('a send that finished off screen', (tester) async {
      final service = _service();
      await _pumpApp(tester, _desktop, service);
      final t = Transfer(
        direction: TransferDirection.send,
        peer: _devices.first,
        files: [_files.last],
        securityCode: 'AB12',
      )..setStatus(TransferStatus.running);
      service.addTransfer(t);
      await settle(tester);
      expect(find.byTooltip('Dismiss'), findsNothing); // its screen shows it

      t.setStatus(TransferStatus.declined);
      await settle(tester);
      expect(find.text('MacBook Pro declined notes.pdf'), findsWidgets);
      expect(find.byTooltip('Dismiss'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

/// A browser HTTP layer for widget tests that never gets anywhere.
class _NoNetwork implements BrowserHttp {
  @override
  String get browserName => 'Chrome';

  @override
  Future<({int status, String body})> send(
    String method,
    Uri url, {
    String? json,
    void Function(void Function() abort)? onStart,
  }) async => throw const BrowserHttpException('offline');

  @override
  Future<int> upload(
    Uri url,
    Uint8List bytes, {
    required void Function(int sent) onProgress,
    void Function(void Function() abort)? onStart,
  }) async => throw const BrowserHttpException('offline');

  @override
  void download(Uri url) {}
}
