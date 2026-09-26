import 'package:flutter/material.dart';

import '../models/shared_file.dart';
import '../services/wisp_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../utils/open_folder.dart';
import '../utils/pick_files.dart';
import '../widgets/device_avatar.dart';
import '../widgets/file_type_badge.dart';

/// Page 4: another device wants to send files. Accepting or declining
/// answers [request]; dismissing the sheet counts as declining. Returns
/// whether it was accepted.
Future<bool> showIncomingSheet(
  BuildContext context, {
  required IncomingRequest request,
}) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _IncomingSheet(request: request),
  );
  if (accepted != true) request.decline();
  return accepted ?? false;
}

class _IncomingSheet extends StatefulWidget {
  const _IncomingSheet({required this.request});

  final IncomingRequest request;

  @override
  State<_IncomingSheet> createState() => _IncomingSheetState();
}

class _IncomingSheetState extends State<_IncomingSheet> {
  bool _alwaysAccept = false;
  String? _folderError;

  Future<void> _changeFolder() async {
    final dir = await pickFolder(title: 'Save received files to');
    if (dir == null || !mounted) return;
    final ok = await WispScope.of(context).setSaveDir(dir);
    if (mounted) {
      setState(() => _folderError = ok ? null : 'Can\'t save to that folder');
    }
  }

  @override
  void initState() {
    super.initState();
    widget.request.cancelled.addListener(_onCancelled);
  }

  @override
  void dispose() {
    widget.request.cancelled.removeListener(_onCancelled);
    super.dispose();
  }

  /// The sender gave up (or it timed out): close the sheet.
  void _onCancelled() {
    if (widget.request.cancelled.value && mounted) {
      Navigator.pop(context, false);
    }
  }

  void _answer(bool accept) {
    if (accept) widget.request.accept(always: _alwaysAccept);
    Navigator.pop(context, accept);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final offer = widget.request.offer;
    final files = offer.files;
    final count = files.length == 1 ? '1 file' : '${files.length} files';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Row(
              children: [
                DeviceAvatar(
                  platform: offer.from.platform,
                  size: 52,
                  highlighted: true,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(offer.from.name, style: text.headlineSmall),
                      Text(
                        'wants to send you $count · '
                        '${formatBytes(totalBytes(files))}',
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (final (i, file) in files.indexed) ...[
                    if (i > 0) const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
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
                          Text(formatBytes(file.bytes), style: text.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Files shared from another device to a browser come without a
            // code (there's no certificate to check).
            if (offer.securityCode.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Text('Security code', style: text.bodyMedium),
                    const Spacer(),
                    Text(offer.securityCode, style: AppTheme.mono()),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Save to ',
                      children: [
                        TextSpan(
                          text: WispScope.of(context).saveDirName,
                          style: text.titleSmall,
                        ),
                      ],
                    ),
                    style: text.bodyMedium,
                    overflow: .ellipsis,
                  ),
                ),
                // Other folders need extra permissions on phones.
                if (canOpenFolders)
                  TextButton(
                    onPressed: _changeFolder,
                    child: const Text('Change'),
                  ),
              ],
            ),
            if (_folderError case final error?)
              Text(
                error,
                style: text.bodySmall?.copyWith(color: AppColors.danger),
              ),
            CheckboxListTile(
              value: _alwaysAccept,
              onChanged: (v) => setState(() => _alwaysAccept = v ?? false),
              title: Text(
                'Always accept from this device',
                style: text.bodyLarge,
              ),
              controlAffinity: .leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => _answer(false),
                      child: const Text('Decline'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () => _answer(true),
                      child: const Text('Accept'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
