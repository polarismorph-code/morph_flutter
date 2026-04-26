import 'package:flutter/material.dart';

import '../provider/morph_provider.dart';
import 'gps_context_adapter.dart';

/// Scaffold replacement that scales typography and reinforces contrast
/// when the user is moving. Drop in instead of [Scaffold] inside any
/// fintech screen that should follow the user from desk to commute.
///
/// Behavior:
///   • stationary / unknown → original theme, no banner
///   • walking → text ×1.10
///   • cycling → text ×1.20
///   • vehicle → text ×1.30, white onBackground for max read-at-a-glance
class GpsAdaptiveScaffold extends StatelessWidget {
  final Widget body;

  const GpsAdaptiveScaffold({required this.body, super.key});

  @override
  Widget build(BuildContext context) {
    final adapter = MorphInheritedWidget.maybeOf(context)?.gpsAdapter;
    final base = Theme.of(context);

    if (adapter == null) {
      return Scaffold(body: SafeArea(child: body));
    }

    return StreamBuilder<MovementContext>(
      stream: adapter.stream,
      initialData: adapter.currentContext,
      builder: (ctx, snap) {
        final movement = snap.data ?? MovementContext.stationary;
        final isMoving = movement != MovementContext.stationary &&
            movement != MovementContext.unknown;

        return AnimatedTheme(
          duration: const Duration(milliseconds: 400),
          data: _adapt(base, movement),
          child: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  if (isMoving)
                    _MovementBanner(context: movement, theme: base),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ThemeData _adapt(ThemeData theme, MovementContext movement) {
    if (movement == MovementContext.stationary ||
        movement == MovementContext.unknown) {
      return theme;
    }
    final scale = _scaleFor(movement);
    return theme.copyWith(
      textTheme: _scaleTextTheme(theme.textTheme, scale),
      colorScheme: theme.colorScheme.copyWith(
        // Boost foreground contrast when in a vehicle — maximum
        // glance-ability is the priority.
        // ignore: deprecated_member_use
        onBackground: movement == MovementContext.vehicle
            ? Colors.white
            // ignore: deprecated_member_use
            : theme.colorScheme.onBackground,
      ),
    );
  }

  double _scaleFor(MovementContext m) {
    switch (m) {
      case MovementContext.walking:
        return 1.10;
      case MovementContext.cycling:
        return 1.20;
      case MovementContext.vehicle:
        return 1.30;
      default:
        return 1.0;
    }
  }

  TextTheme _scaleTextTheme(TextTheme base, double scale) {
    if (scale == 1.0) return base;
    TextStyle? bump(TextStyle? style, double fallback) {
      if (style == null) return null;
      return style.copyWith(fontSize: (style.fontSize ?? fallback) * scale);
    }

    return base.copyWith(
      bodyLarge: bump(base.bodyLarge, 16),
      bodyMedium: bump(base.bodyMedium, 14),
      bodySmall: bump(base.bodySmall, 12),
      titleLarge: bump(base.titleLarge, 22),
      titleMedium: bump(base.titleMedium, 16),
      titleSmall: bump(base.titleSmall, 14),
      labelLarge: bump(base.labelLarge, 14),
    );
  }
}

class _MovementBanner extends StatelessWidget {
  final MovementContext context;
  final ThemeData theme;

  const _MovementBanner({required this.context, required this.theme});

  @override
  Widget build(BuildContext _) {
    final cs = theme.colorScheme;
    final label = _label(context);
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // ignore: deprecated_member_use
      color: cs.surfaceVariant,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          // ignore: deprecated_member_use
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  String _label(MovementContext m) {
    switch (m) {
      case MovementContext.walking:
        return '🚶 Walking mode';
      case MovementContext.cycling:
        return '🚲 Cycling mode';
      case MovementContext.vehicle:
        return '🚗 Vehicle mode';
      default:
        return '';
    }
  }
}
