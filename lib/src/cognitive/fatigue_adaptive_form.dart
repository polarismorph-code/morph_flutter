import 'package:flutter/material.dart';

import '../provider/morph_provider.dart';
import 'fatigue_detector.dart';

/// Form scaffold whose field set, scale, and banner adapt to the
/// detected fatigue.
///
/// **Two adaptation modes** (controlled by [adaptation]):
///
///   • [FatigueAdaptation.smooth] (default) — reads
///     [FatigueDetector.scoreStream] and interpolates the field scale
///     continuously between 1.0 (score=0) and 1.30 (score=100). The
///     simplified field set kicks in past score 70. The banner fades
///     in as the score rises past 40.
///   • [FatigueAdaptation.stepped] — reads
///     [FatigueDetector.stream] and snaps to the legacy three buckets
///     (none/medium/high). Backward compatibility default for apps
///     that prefer abrupt transitions.
///
/// The banner exposes a "Reset" affordance that calls
/// [FatigueDetector.resetFatigue] so the user can revert if the
/// heuristic misfires. All colours are pulled from
/// `Theme.of(context).colorScheme`.
class FatigueAdaptiveForm extends StatelessWidget {
  /// Full field set. Shown until the score crosses 70.
  final List<Widget> normalFields;

  /// Stripped-down set shown above score 70. Should only contain the
  /// fields strictly required to submit; the dev pre-fills the rest.
  final List<Widget> simplifiedFields;

  /// The submit CTA — rendered unmodified at every fatigue level.
  final Widget submitButton;

  /// How aggressively to react to the live signal — see class doc.
  final FatigueAdaptation adaptation;

  const FatigueAdaptiveForm({
    required this.normalFields,
    required this.simplifiedFields,
    required this.submitButton,
    this.adaptation = FatigueAdaptation.smooth,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final detector =
        MorphInheritedWidget.maybeOf(context)?.fatigueDetector;
    if (detector == null) {
      // Feature off — render the normal form with no scale change.
      return _buildLayout(context, score: 0, fields: normalFields);
    }

    if (adaptation == FatigueAdaptation.stepped) {
      return StreamBuilder<FatigueLevel>(
        stream: detector.stream,
        initialData: detector.currentLevel,
        builder: (ctx, snap) {
          final level = snap.data ?? FatigueLevel.none;
          final score = _legacyLevelToScore(level);
          final fields =
              level == FatigueLevel.high ? simplifiedFields : normalFields;
          return _buildLayout(ctx, score: score, fields: fields, detector: detector);
        },
      );
    }

    return StreamBuilder<double>(
      stream: detector.scoreStream,
      initialData: detector.currentScore,
      builder: (ctx, snap) {
        final score = (snap.data ?? 0).clamp(0.0, 100.0);
        final fields = score >= 70 ? simplifiedFields : normalFields;
        return _buildLayout(ctx, score: score, fields: fields, detector: detector);
      },
    );
  }

  Widget _buildLayout(
    BuildContext context, {
    required double score,
    required List<Widget> fields,
    FatigueDetector? detector,
  }) {
    // Smooth scale — interpolates 1.00 (score=0) → 1.30 (score=100).
    final scale = 1.0 + (score / 100) * 0.30;

    // Banner appears past score 40, opacity ramps up to fully visible
    // by score 60 — avoids a hard pop-in.
    final bannerOpacity = ((score - 40) / 20).clamp(0.0, 1.0);
    final showBanner = bannerOpacity > 0 && detector != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBanner)
          AnimatedOpacity(
            opacity: bannerOpacity,
            duration: const Duration(milliseconds: 250),
            child: _Banner(
              isHigh: score >= 70,
              onReset: () => detector.resetFatigue(),
            ),
          ),
        ...fields.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AnimatedScale(
              scale: scale,
              alignment: Alignment.topCenter,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: f,
            ),
          ),
        ),
        const SizedBox(height: 8),
        submitButton,
      ],
    );
  }

  double _legacyLevelToScore(FatigueLevel level) {
    switch (level) {
      case FatigueLevel.none:
        return 0;
      case FatigueLevel.medium:
        return 50;
      case FatigueLevel.high:
        return 80;
    }
  }
}

/// How [FatigueAdaptiveForm] reacts to the live fatigue signal.
enum FatigueAdaptation {
  /// Continuous interpolation driven by [FatigueDetector.scoreStream].
  smooth,

  /// Three-step bucket driven by the legacy [FatigueDetector.stream] —
  /// kept for apps that wired Morph against the 0.1.1 API.
  stepped,
}

class _Banner extends StatelessWidget {
  final bool isHigh;
  final VoidCallback onReset;

  const _Banner({required this.isHigh, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = isHigh
        ? '😮‍💨 Simplified view active'
        : '👁 Interface adjusted';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                // ignore: deprecated_member_use
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: cs.primary,
              minimumSize: const Size(48, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reset', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
