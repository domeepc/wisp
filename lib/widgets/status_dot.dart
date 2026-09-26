import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Colored dot followed by a label: "● Visible · ready to receive".
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.label,
    this.color = AppColors.success,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: .circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: .ellipsis,
          ),
        ),
      ],
    );
  }
}
