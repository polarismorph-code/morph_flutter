import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/endpoints.dart';
import '../license/app_identity.dart';
import '../models/morph_system_settings.dart';
import '../models/theme_model.dart';
import 'morph_raw_colors.dart';

/// Reads the current system theme + a11y preferences and, when a licenseKey
/// is present, fetches a WCAG-verified AI-generated palette from the backend.
class ThemeAdapter {
  final String licenseKey;

  ThemeAdapter({required this.licenseKey});

  /// Reads the system state — returns a fresh [MorphTheme] each call.
  ///
  /// Brightness is read from [PlatformDispatcher] directly rather than from
  /// [MediaQuery], because `didChangePlatformBrightness` fires BEFORE the
  /// MediaQuery tree propagates the new value — reading from MediaQuery at
  /// that moment would give a stale frame (observed on iOS simulator toggles).
  MorphTheme detect(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final brightness = dispatcher.platformBrightness;
    return MorphTheme(
      mode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      isHighContrast: mq.highContrast,
      // ignore: deprecated_member_use  — keeping a single API for SDK 3.10+.
      textScaleFactor: mq.textScaleFactor,
      locale: Localizations.maybeLocaleOf(context) ?? const Locale('en'),
    );
  }

  /// Convenience — returns the detected theme AND kicks off [generateTheme]
  /// in the background. The [onGenerated] callback fires when (or if) the
  /// backend responds.
  MorphTheme detectAndGenerate(
    BuildContext context,
    ThemeData baseTheme, {
    required void Function(GeneratedTheme) onGenerated,
  }) {
    final detected = detect(context);
    if (licenseKey.isEmpty) return detected;
    generateTheme(baseTheme, detected.mode).then((gen) {
      if (gen != null) onGenerated(gen);
    });
    return detected;
  }

  /// POST /api/flutter/theme/generate with the app's base colors.
  /// Returns null on any failure — callers should fall back to the existing
  /// ThemeData. The backend caches by (licenseKey, colors, adaptation) so
  /// repeated calls with the same input are cheap.
  Future<GeneratedTheme?> generateTheme(
    ThemeData originalTheme,
    ThemeMode targetMode, {
    bool highContrast = false,
    String? colorBlindMode,
  }) {
    return _postGenerate(
      colors: _extractColors(originalTheme),
      targetMode: targetMode,
      appBrightness: originalTheme.colorScheme.brightness,
      highContrast: highContrast,
      colorBlindMode: colorBlindMode,
      colorSource: null,
    );
  }

  /// Same as [generateTheme] but sources the palette from the normalized
  /// [MorphRawColors] extracted by the [ColorExtractor] — used when the
  /// dev passed `MorphColors` instead of (or on top of) a `ThemeData`.
  Future<GeneratedTheme?> generateFromRaw(
    MorphRawColors raw,
    ThemeMode targetMode, {
    bool highContrast = false,
    String? colorBlindMode,
  }) {
    return _postGenerate(
      colors: raw.toApiPayload(),
      targetMode: targetMode,
      appBrightness: raw.brightness,
      highContrast: highContrast,
      colorBlindMode: colorBlindMode,
      colorSource: raw.source.name,
    );
  }

