import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

abstract final class AppTheme {
  /// Monospace style for things like the "4F9A" security code.
  static TextStyle mono({double fontSize = 20}) => GoogleFonts.ibmPlexMono(
    fontSize: fontSize,
    fontWeight: .w600,
    letterSpacing: 4,
    color: AppColors.textPrimary,
  );

  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: .light,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      primaryContainer: AppColors.accentSoft,
      onPrimaryContainer: AppColors.accent,
      // Black "Choose files" button on desktop.
      secondary: AppColors.textPrimary,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
    );

    final textTheme = _textTheme();
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    const buttonSize = Size(0, 48);

    return ThemeData(
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium,
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: .antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium,
        iconColor: AppColors.textSecondary,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          minimumSize: buttonSize,
          shape: buttonShape,
          side: const BorderSide(color: AppColors.border),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: textTheme.labelLarge,
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.border,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.border, width: 1.5),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.border,
        circularTrackColor: AppColors.border,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
    );
  }

  /// Headings use a tight grotesk (Inter Tight is a close match to the
  /// mockups — swap it here if you find the exact font), body text uses
  /// IBM Plex Sans.
  static TextTheme _textTheme() {
    TextStyle heading(double size, {double spacing = 0}) =>
        GoogleFonts.interTight(
          fontSize: size,
          fontWeight: .w700,
          letterSpacing: spacing,
          color: AppColors.textPrimary,
        );

    TextStyle body(
      double size, {
      FontWeight weight = .w400,
      Color color = AppColors.textPrimary,
      double spacing = 0,
    }) => GoogleFonts.ibmPlexSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
    );

    return TextTheme(
      // Big numbers: "62%"
      displayMedium: heading(44, spacing: -0.5),
      // Page titles: "Wisp", "3 items ready", "Nearby devices"
      headlineMedium: heading(30, spacing: -0.2),
      // Sub-headings: "MacBook Pro" on Sending, the incoming sheet title
      headlineSmall: heading(22),
      // Stat values: "38 MB/s", "About 1 s"
      titleLarge: body(20, weight: .w600),
      // Device names, card titles, app bar titles
      titleMedium: body(16, weight: .w600),
      titleSmall: body(14, weight: .w600),
      // File names, regular text
      bodyLarge: body(16),
      // Secondary lines: "macOS", "2 min ago · saved to Photos"
      bodyMedium: body(14, color: AppColors.textSecondary),
      bodySmall: body(12, color: AppColors.textSecondary),
      // Button labels
      labelLarge: body(15, weight: .w600),
      // Section labels: "SEND", "NEARBY · 4" (write the text in caps)
      labelSmall: body(
        12,
        weight: .w600,
        color: AppColors.textSecondary,
        spacing: 1.2,
      ),
    );
  }
}
