import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The app icon: the "w" mark on a blue rounded square. Drawn in code
/// from the same shapes as assets/brand/wisp_icon.svg, so it's sharp at
/// any size.
class WispLogo extends StatelessWidget {
  const WispLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _LogoPainter()),
  );
}

/// The logo and the name, as in the app's headers.
class WispWordmark extends StatelessWidget {
  const WispWordmark({super.key, this.size = 34});

  /// The logo's size; the name is sized to match.
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: size * 0.9,
      fontWeight: .w800,
      letterSpacing: -size * 0.05,
    );
    return Row(
      mainAxisSize: .min,
      children: [
        WispLogo(size: size),
        SizedBox(width: size * 0.3),
        Text('Wisp', style: style),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // The shapes are on a 100 × 100 grid, like the SVG.
    canvas.scale(size.width / 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Radius.circular(28),
      ),
      Paint()..color = AppColors.accent,
    );

    final white = Paint()..color = Colors.white;
    final mark = Path()
      ..moveTo(20.5, 34.5)
      ..cubicTo(23.5, 46, 29.5, 66, 35.5, 66)
      ..cubicTo(41.5, 66, 45, 50.5, 50, 50.5)
      ..cubicTo(55, 50.5, 58.5, 66, 64.5, 66)
      ..cubicTo(70.5, 66, 76.5, 46, 79.5, 34.5);
    canvas.drawPath(
      mark,
      Paint()
        ..color = Colors.white
        ..style = .stroke
        ..strokeWidth = 9
        ..strokeCap = .round
        ..strokeJoin = .round,
    );
    // The ends are slightly thicker dots.
    canvas.drawCircle(const Offset(20.5, 34.5), 5.3, white);
    canvas.drawCircle(const Offset(79.5, 34.5), 5.3, white);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
