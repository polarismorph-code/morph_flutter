import 'package:flutter/material.dart';

import '../provider/morph_provider.dart';
import 'grip_detector.dart';

/// Wraps a screen and floats [primaryAction] over it on the side that
/// matches the user's detected grip — left edge for left-handed grip,
/// right for right, centered when both/unknown.
///
/// Falls back to [defaultAlignment] (defaults to bottomRight) when no
/// [GripDetector] is mounted (i.e. the dev didn't enable
/// `gripDetection: true` on [MorphFeatures]).
///
/// Drop-in usage on a product page:
/// ```dart
/// Scaffold(
///   body: GripAdaptiveLayout(
///     child: ProductDetails(),
///     primaryAction: AddToCartButton(),
///   ),
/// );
/// ```
class GripAdaptiveLayout extends StatelessWidget {
  /// Page content. Renders behind [primaryAction].
  final Widget child;

  /// CTA that floats over [child]. Typically an [ElevatedButton] /
  /// [FilledButton]. Sized as-given — wrap in [SizedBox] if you want to
  /// constrain it.
  final Widget primaryAction;

  /// Position used when grip detection is unavailable or returns
  /// `GripHand.unknown`.
  final Alignment defaultAlignment;

  /// How long the [primaryAction] takes to slide between sides when the
  /// detected hand changes. Default 300ms — feels responsive without
  /// being snappy. Set higher for a softer feel on longer screens.
  final Duration transitionDuration;

  /// Curve used during the transition. Default `easeOutCubic` matches
  /// Material's standard "settle" feel.
  final Curve transitionCurve;

  const GripAdaptiveLayout({
    required this.child,
    required this.primaryAction,
    this.defaultAlignment = Alignment.bottomRight,
    this.transitionDuration = const Duration(milliseconds: 300),
    this.transitionCurve = Curves.easeOutCubic,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final inherited = MorphInheritedWidget.maybeOf(context);
    final detector = inherited?.gripDetector;

    if (detector == null) {
      // Feature disabled — keep the static fallback so the dev can wrap
      // their screen unconditionally.
      return Stack(
        children: [
          child,
          Align(
            alignment: defaultAlignment,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: primaryAction,
            ),
          ),
        ],
      );
    }

    return StreamBuilder<GripHand>(
      stream: detector.handStream,
      initialData: detector.currentHand,
      builder: (ctx, snap) {
        final alignment = _alignmentFor(snap.data ?? GripHand.unknown);
        return Stack(
          children: [
            child,
            AnimatedAlign(
              alignment: alignment,
              duration: transitionDuration,
              curve: transitionCurve,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: primaryAction,
              ),
            ),
          ],
        );
      },
    );
  }

  Alignment _alignmentFor(GripHand hand) {
    switch (hand) {
      case GripHand.left:
        return Alignment.bottomLeft;
      case GripHand.right:
        return Alignment.bottomRight;
      case GripHand.both:
        return Alignment.bottomCenter;
      case GripHand.unknown:
        return defaultAlignment;
    }
  }
}
