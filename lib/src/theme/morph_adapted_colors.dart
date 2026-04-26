import 'package:flutter/material.dart';

import '../models/theme_model.dart';

/// Semantic color palette produced by Morph after adapting the app's base
/// colors to the current OS settings (dark mode, high contrast, etc.).
///
/// Read from any widget via the [BuildContext.morphPalette] extension:
/// ```dart
/// static Color background(BuildContext ctx) =>
///     ctx.morphPalette?.background ?? AppColorsNeutral.s50;
/// ```
///
/// Returns null when no adaptation is needed (system brightness matches the
/// app's base theme) — callers should fall back to their own base values.
@immutable
class MorphAdaptedColors {
  final Color background;
  final Color surface;
  final Color surfaceSecondary;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverted;
  final Color border;
  final Color success;
  final Color warning;
  final Color error;
  final Brightness brightness;

  const MorphAdaptedColors({
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverted,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
    required this.brightness,
  });

  bool get isDark => brightness == Brightness.dark;

  /// Build from a fully adapted [ThemeData]. The optional [generated] palette
  /// supplements Material-named slots with custom semantic colors (success,
  /// warning) that are absent from the standard [ColorScheme].
  static MorphAdaptedColors fromTheme(
    ThemeData theme, {
    GeneratedTheme? generated,
  }) {
    final cs = theme.colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    Color? genHex(String? hex) {
      if (hex == null || !hex.startsWith('#')) return null;
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    }

    // ignore: deprecated_member_use
    final surfSec = cs.surfaceVariant;
    // ignore: deprecated_member_use
    final textSec = cs.onSurfaceVariant;

    return MorphAdaptedColors(
      background: theme.scaffoldBackgroundColor,
      surface: cs.surface,
      surfaceSecondary: surfSec,
      primary: cs.primary,
      onPrimary: cs.onPrimary,
      secondary: cs.secondary,
      text: cs.onSurface,
      textSecondary: textSec,
      // ignore: deprecated_member_use
      textTertiary: textSec.withOpacity(0.6),
      textInverted: cs.onPrimary,
      border: cs.outline,
      success: genHex(generated?.success) ??
          (isDark ? const Color(0xFF47CD89) : const Color(0xFF17B26A)),
      warning: genHex(generated?.warning) ??
          (isDark ? const Color(0xFFFEC84B) : const Color(0xFFF79009)),
      error: cs.error,
      brightness: cs.brightness,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphAdaptedColors &&
          background == other.background &&
          surface == other.surface &&
          primary == other.primary &&
          brightness == other.brightness;

  @override
  int get hashCode => Object.hash(background, surface, primary, brightness);
}
