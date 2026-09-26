import 'package:flutter/material.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../models/device.dart';
import '../services/wisp_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// "Connect with code": shows this device's code and lets the user type
/// the other device's, for when it doesn't show up by itself. Shows a
/// snackbar once connected.
Future<void> connectWithCode(BuildContext context) async {
  final device = await showDialog<Device>(
    context: context,
    builder: (_) => const _ConnectDialog(),
  );
  if (device == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('Connected to ${device.name}')));
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog();

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await WispScope.of(context).connect(_controller.text);
      if (mounted) Navigator.pop(context, device);
    } on ConnectException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final service = WispScope.of(context);
    final myCode = service.connectCode;
    final lastNumber = service.localAddress?.split('.').last;
    // A browser has no code of its own; it can only connect out.
    final web = service.isWebClient;

    return AlertDialog(
      title: const Text('Connect with code'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            if (web)
              Text(
                'On the other device, open Connect with code and type the '
                'browser address it shows under “No app on the other '
                'device?”.',
                style: text.bodyMedium,
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text('THIS DEVICE\'S CODE', style: text.labelSmall),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(
                      myCode ?? 'No network',
                      style: AppTheme.mono(fontSize: 18)
                          .copyWith(letterSpacing: 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Type it on the other device — or type theirs below.',
                style: text.bodyMedium,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                labelText: web ? 'Its browser address' : 'Other device\'s code',
                hintText: 'e.g. 192.168.1.24',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            if (lastNumber != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'On the same Wi-Fi the last number is enough '
                '(this device is $lastNumber).',
                style: text.bodySmall,
              ),
            ],
            if (service.browserUrl case final url?) ...[
              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              BrowserAddress(url: url),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}

/// "No app on the other device?" — this device's address for a browser,
/// with a QR code phones can scan.
class BrowserAddress extends StatelessWidget {
  const BrowserAddress({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: QrImageView(
            data: url,
            size: 104,
            padding: const EdgeInsets.all(AppSpacing.xs),
            semanticsLabel: 'QR code for $url',
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text('No app on the other device?', style: text.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Open this in its browser, or scan the code with its camera:',
                style: text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                url,
                style: text.bodyMedium?.copyWith(color: AppColors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
