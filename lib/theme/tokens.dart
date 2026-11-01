import 'package:flutter/painting.dart';

/// Colors picked from the mockups. Values are eyeballed from the exported
/// screens — fine-tune them against the design file if you have it.
abstract final class AppColors {
  // Surfaces
  static const background = Color(0xFFF6F5F1); // warm paper page
  static const surface = Color(0xFFFFFEFA); // cards, sheets
  // Gray icon circles, security code box.
  static const surfaceMuted = Color(0xFFEFEEE9);
  // Card outlines, dividers, progress track.
  static const border = Color(0xFFE5E2DA);
  // Dashed drop zones.
  static const borderStrong = Color(0xFFCBC7BD);

  // Text
  static const textPrimary = Color(0xFF171D2B);
  static const textSecondary = Color(0xFF686C75);

  // Accent (blue)
  static const accent = Color(0xFF3157D5);
  static const accentSoft = Color(0xFFE9EDFA); // icon circles, MP4/ZIP badges

  // Status
  static const success = Color(0xFF1F7A4D);
  static const successSoft = Color(0xFFE6F0EA); // "12 photos from…" banner
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFF8E3DF); // PDF badge

  // Extra file-type badge (FIG)
  static const purple = Color(0xFF6B4BC8);
  static const purpleSoft = Color(0xFFEFEAFB);
}

/// Corner radii. The phone mockups are exported at ~2x, so these are
/// half the measured pixel values.
abstract final class AppRadius {
  static const sm = 8.0; // file-type badges
  static const md = 14.0; // buttons, send tiles
  static const lg = 24.0; // cards
  static const sheet = 28.0; // bottom sheet top corners
}

/// Spacing scale. Use these instead of magic numbers in padding/gaps.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0; // page side padding on phone
  static const xxl = 28.0; // gap between sections
}
