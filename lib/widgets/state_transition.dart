import 'package:flutter/material.dart';

/// A short transition for occasional changes between whole interface states.
class StateTransition extends StatelessWidget {
  const StateTransition({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedSwitcher(
      duration: Duration(milliseconds: reducedMotion ? 100 : 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
