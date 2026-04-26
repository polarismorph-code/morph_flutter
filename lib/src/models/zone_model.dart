import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'morph_system_settings.dart';
import 'theme_model.dart';
import '../analytics/morph_analytics_config.dart';
import '../theme/morph_adapted_colors.dart';

/// Coarse semantic type of a zone — used by the scorer to decide how to
/// interpret interactions (a click on a video zone ≠ a click on a button).
enum MorphZoneType {
  section,
  navigation,
  card,
  video,
  carousel,
  text,
}

/// Configuration passed to [MorphProvider]. All fields optional.
@immutable
class MorphConfig {
  /// How often the scorer runs. Default 5 minutes (matches the web SDK).
  final Duration analysisInterval;

  /// Minimum total interactions before the scorer will propose a reorder.
  /// Matches the web SDK's threshold.
  final int minInteractions;

  /// Minimum number of zoom events before font-scale is activated.
  final int minZoomsForFontScale;

  const MorphConfig({
    this.analysisInterval = const Duration(minutes: 5),
    this.minInteractions = 20,
    this.minZoomsForFontScale = 3,
  });
}

/// The piece of state exposed to descendants via [MorphInheritedWidget].
/// Everything in here is derived from the system or from the scorer — never
/// from user app state.
@immutable
class MorphState {
  final MorphTheme theme;
  final String sessionId;
  final bool safeMode;

  /// `Map<zoneId, orderIndex>`. Empty before the scorer has run or when the
  /// scorer decides no reorder is warranted.
  final Map<String, int> zoneOrder;

  /// True once the font-scale threshold has been crossed.
  final bool fontScaleApplied;

  /// True once at least one successful scoring pass has completed.
  final bool v2Enabled;

  /// Raw OS-reported accessibility + appearance state. Updated on every
  /// platform-brightness or accessibility change.
  final MorphSystemSettings systemSettings;

  /// [ThemeData] derived from the app's original theme + [systemSettings].
  /// Null until the first frame — consumers should fall back to their own
  /// theme when reading on the very first build.
  final ThemeData? adaptedTheme;

  /// Flat semantic color palette extracted from [adaptedTheme]. Null when no
  /// adaptation is needed (system brightness matches the base). Widgets read
  /// this via [BuildContext.morphPalette] and fall back to their own base
  /// AppColors values when null.
  final MorphAdaptedColors? adaptedColors;

  /// Snapshot of the analytics config the dev passed to [MorphProvider].
  /// Null when analytics is disabled (the default — privacy by default).
  /// Read via the analytics extensions
  /// (`context.morphAnalyticsEnabled`, `context.morphUserConsented`).
  final MorphAnalyticsConfig? analyticsConfig;

  const MorphState({
    required this.theme,
    required this.sessionId,
    this.safeMode = false,
    this.zoneOrder = const {},
    this.fontScaleApplied = false,
    this.v2Enabled = false,
    this.systemSettings = const MorphSystemSettings(),
    this.adaptedTheme,
    this.adaptedColors,
    this.analyticsConfig,
  });

  factory MorphState.safe(MorphTheme theme) => MorphState(
        theme: theme,
        sessionId: '',
        safeMode: true,
      );

  MorphState copyWith({
    MorphTheme? theme,
    String? sessionId,
    bool? safeMode,
    Map<String, int>? zoneOrder,
    bool? fontScaleApplied,
    bool? v2Enabled,
    MorphSystemSettings? systemSettings,
    ThemeData? adaptedTheme,
    bool clearAdaptedTheme = false,
    MorphAdaptedColors? adaptedColors,
    bool clearAdaptedColors = false,
    MorphAnalyticsConfig? analyticsConfig,
    bool clearAnalyticsConfig = false,
  }) {
    return MorphState(
      theme: theme ?? this.theme,
      sessionId: sessionId ?? this.sessionId,
      safeMode: safeMode ?? this.safeMode,
      zoneOrder: zoneOrder ?? this.zoneOrder,
      fontScaleApplied: fontScaleApplied ?? this.fontScaleApplied,
      v2Enabled: v2Enabled ?? this.v2Enabled,
      systemSettings: systemSettings ?? this.systemSettings,
      adaptedTheme:
          clearAdaptedTheme ? null : (adaptedTheme ?? this.adaptedTheme),
      adaptedColors:
          clearAdaptedColors ? null : (adaptedColors ?? this.adaptedColors),
      analyticsConfig: clearAnalyticsConfig
          ? null
          : (analyticsConfig ?? this.analyticsConfig),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphState &&
          theme == other.theme &&
          sessionId == other.sessionId &&
          safeMode == other.safeMode &&
          mapEquals(zoneOrder, other.zoneOrder) &&
          fontScaleApplied == other.fontScaleApplied &&
          v2Enabled == other.v2Enabled &&
          systemSettings == other.systemSettings &&
          adaptedTheme == other.adaptedTheme &&
          adaptedColors == other.adaptedColors &&
          analyticsConfig == other.analyticsConfig;

  @override
  int get hashCode => Object.hash(
        theme,
        sessionId,
        safeMode,
        Object.hashAll(zoneOrder.entries.map((e) => Object.hash(e.key, e.value))),
        fontScaleApplied,
        v2Enabled,
        systemSettings,
        adaptedTheme,
        adaptedColors,
        analyticsConfig,
      );
}
