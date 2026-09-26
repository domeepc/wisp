import 'package:flutter/material.dart';

import '../models/shared_file.dart';
import '../models/transfer.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/format.dart';
import '../utils/open_folder.dart';
import '../utils/transfer_text.dart';

/// Page 3: live progress of one transfer, sending or receiving.
class TransferScreen extends StatelessWidget {
  const TransferScreen({super.key, required this.transfer});

  final Transfer transfer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: transfer,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = transfer;
    final sending = t.direction == TransferDirection.send;
    final active = t.status.isActive;

    final title = switch (t.status) {
      TransferStatus.waiting => 'Waiting',
      TransferStatus.running => sending ? 'Sending' : 'Receiving',
      TransferStatus.done => sending ? 'Sent' : 'Received',
      TransferStatus.declined => 'Declined',
      TransferStatus.cancelled => 'Cancelled',
      TransferStatus.failed => 'Failed',
    };

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 80,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(active ? 'Hide' : 'Close'),
        ),
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(
                  sending ? 'To' : 'From',
                  style: text.bodyMedium,
                  textAlign: .center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: .center,
                  children: [
                    Icon(t.peer.platform.icon, color: AppColors.accent),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(
                        t.peer.name,
                        style: text.headlineSmall,
                        overflow: .ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Center(
                  child: _ProgressRing(
                    progress: t.progress,
                    caption: t.status == TransferStatus.waiting
                        ? (toBrowser(t)
                              ? 'Waiting for download'
                              : 'Waiting to accept')
                        : '${formatBytes(t.bytesDone)} of '
                              '${formatBytes(t.totalBytes)}',
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                ..._middle(context),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: Column(
                    children: [
                      for (final (i, file) in t.files.indexed) ...[
                        if (i > 0) const Divider(),
                        _FileProgressRow(
                          file: file,
                          sent: t.fileBytesDone[i],
                          transferActive: active,
                          doneLabel: sending ? 'Sent' : 'Saved',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SizedBox(height: 56, child: _bottomButton(context)),
        ),
      ),
    );
  }

  /// Security code while waiting, speed/time while running, or what went
  /// wrong once it's over.
  List<Widget> _middle(BuildContext context) {
    final t = transfer;
    final text = Theme.of(context).textTheme;

    switch (t.status) {
      case TransferStatus.waiting when toBrowser(t):
        return [
          _InfoBox(
            children: [
              Expanded(
                child: Text(
                  'It\'s waiting under “Shared with you” on ${t.peer.name}. '
                  'It\'s sent once they download it.',
                  style: text.bodyLarge,
                  textAlign: .center,
                ),
              ),
            ],
          ),
        ];
      case TransferStatus.waiting:
        return [
          _InfoBox(
            children: [
              Text('Security code', style: text.bodyMedium),
              const Spacer(),
              Text(t.securityCode, style: AppTheme.mono()),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Check that ${t.peer.name} shows the same code.',
            style: text.bodyMedium,
            textAlign: .center,
          ),
        ];
      case TransferStatus.running || TransferStatus.done:
        final done = t.status == TransferStatus.done;
        final left = t.speed > 0
            ? formatTimeLeft((t.totalBytes - t.bytesDone) / t.speed)
            : '—';
        return [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Speed',
                  value: done || t.speed == 0
                      ? '—'
                      : '${formatBytes(t.speed)}/s',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _StatCard(
                  label: 'Time left',
                  value: done ? 'Done' : left,
                ),
              ),
            ],
          ),
        ];
      case TransferStatus.declined ||
          TransferStatus.cancelled ||
          TransferStatus.failed:
        final message = switch (t.status) {
          TransferStatus.declined => '${t.peer.name} declined the files.',
          _ => t.error ?? 'The transfer was cancelled.',
        };
        return [
          _InfoBox(
            children: [
              Expanded(
                child: Text(message, style: text.bodyLarge, textAlign: .center),
              ),
            ],
          ),
        ];
    }
  }

  Widget _bottomButton(BuildContext context) {
    final t = transfer;
    if (t.status.isActive) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
        onPressed: t.cancel,
        child: const Text('Cancel transfer'),
      );
    }
    final showFolder =
        t.direction == TransferDirection.receive &&
        t.status == TransferStatus.done &&
        t.saveDir != null &&
        canOpenFolders;
    if (showFolder) {
      return FilledButton(
        onPressed: () => openFolder(t.saveDir!),
        child: const Text('Show in folder'),
      );
    }
    return FilledButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Done'),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.progress, required this.caption});

  final double progress;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SizedBox.square(
      dimension: 180,
      child: Stack(
        fit: .expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 14,
            strokeCap: .round,
            backgroundColor: AppColors.border,
          ),
          Column(
            mainAxisAlignment: .center,
            children: [
              Text('${(progress * 100).round()}%', style: text.displayMedium),
              Text(caption, style: text.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(children: children),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(label, style: text.bodyMedium),
            const SizedBox(height: 2),
            Text(value, style: text.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _FileProgressRow extends StatelessWidget {
  const _FileProgressRow({
    required this.file,
    required this.sent,
    required this.transferActive,
    required this.doneLabel,
  });

  final SharedFile file;
  final int sent;
  final bool transferActive;
  final String doneLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = sent >= file.bytes && (sent > 0 || !transferActive);
    final started = sent > 0;
    final fraction = file.bytes == 0 ? 1.0 : sent / file.bytes;
    final inProgress = started && !done && transferActive;

    final Widget icon;
    final Widget status;
    if (done) {
      icon = Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: AppColors.success,
          shape: .circle,
        ),
        child: const Icon(Icons.check, size: 16, color: Colors.white),
      );
      status = Text(
        doneLabel,
        style: text.titleSmall?.copyWith(color: AppColors.success),
      );
    } else {
      icon = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: .circle,
          border: Border.all(
            color: inProgress ? AppColors.accent : AppColors.border,
            width: 2,
          ),
        ),
      );
      status = Text(
        inProgress
            ? '${(fraction * 100).round()}%'
            : transferActive
            ? 'Waiting'
            : 'Not sent',
        style: text.bodyMedium,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          icon,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        style: text.bodyLarge,
                        overflow: .ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    status,
                  ],
                ),
                if (inProgress) ...[
                  const SizedBox(height: AppSpacing.sm),
                  LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
