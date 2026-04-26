import 'package:flutter/material.dart';

import '../models/theme_model.dart';
import 'morph_raw_colors.dart';
import 'theme_adapter.dart';

/// Orchestrates the "generate the opposite of what the dev gave us" flow.
///
/// The contract: the dev provides ONE [ThemeData]. We inspect its brightness.
/// When the OS asks for the opposite, we fetch an AI palette tuned for that
/// opposite brightness. When the OS matches the base, we do nothing — no
/// wasted network call, no forced dark.
class ThemeGenerator {
  final ThemeAdapter adapter;

  ThemeGenerator(this.adapter);

  /// Brightness encoded in the theme's colorScheme — the canonical source,
  /// ahead of the phasing-out top-level `ThemeData.brightness`.
  static Brightness brightnessOf(ThemeData theme) =>
      theme.colorScheme.brightness;

  static Brightness opposite(Brightness b) =>
      b == Brightness.dark ? Brightness.light : Brightness.dark;

  /// True iff [systemBrightness] differs from the base's own brightness.
  /// False means the dev's theme already matches the OS — skip generation.
  static bool needsOpposite(ThemeData base, Brightness systemBrightness) =>
      brightnessOf(base) != systemBrightness;

  /// Fetch an AI palette targeting the opposite of [base]. Returns null when:
  /// - the OS brightness already matches the base (no flip needed),
  /// - the licenseKey is empty or the network call fails.
  ///
  /// The caller should keep the current [GeneratedTheme] on null — it may
  /// still be valid if the user just toggled back to the matching mode.
  Future<GeneratedTheme?> generateOpposite(
    ThemeData base,
    Brightness systemBrightness, {
    bool highContrast = false,
    String? colorBlindMode,
  }) async {
    if (!needsOpposite(base, systemBrightness)) return null;
    // targetMode here is really "the brightness we're flipping TO" — the
    // adapter/backend only looks at whether to lighten or darken relative
    // to the base's colors, so mode ↔ brightness is a faithful mapping.
    final targetMode = systemBrightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    return adapter.generateTheme(
      base,
      targetMode,
      highContrast: highContrast,
      colorBlindMode: colorBlindMode,
    );
  }

  /// Opposite-generation path that uses the richer [MorphRawColors]
  /// payload (from [ColorExtractor]) — this is the preferred path when the
  /// dev declared [MorphColors], because the backend gets more signal
  /// (success, warning, outline, textSecondary, …) than just a ThemeData.
  Future<GeneratedTheme?> generateOppositeFromRaw(
    MorphRawColors raw,
    Brightness systemBrightness, {
    bool highContrast = false,
    String? colorBlindMode,
  }) async {
    if (raw.brightness == systemBrightness) return null;
    final targetMode = systemBrightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    return adapter.generateFromRaw(
      raw,
      targetMode,
      highContrast: highContrast,
      colorBlindMode: colorBlindMode,
    );
  }
}
