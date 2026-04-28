import 'package:flutter/material.dart';

import '../provider/morph_provider.dart';
import 'morph_plan.dart';

/// Wraps a feature so it only renders when the resolved plan satisfies
/// [requiredPlan]. Otherwise renders [fallback], or — when [fallback] is
/// null — **nothing visible** (a `SizedBox.shrink()`).
///
/// **Why the default is silent.** The SDK ships inside YOUR customers'
/// apps. If your subscription lapses or downgrades unexpectedly, an
/// auto-rendered "Upgrade to Morph Pro" card would surface to YOUR end
/// users — people who never heard of Morph and can't act on the prompt.
/// That's an embarrassing leak from your billing relationship into
/// their UX. So we hide the gated child silently and let YOU decide
/// whether to surface anything in its place.
///
/// **Two safe usage patterns:**
///
/// 1. Silent degrade (default): the feature simply disappears when the
///    plan can't satisfy it. Use this for end-user surfaces.
/// ```dart
/// PlanGate(
///   requiredPlan: MorphPlan.business,
///   featureName: 'Analytics Dashboard',
///   child: const FullAnalyticsDashboard(),
/// )
/// ```
///
/// 2. Custom fallback: render your own placeholder when you want
///    something there — e.g. a banner pointing to YOUR pricing page,
///    not Morph's.
/// ```dart
/// PlanGate(
///   requiredPlan: MorphPlan.business,
///   featureName: 'Analytics Dashboard',
///   child: const FullAnalyticsDashboard(),
///   fallback: const YourOwnUpgradeBanner(),
/// )
/// ```
///
/// 3. Internal admin: when YOU (the SDK customer) want to see the
///    Morph-branded upsell on YOUR admin dashboard or settings page,
///    pass [MorphUpsellCard] explicitly:
/// ```dart
/// PlanGate(
///   requiredPlan: MorphPlan.business,
///   featureName: 'Analytics Dashboard',
///   child: const FullAnalyticsDashboard(),
///   fallback: MorphUpsellCard(
///     featureName: 'Analytics Dashboard',
///     requiredPlan: MorphPlan.business,
///     onUpgrade: () => launchUrl(Uri.parse(MorphPlan.upgradeUrl)),
///   ),
/// )
/// ```
class PlanGate extends StatelessWidget {
  final Widget child;
  final MorphPlan requiredPlan;
  final String featureName;

  /// Rendered when the current plan is below [requiredPlan]. **Defaults
  /// to a hidden `SizedBox.shrink()`** — the gated feature silently
  /// disappears for end users. Pass [MorphUpsellCard] to opt into the
  /// Morph-branded upsell, or your own widget for a custom message.
  final Widget? fallback;

  const PlanGate({
    required this.child,
    required this.requiredPlan,
    required this.featureName,
    this.fallback,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final inherited = MorphInheritedWidget.maybeOf(context);
    final plan = inherited?.plan ?? MorphPlan.free;
    if (_satisfies(plan)) return child;
    return fallback ?? const SizedBox.shrink();
  }

  bool _satisfies(MorphPlan plan) {
    switch (requiredPlan) {
      case MorphPlan.free:
        return true;
      case MorphPlan.professional:
        return plan.isProfessional;
      case MorphPlan.business:
        return plan.isBusiness;
      case MorphPlan.enterprise:
        return plan.isEnterprise;
    }
  }
}

/// Morph-branded upsell card — visually pitches the customer to upgrade
/// THEIR Morph subscription. **Never auto-rendered by the SDK.** Pass
/// it explicitly via [PlanGate.fallback] when YOU (the SDK customer)
/// want it shown — typically on YOUR own admin / settings / dev-tools
/// surface, NOT on end-user screens.
///
/// All colors come from `Theme.of(context).colorScheme` so the card
/// matches whatever surface it's dropped into. The default upgrade
/// affordance falls back to logging the URL — pass [onUpgrade] to wire
/// `url_launcher`, an in-app paywall, or your own billing flow.
class MorphUpsellCard extends StatelessWidget {
  final String featureName;
  final MorphPlan requiredPlan;
  final VoidCallback? onUpgrade;

  const MorphUpsellCard({
    required this.featureName,
    required this.requiredPlan,
    this.onUpgrade,
    super.key,
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

/// Morph-branded upgrade dialog — shown ONLY when YOU (the SDK
/// customer) explicitly call it via `showDialog`. **Never auto-rendered
/// by the SDK.** Use it on YOUR admin screens, billing-recovery flows,
/// or wherever an end-user-facing prompt is already part of YOUR own
/// product narrative.
///
/// ```dart
/// // Example — dev tools button on YOUR settings screen
/// showDialog(
///   context: context,
///   builder: (_) => MorphUpgradeDialog(
///     requiredPlan: MorphPlan.business,
///     onUpgrade: () => launchUrl(Uri.parse(MorphPlan.upgradeUrl)),
///   ),
/// );
/// ```
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
