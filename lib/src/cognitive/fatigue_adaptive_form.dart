import 'package:flutter/material.dart';

import '../provider/morph_provider.dart';
import 'fatigue_detector.dart';

/// Form scaffold that swaps its field set and zoom level based on the
/// detected [FatigueLevel].
///
///   • none   — full [normalFields] at scale 1.0
///   • medium — full [normalFields] at scale 1.15 + discreet banner
///   • high   — only [simplifiedFields] at scale 1.30 + banner
///
/// The banner exposes a "Reset" affordance that calls
/// [FatigueDetector.resetFatigue] so the user can revert if the heuristic
/// misfires. All colors are pulled from `Theme.of(context).colorScheme`.
class FatigueAdaptiveForm extends StatelessWidget {
  /// Full field set. Shown at none/medium fatigue.
  final List<Widget> normalFields;

  /// Stripped-down set shown at high fatigue. Should only contain the
  /// fields strictly required to submit; the dev pre-fills the rest.
  final List<Widget> simplifiedFields;

  /// The submit CTA — rendered unmodified at every fatigue level.
  final Widget submitButton;

  const FatigueAdaptiveForm({
    required this.normalFields,
    required this.simplifiedFields,
    required this.submitButton,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final detector =
        MorphInheritedWidget.maybeOf(context)?.fatigueDetector;
    if (detector == null) {
      // Feature off — render the normal form with no scale change.
      return _buildLayout(context, FatigueLevel.none, normalFields);
    }

    return StreamBuilder<FatigueLevel>(
      stream: detector.stream,
      initialData: detector.currentLevel,
      builder: (ctx, snap) {
        final level = snap.data ?? FatigueLevel.none;
        final fields =
            level == FatigueLevel.high ? simplifiedFields : normalFields;
        return _buildLayout(ctx, level, fields, detector: detector);
      },
    );
  }

  Widget _buildLayout(
    BuildContext context,
    FatigueLevel level,
    List<Widget> fields, {
    FatigueDetector? detector,
  }) {
    final scale = _scaleFor(level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (level != FatigueLevel.none && detector != null)
          _Banner(level: level, onReset: detector.resetFatigue),
        ...fields.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: f,
            ),
          ),
        ),
        const SizedBox(height: 8),
        submitButton,
      ],
    );
  }

  double _scaleFor(FatigueLevel level) {
    switch (level) {
      case FatigueLevel.none:
        return 1.0;
      case FatigueLevel.medium:
        return 1.15;
      case FatigueLevel.high:
        return 1.30;
    }
  }
}

class _Banner extends StatelessWidget {
  final FatigueLevel level;
  final VoidCallback onReset;

  const _Banner({required this.level, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = level == FatigueLevel.high
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
