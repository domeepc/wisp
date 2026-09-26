import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/tokens.dart';
import 'device_avatar.dart';
import 'status_dot.dart';

/// "This device" card with the visibility switch, at the top of Home.
/// Pass [color] for the gray desktop variant.
class ThisDeviceCard extends StatelessWidget {
  const ThisDeviceCard({
    super.key,
    required this.device,
    required this.visible,
    required this.visibleLabel,
    required this.onVisibleChanged,
    this.online = true,
    this.color,
    this.onTap,
  });

  final Device device;
  final bool visible;

  /// Status shown while visible, e.g. "Visible · ready to receive".
  final String visibleLabel;
  final ValueChanged<bool> onVisibleChanged;

  /// False while networking is starting or broken: the dot turns gray.
  final bool online;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: color == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              DeviceAvatar(
                platform: device.platform,
                size: 48,
                highlighted: true,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      device.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    visible
                        ? StatusDot(
                            label: visibleLabel,
                            color: online
                                ? AppColors.success
                                : AppColors.textSecondary,
                          )
                        : const StatusDot(
                            label: 'Hidden',
                            color: AppColors.textSecondary,
                          ),
                  ],
                ),
              ),
              Switch(value: visible, onChanged: onVisibleChanged),
            ],
          ),
        ),
      ),
    );
  }
}
