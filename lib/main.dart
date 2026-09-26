import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/incoming_sheet.dart';
import 'services/wisp_service.dart';
import 'theme/app_theme.dart';
import 'models/transfer.dart';
import 'screens/transfer_screen.dart';
import 'utils/notices.dart';
import 'utils/pick_files.dart' show trackTaps;
import 'widgets/toasts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  trackTaps(); // browser only: where to open the file picker
  final service = WispService(prefs: SharedPreferencesAsync())..start();
  runApp(WispApp(service: service));
}

class WispApp extends StatefulWidget {
  const WispApp({super.key, required this.service});

  final WispService service;

  @override
  State<WispApp> createState() => _WispAppState();
}

class _WispAppState extends State<WispApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _toasts = ToastController();
  late final StreamSubscription<IncomingRequest> _incoming;
  late final _notices = Notices(
    service: widget.service,
    toasts: _toasts,
    openTransfer: _openTransfer,
  );

  @override
  void initState() {
    super.initState();
    _incoming = widget.service.incoming.listen(_onIncoming);
    _notices; // starts listening
  }

  @override
  void dispose() {
    _incoming.cancel();
    _notices.dispose();
    _toasts.dispose();
    super.dispose();
  }

  void _openTransfer(Transfer transfer) {
    final context = _navigatorKey.currentContext;
    if (context == null || TransferScreen.showing.contains(transfer)) return;
    openTransfer(context, transfer);
  }

  /// Someone wants to send us files: ask, wherever the user currently is.
  Future<void> _onIncoming(IncomingRequest request) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return request.decline();

    // Once accepted, a toast follows the transfer (see Notices).
    await showIncomingSheet(context, request: request);
  }

  @override
  Widget build(BuildContext context) {
    return WispScope(
      service: widget.service,
      child: MaterialApp(
        title: 'Wisp',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        navigatorKey: _navigatorKey,
        builder: (context, child) =>
            ToastHost(controller: _toasts, child: child!),
        home: const HomeScreen(),
      ),
    );
  }
}
