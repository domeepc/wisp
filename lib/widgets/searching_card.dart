import 'package:flutter/material.dart';

import '../services/wisp_service.dart';
import '../theme/tokens.dart';
import 'connect_dialog.dart';

/// Placeholder shown while there are no devices to send to yet.
class SearchingCard extends StatelessWidget {
  const SearchingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final service = WispScope.of(context);
    final error = service.startError;

    final Widget leading;
    final String title;
    final String hint;
    if (error != null) {
      leading = const Icon(Icons.wifi_off, color: AppColors.textSecondary);
      (title, hint) = ('Couldn\'t start networking', error);
    } else if (service.isWebClient) {
      // A browser can't look for devices; it connects by address.
      leading = const Icon(Icons.link, color: AppColors.accent);
      (title, hint) = (
        'Connect to a Wisp device',
        'A browser can\'t find devices by itself. On the other device, open '
            'Connect with code and type the browser address it shows.',
      );
    } else {
      leading = const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
      (title, hint) = (
        'Looking for devices…',
        'Open Wisp on another device on the same Wi-Fi.',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Row(
          children: [
            leading,
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(title, style: text.titleMedium),
                  Text(hint, style: text.bodyMedium),
                  if (service.isWebClient && error == null) ...[
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => connectWithCode(context),
                      child: const Text('Connect'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
