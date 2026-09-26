import 'package:flutter/material.dart';

import '../models/transfer.dart';
import '../theme/tokens.dart';

/// Round status icon for a transfer: arrow while running, check when
/// done, cross when it failed. [solid] fills the circle (home banner).
class TransferIcon extends StatelessWidget {
  const TransferIcon({
    super.key,
    required this.transfer,
    this.size = 40,
    this.solid = false,
  });

  final Transfer transfer;
  final double size;
  final bool solid;

  /// Foreground and soft background colors for [t]'s current state.
  static (Color, Color) colors(Transfer t) => switch (t.status) {
    TransferStatus.waiting ||
    TransferStatus.running => (AppColors.accent, AppColors.accentSoft),
    TransferStatus.done when t.direction == TransferDirection.receive => (
      AppColors.success,
      AppColors.successSoft,
    ),
    TransferStatus.done => (AppColors.textSecondary, AppColors.surfaceMuted),
    _ => (AppColors.danger, AppColors.dangerSoft),
  };

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final (fg, bg) = colors(t);
    final icon = switch (t.status) {
      TransferStatus.waiting || TransferStatus.running =>
        t.direction == TransferDirection.send
            ? Icons.arrow_upward
            : Icons.arrow_downward,
      TransferStatus.done
          when !solid && t.direction == TransferDirection.receive =>
        Icons.arrow_downward,
      TransferStatus.done => Icons.check,
      _ => Icons.close,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: solid ? fg : bg, shape: .circle),
      child: Icon(icon, size: size * 0.5, color: solid ? Colors.white : fg),
    );
  }
}
