import 'dart:math';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/shared_file.dart';
import '../models/transfer.dart';
import '../services/wisp_service.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../utils/open_folder.dart';
import '../utils/pick_files.dart';
import '../utils/transfer_text.dart';
import '../widgets/connect_dialog.dart';
import '../widgets/dashed_border.dart';
import '../widgets/device_card.dart';
import '../widgets/file_type_badge.dart';
import '../widgets/searching_card.dart';
import '../widgets/section_label.dart';
import '../widgets/settings_button.dart';
import '../widgets/toasts.dart';
import '../widgets/wisp_logo.dart';
import '../widgets/status_dot.dart';
import '../widgets/this_device_card.dart';
import '../widgets/transfer_icon.dart';
import 'home_screen.dart';

/// Page 5: desktop layout — sidebar for picking files, main area for
/// devices and transfer history.
class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key});

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  final List<SharedFile> _selected = [];

  Future<void> _add(Future<List<SharedFile>> Function() pick) async {
    try {
      final files = await pick();
      if (mounted) setState(() => _selected.addAll(files));
    } on Exception {
      if (!mounted) return;
      Toasts.of(context).message(
        'Couldn\'t open the file picker',
        icon: Icons.error_outline,
        tone: ToastTone.error,
      );
    }
  }

  void _sendTo(Device device) {
    final transfer = WispScope.of(context).send(device, List.of(_selected));
    openTransfer(context, transfer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: .stretch,
        children: [
          Container(
            width: 400,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: _buildSidebar(context),
          ),
          Expanded(child: _buildMain(context)),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final service = WispScope.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
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
          visibleLabel: visibilityLabel(service, showCode: true),
          color: AppColors.background,
          online: service.running,
          onVisibleChanged: (v) => service.visible = v,
        ),
        const SizedBox(height: AppSpacing.xl),
        _DropZone(
          onDrop: (items) => _add(
            // In a browser dropped files have no paths, only contents.
            () => kIsWeb
                ? filesFromDropped(items)
                : filesFromPaths([for (final f in items) f.path]),
          ),
          onChooseFiles: () => _add(pickFiles),
          onSendText: () => _add(() async => [?await askForText(context)]),
        ),
        const SizedBox(height: AppSpacing.xxl),
        SectionLabel(
          _selected.isEmpty
              ? 'Selected'
              : 'Selected · ${formatBytes(totalBytes(_selected))}',
          trailing: TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => setState(_selected.clear),
            child: const Text('Clear'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_selected.isEmpty)
          Text('Nothing selected yet.', style: text.bodyMedium)
        else
          for (final (i, file) in _selected.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SelectedFileRow(
                file: file,
                onRemove: () => setState(() => _selected.removeAt(i)),
              ),
            ),
      ],
    );
  }

  Widget _buildMain(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final service = WispScope.of(context);
    final devices = service.devices;
    final transfers = service.transfers.reversed.take(10).toList();
    final count = _selected.length;

    return ListView(
      padding: const EdgeInsets.all(44),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text('Nearby devices', style: text.headlineMedium),
                  if (service.running)
                    StatusDot(
                      label: service.isWebClient
                          ? connectedLabel(devices.length)
                          : 'Scanning your Wi-Fi · ${devices.length} found',
                      color: AppColors.accent,
                    ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: () => connectWithCode(context),
              child: const Text('Connect with code'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        if (devices.isEmpty)
          const SearchingCard()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.lg;
              const minCardWidth = 190.0;
              final columns = max(
                1,
                ((constraints.maxWidth + gap) / (minCardWidth + gap)).floor(),
              );
              final cardWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final device in devices)
                    SizedBox(
                      width: cardWidth,
                      child: DeviceCard(
                        device: device,
                        action: FilledButton(
                          onPressed: count == 0 ? null : () => _sendTo(device),
                          child: Text(switch (count) {
                            0 => 'Select files first',
                            1 => 'Send 1 file',
                            _ => 'Send $count files',
                          }),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: AppSpacing.xxl),
        SectionLabel(
          'Transfers',
          trailing: service.saveDir != null && canOpenFolders
              ? TextButton(
                  onPressed: () => openFolder(service.saveDir!),
                  child: Text(
                    'Open ${service.saveDirName.toLowerCase()} folder',
                  ),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (transfers.isEmpty)
          Text('No transfers yet.', style: text.bodyMedium)
        else
          Card(
            child: Column(
              children: [
                for (final (i, transfer) in transfers.indexed) ...[
                  if (i > 0) const Divider(),
                  _TransferRow(
                    transfer: transfer,
                    // "Send again" needs the device to still be around.
                    peerNow: devices
                        .where((d) => d.id == transfer.peer.id)
                        .firstOrNull,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DropZone extends StatefulWidget {
  const _DropZone({
    required this.onDrop,
    required this.onChooseFiles,
    required this.onSendText,
  });

  final ValueChanged<List<DropItem>> onDrop;
  final VoidCallback onChooseFiles;
  final VoidCallback onSendText;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        widget.onDrop(details.files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _dragging ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: DashedBorder(
          color: _dragging ? AppColors.accent : AppColors.borderStrong,
          child: _content(text),
        ),
      ),
    );
  }

  Widget _content(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 44,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.accentSoft,
              shape: .circle,
            ),
            child: const Icon(
              Icons.file_upload_outlined,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Drop files or folders here', style: text.titleMedium),
          Text('then click a device to send', style: text.bodyMedium),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: .center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                ),
                onPressed: widget.onChooseFiles,
                child: const Text('Choose files'),
              ),
              OutlinedButton(
                onPressed: widget.onSendText,
                child: const Text('Send text'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectedFileRow extends StatelessWidget {
  const _SelectedFileRow({required this.file, required this.onRemove});

  final SharedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            FileTypeBadge(fileName: file.name, size: 34),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                file.name,
                style: text.bodyLarge,
                overflow: .ellipsis,
              ),
            ),
            Text(formatBytes(file.bytes), style: text.bodySmall),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.transfer, required this.peerNow});

  final Transfer transfer;

  /// The peer as currently discovered, or null if it's gone.
  final Device? peerNow;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: transfer,
      builder: (context, _) {
        final t = transfer;
        final running = t.status == TransferStatus.running;

        return InkWell(
          onTap: () => openTransfer(context, t),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: Row(
              children: [
                TransferIcon(transfer: t),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              transferTitle(t),
                              style: text.titleSmall,
                              overflow: .ellipsis,
                            ),
                          ),
                          if (running)
                            Text(transferSubtitle(t), style: text.bodySmall),
                        ],
                      ),
                      if (running) ...[
                        const SizedBox(height: AppSpacing.sm),
                        LinearProgressIndicator(
                          value: t.progress,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ] else
                        Text(transferSubtitle(t), style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                ?_action(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget? _action(BuildContext context) {
    final t = transfer;
    if (t.status.isActive) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
        onPressed: t.cancel,
        child: const Text('Cancel'),
      );
    }
    if (t.status != TransferStatus.done) return null;

    if (t.direction == TransferDirection.receive) {
      if (t.saveDir == null || !canOpenFolders) return null;
      return TextButton(
        onPressed: () => openFolder(t.saveDir!),
        child: const Text('Show in folder'),
      );
    }
    final peer = peerNow;
    if (peer == null) return null;
    return TextButton(
      onPressed: () =>
          openTransfer(context, WispScope.of(context).send(peer, t.files)),
      child: const Text('Send again'),
    );
  }
}
