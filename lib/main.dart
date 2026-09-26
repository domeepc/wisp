import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/incoming_sheet.dart';
import 'services/wisp_service.dart';
import 'theme/app_theme.dart';
import 'utils/transfer_text.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final StreamSubscription<IncomingRequest> _incoming;

  @override
  void initState() {
    super.initState();
    _incoming = widget.service.incoming.listen(_onIncoming);
  }

  @override
  void dispose() {
    _incoming.cancel();
    super.dispose();
  }

  /// Someone wants to send us files: ask, wherever the user currently is.
  Future<void> _onIncoming(IncomingRequest request) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return request.decline();

    final accepted = await showIncomingSheet(context, request: request);
    if (!accepted) return;

    final transfer = await request.transfer;
    if (transfer == null || !mounted) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(transferTitle(transfer)),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            final context = _navigatorKey.currentContext;
            if (context != null) openTransfer(context, transfer);
          },
        ),
      ),
    );
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
        scaffoldMessengerKey: _messengerKey,
        home: const HomeScreen(),
      ),
    );
  }
}
