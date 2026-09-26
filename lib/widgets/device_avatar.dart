import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/tokens.dart';

/// Circle with the platform icon. [highlighted] gives the blue version
/// (send grid, incoming sheet); otherwise it's gray (home list, desktop).
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({
    super.key,
    required this.platform,
    this.size = 40,
    this.highlighted = false,
  });

  final DevicePlatform platform;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlighted ? AppColors.accentSoft : AppColors.surfaceMuted,
        shape: .circle,
      ),
      child: Icon(
        platform.icon,
        size: size * 0.45,
        color: highlighted ? AppColors.accent : AppColors.textPrimary,
      ),
    );
  }
}
