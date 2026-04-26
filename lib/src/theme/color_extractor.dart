import 'package:flutter/material.dart';

import 'morph_colors.dart';
import 'morph_raw_colors.dart';
import 'morph_theme_extension.dart';

/// Resolves the 3 sourcing cases:
/// - **CAS 1** dev passes nothing → read everything from [ThemeData].
/// - **CAS 2** dev passes [MorphColors] only → fill from declaration,
///   ThemeData fills the gaps (usually defaults since there's no theme).
/// - **CAS 3** dev passes both → declaration wins per-slot, ThemeData fills
///   the gaps.
///
/// Always returns a [MorphRawColors] with every slot populated — the
/// rest of the pipeline never has to null-check.
class ColorExtractor {
  ColorExtractor._();

  /// [baseTheme] is the dev's own ThemeData. Callers typically pass either
  /// `widget.baseTheme` (provider outside `MaterialApp`) or
  /// `Theme.of(context)` (provider inside `MaterialApp`). When both are
  /// unavailable, Flutter's default `ThemeData()` is used as a last resort.
  static MorphRawColors extract({
    required BuildContext context,
    MorphColors? declaredColors,
    ThemeData? baseTheme,
  }) {
    final theme = baseTheme ?? Theme.of(context);
    final fromTheme = _fromThemeData(theme);

    if (declaredColors == null || declaredColors.isEmpty) {
      // CAS 1
      return fromTheme;
    }
    // CAS 2 / CAS 3 — merge, declaration wins per-slot.
    return _merge(declaredColors, fromTheme);
  }

  // ── Read from ThemeData ───────────────────────────────────────────────
  static MorphRawColors _fromThemeData(ThemeData theme) {
    final cs = theme.colorScheme;
    final defaults = ThemeData();
    final devOverrodeScaffold =
        theme.scaffoldBackgroundColor != defaults.scaffoldBackgroundColor;
    final ext = theme.extension<MorphThemeExtension>();

    return MorphRawColors(
      background: devOverrodeScaffold
          ? theme.scaffoldBackgroundColor
          // ignore: deprecated_member_use
          : cs.background,
      surface: cs.surface,
      // ignore: deprecated_member_use
      surfaceVariant: ext?.surfaceSecondary ?? cs.surfaceVariant,
      primary: cs.primary,
      onPrimary: ext?.textInverted ?? cs.onPrimary,
      secondary: cs.secondary,
      // ignore: deprecated_member_use
      text: cs.onBackground,
      textSecondary: cs.onSurfaceVariant,
      error: cs.error,
      outline: cs.outline,
      success: ext?.success ?? const Color(0xFF17B26A),
      warning: ext?.warning ?? const Color(0xFFF79009),
      source: ColorSource.themeData,
    );
  }

  // ── Merge declared + ThemeData — declaration wins per-slot ────────────
  static MorphRawColors _merge(
    MorphColors declared,
    MorphRawColors fromTheme,
  ) {
    // Count which "anchor" slots actually came from the declaration to
    // decide between `declared` (all declared) and `mixed` (partial).
    var declaredCount = 0;
    var themeCount = 0;
    Color pick(Color? from, Color fallback) {
      if (from != null) {
        declaredCount++;
        return from;
      }
      themeCount++;
      return fallback;
    }

    final merged = MorphRawColors(
      background: pick(declared.background, fromTheme.background),
      surface: pick(declared.surface, fromTheme.surface),
      surfaceVariant:
          pick(declared.surfaceSecondary, fromTheme.surfaceVariant),
      primary: pick(declared.primary, fromTheme.primary),
      onPrimary: pick(declared.textInverted, fromTheme.onPrimary),
      secondary: pick(declared.secondary, fromTheme.secondary),
      text: pick(declared.text, fromTheme.text),
      textSecondary: pick(declared.textSecondary, fromTheme.textSecondary),
      error: pick(declared.error, fromTheme.error),
      outline: pick(declared.border, fromTheme.outline),
      success: pick(declared.success, fromTheme.success),
      warning: pick(declared.warning, fromTheme.warning),
      // source is overwritten just below with the final decision.
      source: ColorSource.mixed,
    );

    final source = themeCount == 0
        ? ColorSource.declared
        : (declaredCount == 0 ? ColorSource.themeData : ColorSource.mixed);

    return MorphRawColors(
      background: merged.background,
      surface: merged.surface,
      surfaceVariant: merged.surfaceVariant,
      primary: merged.primary,
      onPrimary: merged.onPrimary,
      secondary: merged.secondary,
      text: merged.text,
      textSecondary: merged.textSecondary,
      error: merged.error,
      outline: merged.outline,
      success: merged.success,
      warning: merged.warning,
      source: source,
    );
  }
}
