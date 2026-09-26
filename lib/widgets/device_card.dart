import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/tokens.dart';
import 'device_avatar.dart';

/// Device as a card: the phone's send grid and the desktop's device row.
/// [action] goes at the bottom, e.g. the desktop "Send 2 files" button.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
    this.highlighted = false,
    this.action,
  });

  final Device device;
  final VoidCallback? onTap;
  final bool highlighted;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              DeviceAvatar(
                platform: device.platform,
                size: 48,
                highlighted: highlighted,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                device.name,
                style: text.titleMedium,
                maxLines: 1,
                overflow: .ellipsis,
              ),
              Text(
                device.subtitle,
                style: text.bodyMedium,
                maxLines: 1,
                overflow: .ellipsis,
              ),
              if (action case final action?) ...[
                const SizedBox(height: AppSpacing.lg),
                SizedBox(width: double.infinity, child: action),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
