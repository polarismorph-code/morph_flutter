import 'package:flutter/material.dart';

/// Snapshot of the system-detected theme + accessibility state.
/// Immutable — rebuilt by [ThemeAdapter.detect] on every platform change.
@immutable
class MorphTheme {
  final ThemeMode mode;
  final bool isHighContrast;
  final double textScaleFactor;
  final Locale locale;

  /// AI-generated palette for the current [mode], if the backend replied.
  /// Null until the /flutter/theme/generate call completes (or forever
  /// without licenseKey).
  final GeneratedTheme? generated;

  const MorphTheme({
    required this.mode,
    required this.isHighContrast,
    required this.textScaleFactor,
    required this.locale,
    this.generated,
  });

  bool get isDark => mode == ThemeMode.dark;
  bool get isLight => mode == ThemeMode.light;

  MorphTheme copyWith({
    ThemeMode? mode,
    bool? isHighContrast,
    double? textScaleFactor,
    Locale? locale,
    GeneratedTheme? generated,
    bool clearGenerated = false,
  }) {
    return MorphTheme(
      mode: mode ?? this.mode,
      isHighContrast: isHighContrast ?? this.isHighContrast,
      textScaleFactor: textScaleFactor ?? this.textScaleFactor,
      locale: locale ?? this.locale,
      generated: clearGenerated ? null : (generated ?? this.generated),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphTheme &&
          mode == other.mode &&
          isHighContrast == other.isHighContrast &&
          textScaleFactor == other.textScaleFactor &&
          locale == other.locale &&
          generated == other.generated;

  @override
  int get hashCode =>
      Object.hash(mode, isHighContrast, textScaleFactor, locale, generated);
}

/// Full Material3 ColorScheme returned by `/api/flutter/theme/generate`.
/// All slots are stored as hex strings (`#RRGGBB`) to stay JSON-serializable;
/// use [toColorScheme] to convert to Flutter's ColorScheme.
@immutable
class GeneratedTheme {
  final String primary;
  final String onPrimary;
  final String primaryContainer;
  final String onPrimaryContainer;
  final String secondary;
  final String onSecondary;
  final String secondaryContainer;
  final String onSecondaryContainer;
  final String background;
  final String onBackground;
  final String surface;
  final String onSurface;
  final String surfaceVariant;
  final String onSurfaceVariant;
  final String error;
  final String onError;
  final String outline;
  final String shadow;

  /// 'dark' | 'light' — the brightness the generator was asked to produce.
  final String brightness;
  final String reasoning;

  // Custom semantic colors — sent by the backend when the prompt includes them.
  // Null when the backend response omits the field (older prompts / free tier).
  final String? success;
  final String? warning;

  const GeneratedTheme({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.background,
    required this.onBackground,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.error,
    required this.onError,
    required this.outline,
    required this.shadow,
    required this.brightness,
    required this.reasoning,
    this.success,
    this.warning,
  });

  /// Permissive parser — missing slots fall back to MD3 defaults so a
  /// partial Claude response still yields a usable theme.
  factory GeneratedTheme.fromJson(Map<String, dynamic> json) {
    String pick(String key, String fallback) {
      final v = json[key];
      return (v is String && v.startsWith('#')) ? v : fallback;
    }

    final isDark = (json['brightness'] as String?) == 'dark';
    final defaults = isDark ? _md3Dark : _md3Light;

    return GeneratedTheme(
      primary: pick('primary', defaults['primary']!),
      onPrimary: pick('onPrimary', defaults['onPrimary']!),
      primaryContainer: pick('primaryContainer', defaults['primaryContainer']!),
      onPrimaryContainer: pick('onPrimaryContainer', defaults['onPrimaryContainer']!),
      secondary: pick('secondary', defaults['secondary']!),
      onSecondary: pick('onSecondary', defaults['onSecondary']!),
      secondaryContainer: pick('secondaryContainer', defaults['secondaryContainer']!),
      onSecondaryContainer: pick('onSecondaryContainer', defaults['onSecondaryContainer']!),
      background: pick('background', defaults['background']!),
      onBackground: pick('onBackground', defaults['onBackground']!),
      surface: pick('surface', defaults['surface']!),
      onSurface: pick('onSurface', defaults['onSurface']!),
      surfaceVariant: pick('surfaceVariant', defaults['surfaceVariant']!),
      onSurfaceVariant: pick('onSurfaceVariant', defaults['onSurfaceVariant']!),
      error: pick('error', defaults['error']!),
      onError: pick('onError', defaults['onError']!),
      outline: pick('outline', defaults['outline']!),
      shadow: pick('shadow', '#000000'),
      brightness: isDark ? 'dark' : 'light',
      reasoning: (json['reasoning'] as String?) ?? '',
      success: json['success'] is String &&
              (json['success'] as String).startsWith('#')
          ? json['success'] as String
          : null,
      warning: json['warning'] is String &&
              (json['warning'] as String).startsWith('#')
          ? json['warning'] as String
          : null,
    );
  }

  /// Convert to a Flutter [ColorScheme] ready to be used in
  /// `ThemeData.colorScheme` or `ThemeData(colorScheme: ...)`.
  ColorScheme toColorScheme() {
    final isDark = brightness == 'dark';
    return ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: _hex(primary),
      onPrimary: _hex(onPrimary),
      primaryContainer: _hex(primaryContainer),
      onPrimaryContainer: _hex(onPrimaryContainer),
      secondary: _hex(secondary),
      onSecondary: _hex(onSecondary),
      secondaryContainer: _hex(secondaryContainer),
      onSecondaryContainer: _hex(onSecondaryContainer),
      // `background`/`onBackground` are deprecated since Flutter 3.18 but
      // ColorScheme's constructor still accepts them for compatibility.
      // ignore: deprecated_member_use
      background: _hex(background),
      // ignore: deprecated_member_use
      onBackground: _hex(onBackground),
      surface: _hex(surface),
      onSurface: _hex(onSurface),
      // ignore: deprecated_member_use
      surfaceVariant: _hex(surfaceVariant),
      onSurfaceVariant: _hex(onSurfaceVariant),
      error: _hex(error),
      onError: _hex(onError),
      outline: _hex(outline),
      shadow: _hex(shadow),
    );
  }

  static Color _hex(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedTheme &&
          primary == other.primary &&
          background == other.background &&
          surface == other.surface &&
          brightness == other.brightness;

  @override
  int get hashCode => Object.hash(primary, background, surface, brightness);
}

// Material3 default palettes — used as fallback when the backend response
// is missing a slot. Values match Flutter's ColorScheme.fromSeed(Colors.indigo).
const Map<String, String> _md3Light = {
  'primary': '#4F46E5',
  'onPrimary': '#FFFFFF',
  'primaryContainer': '#E0E7FF',
  'onPrimaryContainer': '#1E1B4B',
  'secondary': '#7C3AED',
  'onSecondary': '#FFFFFF',
  'secondaryContainer': '#EDE9FE',
  'onSecondaryContainer': '#2E1065',
  'background': '#FFFFFF',
  'onBackground': '#0F172A',
  'surface': '#F8FAFC',
  'onSurface': '#0F172A',
  'surfaceVariant': '#E2E8F0',
  'onSurfaceVariant': '#475569',
  'error': '#DC2626',
  'onError': '#FFFFFF',
  'outline': '#94A3B8',
};

const Map<String, String> _md3Dark = {
  'primary': '#818CF8',
  'onPrimary': '#1E1B4B',
  'primaryContainer': '#3730A3',
  'onPrimaryContainer': '#E0E7FF',
  'secondary': '#A78BFA',
  'onSecondary': '#2E1065',
  'secondaryContainer': '#5B21B6',
  'onSecondaryContainer': '#EDE9FE',
  'background': '#0F172A',
  'onBackground': '#F8FAFC',
  'surface': '#1E293B',
  'onSurface': '#F8FAFC',
  'surfaceVariant': '#334155',
  'onSurfaceVariant': '#CBD5E1',
  'error': '#F87171',
  'onError': '#450A0A',
  'outline': '#64748B',
};
