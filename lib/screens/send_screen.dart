import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/shared_file.dart';
import '../services/wisp_service.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../utils/pick_files.dart';
import '../widgets/connect_dialog.dart';
import '../widgets/dashed_border.dart';
import '../widgets/device_card.dart';
import '../widgets/file_type_badge.dart';
import '../widgets/searching_card.dart';
import '../widgets/section_label.dart';
import 'transfer_screen.dart';

/// Page 2: review the picked files, then tap a device to send them.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key, required this.files});

  final List<SharedFile> files;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  late final List<SharedFile> _files = [...widget.files];

  Future<void> _addFiles() async {
    final more = await pickFiles();
    if (more.isNotEmpty) setState(() => _files.addAll(more));
  }

  void _remove(int index) => setState(() => _files.removeAt(index));

  void _sendTo(Device device) {
    final transfer = WispScope.of(context).send(device, List.of(_files));
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TransferScreen(transfer: transfer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final devices = WispScope.of(context).devices;
    final count = _files.length == 1 ? '1 item' : '${_files.length} items';
    final empty = _files.isEmpty;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 88,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        title: const Text('Send'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              empty ? 'Nothing selected' : '$count ready',
              style: text.headlineMedium,
            ),
            Text(
              empty
                  ? 'Tap + to add files'
                  : '${formatBytes(totalBytes(_files))} total',
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: .horizontal,
                itemCount: _files.length + 1,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, i) => i < _files.length
                    ? _FileThumb(
                        file: _files[i],
                        index: i,
                        onRemove: () => _remove(i),
                      )
                    : _AddTile(onTap: _addFiles),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('Tap a device to send'),
            const SizedBox(height: AppSpacing.md),
            if (devices.isEmpty) const SearchingCard(),
            for (var i = 0; i < devices.length; i += 2) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: _card(devices[i])),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: i + 1 < devices.length
                        ? _card(devices[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            Text(
              'Only devices on the same Wi-Fi show up here.',
              style: text.bodyMedium,
              textAlign: .center,
            ),
            TextButton(
              onPressed: () => connectWithCode(context),
              child: const Text('Device missing? Connect with a code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Device device) => DeviceCard(
    device: device,
    highlighted: _files.isNotEmpty,
    onTap: _files.isEmpty ? null : () => _sendTo(device),
  );
}

class _FileThumb extends StatelessWidget {
  const _FileThumb({
    required this.file,
    required this.index,
    required this.onRemove,
  });

  static const _size = 92.0;
  // Placeholder tints until real thumbnails are loaded.
  static const _tints = [Color(0xFFDCD6C9), Color(0xFFD0D6DC)];

  final SharedFile file;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: _size,
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Stack(
            children: [
              Container(
                width: _size,
                height: _size,
                alignment: .center,
                decoration: BoxDecoration(
                  color: file.isImage
                      ? _tints[index % _tints.length]
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: file.isImage
                      ? null
                      : Border.all(color: AppColors.border),
                ),
                child: file.isImage
                    ? const Icon(
                        Icons.image_outlined,
                        color: AppColors.textSecondary,
                      )
                    : FileTypeBadge(fileName: file.name, size: 48),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton.filled(
                  onPressed: onRemove,
                  tooltip: 'Remove',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.textPrimary.withValues(
                      alpha: 0.7,
                    ),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            file.name,
            style: text.titleSmall?.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: .ellipsis,
          ),
          Text(formatBytes(file.bytes), style: text.bodySmall),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: .topCenter,
      child: DashedBorder(
        radius: AppRadius.md,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: const SizedBox(
            width: 32,
            height: 88,
            child: Icon(Icons.add, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
