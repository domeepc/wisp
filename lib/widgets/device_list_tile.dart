import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/tokens.dart';
import 'device_avatar.dart';

/// Row in the home screen's "Nearby" list. Put several inside a Card,
/// separated by Dividers.
class DeviceListTile extends StatelessWidget {
  const DeviceListTile({super.key, required this.device, this.onTap});

  final Device device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: DeviceAvatar(platform: device.platform),
      title: Text(device.name),
      subtitle: Text(device.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
