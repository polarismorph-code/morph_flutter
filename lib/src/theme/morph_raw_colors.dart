import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Where did the colors end up coming from — used only for debug + for the
/// backend to know how confident we are in each slot.
enum ColorSource {
  /// Everything came from `Theme.of(context)` / the dev's `baseTheme:`.
  themeData,

  /// Dev passed a fully populated `MorphColors`; ThemeData was irrelevant.
  declared,

  /// Dev passed `MorphColors` but some slots still came from ThemeData.
  mixed,
}

/// Normalized internal palette. Always non-null fields — every slot has a
/// value, whether from the dev, the theme or a default. Never exposed to
/// user code directly; the provider converts it into a ThemeData or sends
/// it to the backend.
@immutable
class MorphRawColors {
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color text;
  final Color textSecondary;
  final Color error;
  final Color outline;
  final Color success;
  final Color warning;
  final ColorSource source;

  const MorphRawColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.text,
    required this.textSecondary,
    required this.error,
    required this.outline,
    required this.success,
    required this.warning,
    required this.source,
  });

  /// JSON-safe map sent to `/api/flutter/theme/generate` — the backend
  /// accepts unknown keys and ignores them, so sending the richer set is
  /// forward-compatible.
  Map<String, String> toApiPayload() => {
        'background': _toHex(background),
        'surface': _toHex(surface),
        'surfaceVariant': _toHex(surfaceVariant),
        'primary': _toHex(primary),
        'onPrimary': _toHex(onPrimary),
        'secondary': _toHex(secondary),
        'text': _toHex(text),
        'textSecondary': _toHex(textSecondary),
        'error': _toHex(error),
        'outline': _toHex(outline),
        'success': _toHex(success),
        'warning': _toHex(warning),
      };

  /// Perceived brightness of the palette — derived from the WCAG relative
  /// luminance of [background]. This is what `ThemeGenerator` compares
  /// against the OS brightness to decide whether a flip is needed.
  Brightness get brightness =>
      _relativeLuminance(background) > 0.5 ? Brightness.light : Brightness.dark;

  /// Build a ThemeData from these raw colors. Used when the dev only passed
  /// [MorphColors] (no `baseTheme:`) — we still need a ThemeData to feed
  /// the existing adapter pipeline.
  ThemeData toThemeData() {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        secondary: secondary,
        onSecondary: onPrimary,
        // ignore: deprecated_member_use
        background: background,
        // ignore: deprecated_member_use
        onBackground: text,
        surface: surface,
        onSurface: text,
        // ignore: deprecated_member_use
        surfaceVariant: surfaceVariant,
        onSurfaceVariant: textSecondary,
        error: error,
        onError: onPrimary,
        outline: outline,
      ),
      cardColor: surface,
    );
  }

  static double _relativeLuminance(Color c) {
    // Color.red / .green / .blue are still the simplest path that works on
    // SDK 3.10 through 3.27+.
    // ignore: deprecated_member_use
    final r = c.red / 255.0;
    // ignore: deprecated_member_use
    final g = c.green / 255.0;
    // ignore: deprecated_member_use
    final b = c.blue / 255.0;
    return 0.2126 * _linearize(r) +
        0.7152 * _linearize(g) +
        0.0722 * _linearize(b);
  }

  static double _linearize(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static String _toHex(Color c) {
    // ignore: deprecated_member_use
    final argb = c.value;
    final hex = argb.toRadixString(16).padLeft(8, '0').substring(2);
    return '#${hex.toUpperCase()}';
  }
}
