import 'package:flutter/material.dart';

import '../provider/morph_provider.dart';
import 'morph_plan.dart';

/// Wraps a feature so it only renders when the resolved plan satisfies
/// [requiredPlan]. Otherwise renders [fallback], or — when [fallback] is
/// null — a themed "Available on X plan" upsell card.
///
/// All colors come from `Theme.of(context).colorScheme` so the gate
/// matches whatever surface it's dropped into. The default upgrade
/// affordance falls back to logging the URL — pass [onUpgrade] to wire
/// `url_launcher`, an in-app paywall, or your own billing flow.
///
/// ```dart
/// PlanGate(
///   requiredPlan: MorphPlan.agency,
///   featureName: 'Analytics Dashboard',
///   child: FullAnalyticsDashboard(),
///   fallback: UpgradePromoBanner(),  // optional
/// );
/// ```
class PlanGate extends StatelessWidget {
  final Widget child;
  final MorphPlan requiredPlan;
  final String featureName;

  /// Rendered when the current plan is below [requiredPlan]. Pass null
  /// to use the built-in upsell card.
  final Widget? fallback;

  /// Tapped on the default upgrade button. Pass `null` and the SDK logs
  /// the upgrade URL in debug builds.
  final VoidCallback? onUpgrade;

  const PlanGate({
    required this.child,
    required this.requiredPlan,
    required this.featureName,
    this.fallback,
    this.onUpgrade,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final inherited = MorphInheritedWidget.maybeOf(context);
    final plan = inherited?.plan ?? MorphPlan.free;
    if (_satisfies(plan)) return child;
    return fallback ??
        _UpgradeCard(
          featureName: featureName,
          requiredPlan: requiredPlan,
          onUpgrade: onUpgrade,
        );
  }

  bool _satisfies(MorphPlan plan) {
    switch (requiredPlan) {
      case MorphPlan.free:
        return true;
      case MorphPlan.pro:
        return plan.isPro;
      case MorphPlan.agency:
        return plan.isAgency;
    }
  }
}

class _UpgradeCard extends StatelessWidget {
  final String featureName;
  final MorphPlan requiredPlan;
  final VoidCallback? onUpgrade;

  const _UpgradeCard({
    required this.featureName,
    required this.requiredPlan,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // ignore: deprecated_member_use
          color: cs.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '🔒 $featureName',
            style: theme.textTheme.titleSmall?.copyWith(
              // ignore: deprecated_member_use
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Available on ${requiredPlan.label} plan (${requiredPlan.price})',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              // ignore: deprecated_member_use
              color: cs.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onUpgrade ?? () => _logUpgrade(),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              side: BorderSide(
                // ignore: deprecated_member_use
                color: cs.primary.withOpacity(0.5),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
            ),
            child: const Text('Upgrade', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _logUpgrade() {
    // Default fallback when the dev didn't wire an upgrade handler. We
    // avoid pulling url_launcher into the SDK — devs route this however
    // they want (in-app paywall, browser, RevenueCat, …).
    debugPrint(
      '🦎 Morph: open ${MorphPlan.upgradeUrl} to upgrade '
      'to ${requiredPlan.label}',
    );
  }
}

/// Internal upgrade dialog used by `requireMorphPro` /
/// `requireMorphAgency`. Same theming + same default fallback as
/// [_UpgradeCard].
class MorphUpgradeDialog extends StatelessWidget {
  final MorphPlan requiredPlan;
  final VoidCallback? onUpgrade;

  const MorphUpgradeDialog({
    required this.requiredPlan,
    this.onUpgrade,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Upgrade to ${requiredPlan.label}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        'This feature requires the ${requiredPlan.label} plan '
        '(${requiredPlan.price}).\n\nUpgrade to unlock all features.',
        style: theme.textTheme.bodyMedium?.copyWith(
          // ignore: deprecated_member_use
          color: cs.onSurfaceVariant,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            // ignore: deprecated_member_use
            foregroundColor: cs.onSurfaceVariant,
          ),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            if (onUpgrade != null) {
              onUpgrade!();
            } else {
              debugPrint(
                '🦎 Morph: open ${MorphPlan.upgradeUrl} to upgrade',
              );
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ),
          child: const Text('Upgrade'),
        ),
      ],
    );
  }
}
