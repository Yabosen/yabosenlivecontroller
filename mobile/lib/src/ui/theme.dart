import 'package:flutter/material.dart';

import '../models.dart';

/// Palette matching the yabosen.live dark purple theme.
abstract final class AppColors {
  static const background = Color(0xFF0E0A12);
  static const surface = Color(0xFF2B2434);
  static const surfaceHigh = Color(0xFF362D41);
  static const field = Color(0xFF16111C);
  static const text = Color(0xFFE8DEFA);
  static const muted = Color(0xFFA397B8);
  static const accent = Color(0xFFB98CFF);
  static const selection = Color(0xFF7C4DCC);
  static const border = Color(0xFF463B54);
  static const error = Color(0xFFEF4444);
  static const success = Color(0xFF22C55E);
}

/// Corner radius used everywhere: square-ish for a retro feel.
const double kRadius = 4;
const BorderRadius kBorderRadius = BorderRadius.all(Radius.circular(kRadius));
const RoundedRectangleBorder kShape = RoundedRectangleBorder(
  borderRadius: kBorderRadius,
);

extension StatusKindColor on StatusKind {
  Color get color => switch (this) {
    StatusKind.online => const Color(0xFF22C55E),
    StatusKind.offline => const Color(0xFF6B7280),
    StatusKind.dnd => const Color(0xFFEF4444),
    StatusKind.idle => const Color(0xFFEAB308),
    StatusKind.sleeping => const Color(0xFFA855F7),
    StatusKind.streaming => const Color(0xFFEF4444),
  };
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.accent,
    onPrimary: Color(0xFF1B0F2B),
    primaryContainer: AppColors.selection,
    onPrimaryContainer: AppColors.text,
    secondary: AppColors.selection,
    onSecondary: AppColors.text,
    secondaryContainer: AppColors.selection,
    onSecondaryContainer: AppColors.text,
    error: AppColors.error,
    onError: Colors.white,
    surface: AppColors.background,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerLowest: AppColors.field,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceHigh,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    inverseSurface: AppColors.text,
    onInverseSurface: AppColors.background,
    inversePrimary: AppColors.selection,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  const buttonShape = WidgetStatePropertyAll<OutlinedBorder>(kShape);
  const buttonPadding = WidgetStatePropertyAll<EdgeInsetsGeometry>(
    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarThemeData(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: kBorderRadius,
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.field,
      isDense: true,
      labelStyle: TextStyle(color: AppColors.muted),
      hintStyle: TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: kBorderRadius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: kBorderRadius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: kBorderRadius,
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: AppColors.selection,
      selectionHandleColor: AppColors.accent,
    ),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(shape: buttonShape, padding: buttonPadding),
    ),
    outlinedButtonTheme: const OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        padding: buttonPadding,
        side: WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
      ),
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    segmentedButtonTheme: const SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        side: WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.selection,
      indicatorShape: kShape,
      height: 64,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: kShape,
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: AppColors.surface,
      shape: kShape,
      hourMinuteShape: kShape,
      dayPeriodShape: kShape,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: kShape,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.text),
      actionTextColor: AppColors.accent,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    listTileTheme: const ListTileThemeData(
      shape: kShape,
      contentPadding: EdgeInsets.zero,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
  );
}
