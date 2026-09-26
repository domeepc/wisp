import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Colored square showing a file's extension: PDF, MP4, FIG, ZIP.
class FileTypeBadge extends StatelessWidget {
  const FileTypeBadge({super.key, required this.fileName, this.size = 36});

  final String fileName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();

    final (fg, bg) = switch (ext) {
      'pdf' => (AppColors.danger, AppColors.dangerSoft),
      'mp4' || 'mov' || 'zip' => (AppColors.accent, AppColors.accentSoft),
      'fig' => (AppColors.purple, AppColors.purpleSoft),
      _ => (AppColors.textSecondary, AppColors.surfaceMuted),
    };

    return Container(
      width: size,
      height: size,
      alignment: .center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        ext.isEmpty ? 'FILE' : ext.toUpperCase(),
        maxLines: 1,
        overflow: .clip,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: .w700,
          fontSize: size * 0.3,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
