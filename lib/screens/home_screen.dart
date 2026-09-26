import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/shared_file.dart';
import '../models/transfer.dart';
import '../services/wisp_service.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../utils/pick_files.dart';
import '../utils/transfer_text.dart';
import '../widgets/searching_card.dart';
import '../widgets/device_avatar.dart';
import '../widgets/section_label.dart';
import '../widgets/settings_button.dart';
import '../widgets/toasts.dart';
import '../widgets/wisp_logo.dart';
import '../widgets/status_dot.dart';
import '../widgets/this_device_card.dart';
import '../widgets/transfer_icon.dart';
import '../widgets/voice_dialog.dart';
import 'desktop_home.dart';
import 'send_screen.dart';
import 'transfer_screen.dart';

/// Picks the phone layout (page 1) or the desktop layout (page 5)
/// depending on the window width.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const desktopBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= desktopBreakpoint
        ? const DesktopHome()
        : const MobileHome();
  }
}

/// Status line under this device's name.
String visibilityLabel(WispService service, {bool showCode = false}) {
  if (service.startError != null) return 'Offline · network error';
  if (!service.running) return 'Starting…';
  if (service.isWebClient) return connectedLabel(service.devices.length);
  if (showCode) return 'Visible · code ${service.connectCode ?? '—'}';
  return 'Visible · ready to receive';
}

/// In the browser there's no scanning, only devices connected by hand.
String connectedLabel(int count) => switch (count) {
  0 => 'Not connected yet',
  1 => 'Connected to 1 device',
  _ => 'Connected to $count devices',
};

void openTransfer(BuildContext context, Transfer transfer) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => TransferScreen(transfer: transfer)),
  );
}

/// Page 1: phone home screen.
class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  /// Runs a picker; then opens the Send screen, or sends straight to [to].
  Future<void> _pickAndSend(
    Future<List<SharedFile>> Function() pick, {
    Device? to,
  }) async {
    final List<SharedFile> files;
    try {
      files = await pick();
    } on Exception {
      _snack('Couldn\'t open the file picker');
      return;
    }
    if (!mounted || files.isEmpty) return;

    if (to != null) {
      openTransfer(context, WispScope.of(context).send(to, files));
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => SendScreen(files: files)),
      );
    }
  }

  Future<List<SharedFile>> _paste() async {
    final file = await clipboardAsFile();
    if (file == null) _snack('The clipboard has no text');
    return [?file];
  }

  void _snack(String message) {
    if (!mounted) return;
    ToastController.of(context).message(message);
  }

  @override
  Widget build(BuildContext context) {
    final service = WispScope.of(context);
    final devices = service.devices;
    final latest = service.transfers.lastOrNull;

    final sendActions = [
      (
        Icons.insert_drive_file_outlined,
        'Files',
        () => _pickAndSend(pickFiles),
      ),
      (
        Icons.image_outlined,
        'Photos',
        () => _pickAndSend(() => pickFiles(media: true)),
      ),
      (
        Icons.notes,
        'Text',
        () => _pickAndSend(() async => [?await askForText(context)]),
      ),
      (Icons.content_paste, 'Paste', () => _pickAndSend(_paste)),
      if (canRecordVoice)
        (
          Icons.mic_none,
          'Voice',
          () => _pickAndSend(() async => [?await recordVoice(context)]),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Row(
              children: [
                const WispWordmark(),
                const Spacer(),
                const SettingsButton(),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            ThisDeviceCard(
              device: service.self,
              visible: service.visible,
              visibleLabel: visibilityLabel(service),
              online: service.running,
              onVisibleChanged: (v) => service.visible = v,
            ),
            const SizedBox(height: AppSpacing.xxl),
            const SectionLabel('Send'),
            const SizedBox(height: AppSpacing.md),
            Row(
              spacing: AppSpacing.sm,
              children: [
                for (final (i, (icon, label, onTap)) in sendActions.indexed)
                  Expanded(
                    child: _SendTile(
                      icon: icon,
                      label: label,
                      primary: i == 0,
                      onTap: onTap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            SectionLabel(
              'Nearby · ${devices.length}',
              trailing: service.running && !service.isWebClient
                  ? const StatusDot(
                      label: 'Scanning Wi-Fi',
                      color: AppColors.accent,
                    )
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            if (devices.isEmpty)
              const SearchingCard()
            else
              Card(
                child: Column(
                  children: [
                    for (final (i, device) in devices.indexed) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.xs,
                        ),
                        leading: DeviceAvatar(platform: device.platform),
                        title: Text(device.name),
                        subtitle: Text(device.subtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => service.opensElsewhere(device)
                            ? service.handOff(device)
                            : _pickAndSend(pickFiles, to: device),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: latest == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: _LatestTransferBanner(
                  transfer: latest,
                  saveDirName: service.saveDirName,
                ),
              ),
            ),
    );
  }
}

class _SendTile extends StatelessWidget {
  const _SendTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.textPrimary;

    return Material(
      color: primary ? AppColors.accent : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: primary
            ? BorderSide.none
            : const BorderSide(color: AppColors.border),
      ),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 76,
          child: Column(
            mainAxisAlignment: .center,
            children: [
              Icon(icon, color: fg),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The most recent transfer, pinned to the bottom of the phone home screen.
class _LatestTransferBanner extends StatelessWidget {
  const _LatestTransferBanner({
    required this.transfer,
    required this.saveDirName,
  });

  final Transfer transfer;
  final String saveDirName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: transfer,
      builder: (context, _) {
        final t = transfer;
        final (fg, bg) = TransferIcon.colors(t);
        final received =
            t.direction == TransferDirection.receive &&
            t.status == TransferStatus.done;
        final subtitle = received
            ? '${formatWhen(t.finishedAt!)} · saved to $saveDirName'
            : transferSubtitle(t);

        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: .antiAlias,
          child: InkWell(
            onTap: () => openTransfer(context, t),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  TransferIcon(transfer: t, size: 36, solid: true),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      // Without this the banner grows to fill the screen.
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          transferTitle(t),
                          style: text.titleSmall,
                          overflow: .ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: text.bodySmall,
                          overflow: .ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Open', style: text.labelLarge?.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
