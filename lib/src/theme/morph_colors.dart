import 'package:flutter/material.dart';

/// What a dev declares when they have a dedicated `AppColors` file or any
/// other palette they maintain by hand. Everything is optional — missing
/// slots are filled in from the ambient [ThemeData] by [ColorExtractor].
///
/// In practice only [background] and [primary] are the "minimum viable" —
/// anything below that and we can't decide light vs. dark or pick a brand
/// accent, but even those will fall back to Flutter defaults if omitted.
@immutable
class MorphColors {
  // Minimum vital
  final Color? background;
  final Color? primary;

  // Surfaces
  final Color? surface;
  final Color? surfaceSecondary;

  // Text
  final Color? text;
  final Color? textSecondary;
  final Color? textTertiary;
  final Color? textInverted;

  // Border / outline
  final Color? border;

  // Status
  final Color? error;
  final Color? success;
  final Color? warning;

  // Accent
  final Color? secondary;

  const MorphColors({
    this.background,
    this.primary,
    this.surface,
    this.surfaceSecondary,
    this.text,
    this.textSecondary,
    this.textTertiary,
    this.textInverted,
    this.border,
    this.error,
    this.success,
    this.warning,
    this.secondary,
  });

  /// Convenience for devs whose `AppColors` already exposes a
  /// `Map<String, Color>` — pass it directly, missing keys are ignored.
  factory MorphColors.fromMap(Map<String, Color> colors) {
    return MorphColors(
      background: colors['background'],
      primary: colors['primary'],
      surface: colors['surface'],
      surfaceSecondary: colors['surfaceSecondary'],
      text: colors['text'],
      textSecondary: colors['textSecondary'],
      textTertiary: colors['textTertiary'],
      textInverted: colors['textInverted'],
      border: colors['border'],
      error: colors['error'],
      success: colors['success'],
      warning: colors['warning'],
      secondary: colors['secondary'],
    );
  }

  bool get isEmpty =>
      background == null &&
      primary == null &&
      surface == null &&
      surfaceSecondary == null &&
      text == null &&
      textSecondary == null &&
      textTertiary == null &&
      textInverted == null &&
      border == null &&
      error == null &&
      success == null &&
      warning == null &&
      secondary == null;
}
