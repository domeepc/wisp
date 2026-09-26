import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../theme/tokens.dart';

/// Round outlined settings button in the top-right corner of Home.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: 'Settings',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      ),
      icon: const Icon(Icons.tune),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        fixedSize: const Size.square(48),
      ),
    );
  }
}
