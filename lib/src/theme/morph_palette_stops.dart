import 'package:flutter/material.dart';

import '../morph_extensions.dart';

/// A 12-stop color scale (s25 → s950) that can flip to its mirror in dark
/// mode. Designed to let apps with a tiered palette (like the Untitled UI
/// scale used here) keep semantic access to every stop while letting
/// Morph follow system brightness.
///
/// The mirror rule: `s25 ↔ s950`, `s50 ↔ s900`, `s100 ↔ s800`, `s200 ↔ s700`,
/// `s300 ↔ s600`, `s400 ↔ s500`. Backgrounds asked for at s25 in light mode
/// come back as s950-equivalent in dark mode — visually "the lightest end of
/// the scale" in both cases.
///
/// Typical wiring in an app:
/// ```dart
/// class AppColorsNeutral {
///   static const Color s25 = Color(0xFFFFFFFF);
///   static const Color s50 = Color(0xFFF5F7FA);
///   // ... all 12 stops as const ...
///
///   static const _stops = MorphPaletteStops(
///     s25: s25, s50: s50, s100: s100, s200: s200,
///     s300: s300, s400: s400, s500: s500, s600: s600,
///     s700: s700, s800: s800, s900: s900, s950: s950,
///   );
///
///   /// Adaptive accessor — `AppColorsNeutral.of(ctx).s25` picks the stop
///   /// that matches the current brightness.
///   static MorphPaletteStops of(BuildContext ctx) => _stops.adapt(ctx);
/// }
///
/// // In a widget:
/// color: AppColorsNeutral.of(context).s50
/// ```
@immutable
class MorphPaletteStops {
  final Color s25;
  final Color s50;
  final Color s100;
  final Color s200;
  final Color s300;
  final Color s400;
  final Color s500;
  final Color s600;
  final Color s700;
  final Color s800;
  final Color s900;
  final Color s950;

  const MorphPaletteStops({
    required this.s25,
    required this.s50,
    required this.s100,
    required this.s200,
    required this.s300,
    required this.s400,
    required this.s500,
    required this.s600,
    required this.s700,
    required this.s800,
    required this.s900,
    required this.s950,
  });

  /// Returns [this] in light mode, the mirrored version in dark mode.
  /// Safe to call before Morph is ready — defaults to light.
  MorphPaletteStops adapt(BuildContext ctx) {
    final isDark = ctx.morphPalette?.isDark ?? false;
    return isDark ? mirrored : this;
  }

  /// Cross-scale inversion — [s25] becomes [s950], [s50] becomes [s900], etc.
  /// Handy for dark-mode palettes where each position keeps its semantic
  /// meaning (background-like, text-like) while hue lightness flips.
  MorphPaletteStops get mirrored => MorphPaletteStops(
        s25: s950,
        s50: s900,
        s100: s800,
        s200: s700,
        s300: s600,
        s400: s500,
        s500: s400,
        s600: s300,
        s700: s200,
        s800: s100,
        s900: s50,
        s950: s25,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphPaletteStops &&
          s25 == other.s25 &&
          s500 == other.s500 &&
          s950 == other.s950;

  @override
  int get hashCode => Object.hash(s25, s500, s950);
}
