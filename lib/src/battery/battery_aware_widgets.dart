import 'package:flutter/material.dart';

import '../behavior/behavior_db.dart';
import '../device/device_capabilities.dart';
import '../provider/morph_provider.dart';
import 'battery_adapter.dart';

/// Picks one of four widget variants depending on the active
/// [BatteryMode]. Lighter variants are used at lower levels — typically
/// fewer animated regions and skeletons instead of skeletons + heroes.
///
/// `medium` / `low` / `critical` are optional — when missing, we cascade
/// upward to [normal]. So a dev who only wants to handle critical can
/// provide just `normal` + `critical`.
class BatteryAwareWidget extends StatelessWidget {
  final Widget normal;
  final Widget? medium;
  final Widget? low;
  final Widget? critical;

  const BatteryAwareWidget({
    required this.normal,
    this.medium,
    this.low,
    this.critical,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final adapter = MorphInheritedWidget.maybeOf(context)?.batteryAdapter;
    if (adapter == null) return normal;
    return StreamBuilder<BatteryMode>(
      stream: adapter.modeStream,
      initialData: adapter.currentMode,
      builder: (ctx, snap) {
        final mode = snap.data ?? BatteryMode.normal;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: KeyedSubtree(
            key: ValueKey('cml-batt-${mode.name}'),
            child: _pick(mode),
          ),
        );
      },
    );
  }

  Widget _pick(BatteryMode mode) {
    switch (mode) {
      case BatteryMode.critical:
        return critical ?? low ?? medium ?? normal;
      case BatteryMode.low:
        return low ?? medium ?? normal;
      case BatteryMode.medium:
        return medium ?? normal;
      case BatteryMode.normal:
        return normal;
    }
  }
}

/// How aggressively [BatteryAwareTheme] applies its adaptations.
enum BatteryAdaptiveMode {
  /// Apply mode adaptations as soon as the bucket flips. Backward-
  /// compatible default for apps that wired Morph before suggestion-
  /// first mode existed.
  imposed,

  /// Wait until the user accepts the "Battery saver mode" suggestion
  /// (fired by `SuggestionEngine` at low/critical). Until accepted,
  /// the theme passes through unchanged. Once accepted, the
  /// adaptations turn on for the rest of the session AND for every
  /// future low-battery moment until the user revokes via the same
  /// suggestion path.
  suggestion,
}

/// Reactively swaps in a battery-adapted [ThemeData]. Animates the change
/// with [AnimatedTheme] so the swap is gentle.
///
/// Strategy:
///   • normal   — passes the inherited theme through unchanged
///   • medium   — softer page transitions
///   • low      — minimal transitions; on OLED screens, swap to a near-
///                black scaffold to cut display draw
///   • critical — pure black scaffold, near-black surfaces, no transitions
///                (OLED-aware: degrades to dim grey on LCD where pure
///                black saves no power)
///
/// All other widgets keep reading from `Theme.of(context)` and adopt the
/// new palette automatically.
class BatteryAwareTheme extends StatelessWidget {
  final Widget child;

  /// Whether to apply adaptations automatically ([BatteryAdaptiveMode.imposed],
  /// the default) or wait for user opt-in via the suggestion card
  /// ([BatteryAdaptiveMode.suggestion]). The latter is the more
  /// "respectful" UX — pair with `MorphFeatures(suggestionsEnabled: true)`
  /// so the suggestion card actually gets a chance to fire.
  final BatteryAdaptiveMode adaptiveMode;

  /// Override for OLED detection. Pass `true` to opt into pure-black
  /// surfaces (saves power on AMOLED), `false` to keep dim-grey
  /// degradations everywhere. When `null` (the default),
  /// [DeviceCapabilities.isLikelyOLED] picks per platform — see its docs
  /// for the heuristic.
  final bool? isOLED;

  const BatteryAwareTheme({
    required this.child,
    this.adaptiveMode = BatteryAdaptiveMode.imposed,
    this.isOLED,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final adapter = MorphInheritedWidget.maybeOf(context)?.batteryAdapter;
    final db = MorphInheritedWidget.maybeOf(context)?.db;
    final base = Theme.of(context);
    if (adapter == null) return child;

    return StreamBuilder<BatteryMode>(
      stream: adapter.modeStream,
      initialData: adapter.currentMode,
      builder: (ctx, snap) {
        final mode = snap.data ?? BatteryMode.normal;
        final accepted = _userAccepted(db);
        // Suggestion mode + not yet accepted = pass through unchanged.
        if (adaptiveMode == BatteryAdaptiveMode.suggestion && !accepted) {
          return child;
        }
        return AnimatedTheme(
          duration: const Duration(milliseconds: 500),
          data: _adapt(base, mode),
          child: child,
        );
      },
    );
  }

  bool _userAccepted(BehaviorDB? db) {
    if (db == null) return false;
    final raw = db.readPreference('battery.preference');
    return raw == 'saver_mode_accepted';
  }

  ThemeData _adapt(ThemeData theme, BatteryMode mode) {
    final oled = DeviceCapabilities.isLikelyOLED(override: isOLED);
    switch (mode) {
      case BatteryMode.normal:
        return theme;
      case BatteryMode.medium:
        return theme.copyWith(
          pageTransitionsTheme: _reducedTransitions,
        );
      case BatteryMode.low:
        return theme.copyWith(
          pageTransitionsTheme: _minimalTransitions,
          // Pure-black backdrop only worth it on OLED — on LCD the panel
          // backlight is already on, so any dark colour costs the same.
          scaffoldBackgroundColor: theme.brightness == Brightness.light && oled
              ? const Color(0xFF1A1A1A)
              : theme.scaffoldBackgroundColor,
        );
      case BatteryMode.critical:
        return theme.copyWith(
          scaffoldBackgroundColor: oled ? Colors.black : const Color(0xFF111111),
          colorScheme: theme.colorScheme.copyWith(
            // ignore: deprecated_member_use
            background: oled ? Colors.black : const Color(0xFF111111),
            surface: oled ? const Color(0xFF0A0A0A) : const Color(0xFF1A1A1A),
          ),
          pageTransitionsTheme: _minimalTransitions,
        );
    }
  }

  static const PageTransitionsTheme _reducedTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    },
  );

  static const PageTransitionsTheme _minimalTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    },
  );
}
