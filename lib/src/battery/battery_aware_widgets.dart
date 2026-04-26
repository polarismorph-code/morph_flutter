import 'package:flutter/material.dart';

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

/// Reactively swaps in a battery-adapted [ThemeData]. Animates the change
/// with [AnimatedTheme] so the swap is gentle.
///
/// Strategy:
///   • normal   — passes the inherited theme through unchanged
///   • medium   — softer page transitions
///   • low      — minimal transitions; on light themes, swap to a near-
///                black scaffold to cut OLED draw
///   • critical — pure black scaffold, near-black surfaces, no transitions
///
/// All other widgets keep reading from `Theme.of(context)` and adopt the
/// new palette automatically.
class BatteryAwareTheme extends StatelessWidget {
  final Widget child;

  const BatteryAwareTheme({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final adapter = MorphInheritedWidget.maybeOf(context)?.batteryAdapter;
    final base = Theme.of(context);
    if (adapter == null) return child;

    return StreamBuilder<BatteryMode>(
      stream: adapter.modeStream,
      initialData: adapter.currentMode,
      builder: (ctx, snap) {
        final mode = snap.data ?? BatteryMode.normal;
        return AnimatedTheme(
          duration: const Duration(milliseconds: 500),
          data: _adapt(base, mode),
          child: child,
        );
      },
    );
  }

  ThemeData _adapt(ThemeData theme, BatteryMode mode) {
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
          scaffoldBackgroundColor: theme.brightness == Brightness.light
              ? const Color(0xFF1A1A1A)
              : theme.scaffoldBackgroundColor,
        );
      case BatteryMode.critical:
        return theme.copyWith(
          scaffoldBackgroundColor: Colors.black,
          colorScheme: theme.colorScheme.copyWith(
            // ignore: deprecated_member_use
            background: Colors.black,
            surface: const Color(0xFF0A0A0A),
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