  Future<GeneratedTheme?> _postGenerate({
    required Map<String, String> colors,
    required ThemeMode targetMode,
    required Brightness appBrightness,
    required bool highContrast,
    required String? colorBlindMode,
    required String? colorSource,
  }) async {
    if (licenseKey.isEmpty) return null;
    final platform = _platformName();
    if (platform == null) return null; // web/desktop unsupported for now

    final uri = Uri.parse('$kMorphApiBaseUrl/api/flutter/theme/generate');
    try {
      final res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'licenseKey': licenseKey,
              // Origin-binding payload — the backend rejects (403) if
              // this id doesn't match the license's allowed_packages.
              'appId': AppIdentity.cachedOrEmpty,
              'platform': platform,
              'targetAdaptation':
                  targetMode == ThemeMode.dark ? 'darken' : 'lighten',
              'appBrightness':
                  appBrightness == Brightness.dark ? 'dark' : 'light',
              'colors': colors,
              if (highContrast) 'highContrast': true,
              if (colorBlindMode != null) 'colorBlindMode': colorBlindMode,
              if (colorSource != null) 'colorSource': colorSource,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (kDebugMode) {
        debugPrint(
          '🦎 Morph → POST ${uri.path} status=${res.statusCode}',
        );
      }
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final scheme = data['colorScheme'];
      if (scheme is Map<String, dynamic>) {
        return GeneratedTheme.fromJson({
          ...scheme,
          'brightness': data['brightness'] ??
              (targetMode == ThemeMode.dark ? 'dark' : 'light'),
          'reasoning': data['reasoning'],
        });
      }
      if (data['primary'] is String) {
        return GeneratedTheme.fromJson(data);
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('🦎 Morph theme generation failed: $e');
      return null;
    }
  }

  String? _platformName() {
    if (kIsWeb) return null;
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return null;
  }

  Map<String, String> _extractColors(ThemeData theme) {
    final cs = theme.colorScheme;
    return {
      'primary': _colorToHex(cs.primary),
      // Using `surface` instead of deprecated `background` when present.
      // ignore: deprecated_member_use
      'background': _colorToHex(cs.background),
      'surface': _colorToHex(cs.surface),
      // ignore: deprecated_member_use
      'onBackground': _colorToHex(cs.onBackground),
      'secondary': _colorToHex(cs.secondary),
    };
  }

  String _colorToHex(Color c) {
    // Flutter 3.27+ deprecates Color.value — use toARGB32 when available,
    // fall back for older SDKs.
    // ignore: deprecated_member_use
    final argb = c.value;
    final hex = argb.toRadixString(16).padLeft(8, '0').substring(2);
    return '#${hex.toUpperCase()}';
  }

  // ───────────────────────────────────────────────────────────────────────
  // System settings + adapted ThemeData
  // ───────────────────────────────────────────────────────────────────────

  /// Reads the device's accessibility + appearance state into a plain value
  /// object. Called by [MorphProvider] whenever the OS reports a change.
  ///
  /// Brightness is read from [PlatformDispatcher] directly (same as [detect])
  /// rather than from [MediaQuery.platformBrightness]. When the provider sits
  /// above [MaterialApp], the MediaQuery tree may not have propagated the new
  /// brightness yet at the moment the observer fires — reading from
  /// PlatformDispatcher is always current.
  MorphSystemSettings readSettings(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MorphSystemSettings(
      brightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      highContrast: mq.highContrast,
      // ignore: deprecated_member_use  — keeping one API for SDK 3.10+.
      textScaleFactor: mq.textScaleFactor,
      boldText: mq.boldText,
      disableAnimations: mq.disableAnimations,
      invertColors: mq.invertColors,
    );
  }

  /// Produces an adapted [ThemeData] from the app's [originalTheme] and the
  /// current system [settings].
  ///
  /// The brightness flip is **symmetric**: if the OS asks for the opposite
  /// of what the dev provided, we swap to the opposite (using [generated] if
  /// it's available, else a deterministic HSL fallback). If the OS matches
  /// the base, we leave the colors alone — no "force dark".
  ///
  /// High contrast / bold text / reduced motion always layer on top.
  ThemeData buildAdaptedTheme(
    ThemeData originalTheme,
    MorphSystemSettings settings,
    GeneratedTheme? generated,
  ) {
    ThemeData theme = originalTheme;

    if (brightnessOf(originalTheme) != settings.brightness) {
      theme = _applyOpposite(theme, settings.brightness, generated);
    }
    if (settings.highContrast) {
      theme = _applyHighContrast(theme);
    }
    if (settings.boldText) {
      theme = _applyBoldText(theme);
    }
    if (settings.disableAnimations) {
      theme = _applyReducedMotion(theme);
    }
    return theme;
  }

  /// Canonical brightness of a [ThemeData]. Reads from `colorScheme`
  /// rather than the (being-phased-out) top-level `theme.brightness`.
  static Brightness brightnessOf(ThemeData theme) =>
      theme.colorScheme.brightness;

  /// Flip the theme to [target]. Uses [generated] when the backend supplied
  /// a palette, otherwise walks HSL to derive an automatic opposite.
  ThemeData _applyOpposite(
    ThemeData original,
    Brightness target,
    GeneratedTheme? generated,
  ) {
    if (generated != null) {
      final scheme = generated.toColorScheme();
      return original.copyWith(
        brightness: target,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        cardColor: scheme.surface,
        // ignore: deprecated_member_use
        dividerColor: scheme.outline.withOpacity(0.3),
        appBarTheme: original.appBarTheme.copyWith(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
        ),
      );
    }
    return _buildAutoOppositeTheme(original, target);
  }

  /// Deterministic HSL-based flip — preserves hue, shifts lightness. Used
  /// whenever no AI palette is available (offline, free tier, first paint).
  ThemeData _buildAutoOppositeTheme(ThemeData original, Brightness target) {
    final isTargetDark = target == Brightness.dark;
    final bgLightness = isTargetDark ? 0.07 : 0.98;
    final surfaceLightness = isTargetDark ? 0.12 : 0.95;
    // ignore: deprecated_member_use
    final foreground = isTargetDark
        // ignore: deprecated_member_use
        ? Colors.white.withOpacity(0.87)
        // ignore: deprecated_member_use
        : Colors.black.withOpacity(0.87);

    final newBg = _setLightness(original.scaffoldBackgroundColor, bgLightness);
    final newSurface = _setLightness(original.colorScheme.surface, surfaceLightness);

    return original.copyWith(
      brightness: target,
      scaffoldBackgroundColor: newBg,
      colorScheme: original.colorScheme.copyWith(
        brightness: target,
        // ignore: deprecated_member_use
        background: newBg,
        surface: newSurface,
        // ignore: deprecated_member_use
        onBackground: foreground,
        onSurface: foreground,
        // Keep the brand primary — hue survives the flip.
        primary: original.colorScheme.primary,
      ),
    );
  }

  ThemeData _applyHighContrast(ThemeData theme) {
    final brightness = brightnessOf(theme);
    final isDark = brightness == Brightness.dark;
    final pure = isDark ? Colors.white : Colors.black;
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final surface = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5);
    // ignore: deprecated_member_use
    final outline = (isDark ? Colors.white : Colors.black).withOpacity(0.6);

    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        // ignore: deprecated_member_use
        onBackground: pure,
        onSurface: pure,
        // ignore: deprecated_member_use
        background: bg,
        surface: surface,
        primary: _increaseContrast(theme.colorScheme.primary, brightness),
        outline: outline,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        border: const OutlineInputBorder(
          borderSide: BorderSide(width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(width: 2, color: outline),
        ),
      ),
      textTheme: _applyHighContrastText(theme.textTheme, brightness),
    );
  }

  TextTheme _applyHighContrastText(TextTheme textTheme, Brightness brightness) {
    final textColor = brightness == Brightness.dark ? Colors.white : Colors.black;
    return textTheme.copyWith(
      bodyLarge: textTheme.bodyLarge?.copyWith(color: textColor, letterSpacing: 0.3),
      bodyMedium: textTheme.bodyMedium?.copyWith(color: textColor, letterSpacing: 0.2),
      titleLarge: textTheme.titleLarge?.copyWith(color: textColor),
      titleMedium: textTheme.titleMedium?.copyWith(color: textColor),
    );
  }

  ThemeData _applyBoldText(ThemeData theme) {
    return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        titleLarge: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        titleMedium: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  ThemeData _applyReducedMotion(ThemeData theme) {
    return theme.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  Color _setLightness(Color color, double target) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(target.clamp(0.0, 1.0)).toColor();
  }

  Color _increaseContrast(Color color, Brightness brightness) {
    final hsl = HSLColor.fromColor(color);
    final delta = brightness == Brightness.dark ? 0.2 : -0.2;
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }
}
