import 'package:flutter/foundation.dart';

import 'morph_plan.dart';

/// What a given [MorphPlan] is **allowed** to do. The runtime gate is
/// always `wants AND allows`:
///   • `wants` = the dev's opt-in via `MorphFeatures` on the provider
///   • `allows` = an instance of this class derived from the resolved plan
///
/// The dev never instantiates this directly — it lands on
/// `BuildContext.morphPlanFeatures` once the validator has resolved
/// the plan. PlanGate / requireMorphPro use it to gate UI access.
///
/// **Naming note**: this class is `MorphPlanFeatures` (not
/// `MorphFeatures`) because the latter is already the dev-facing
/// opt-in flag bag from the commercial-features module. Keeping them
/// distinct means callers can pattern-match `wants && allows` without
/// type collisions.
@immutable
class MorphPlanFeatures {
  final MorphPlan plan;

  const MorphPlanFeatures({required this.plan});

  // ─── FREE — always available ─────────────────────────────────────────────

  bool get darkModeAuto => true;
  bool get systemPreferences => true;
  bool get themeGeneration => true;

  /// Scroll position only — no checkout/transfer/KYC contexts.
  bool get interruptionRecoveryBasic => true;

  // ─── PRO ────────────────────────────────────────────────────────────────

  /// Rich context-aware recovery (cart, transfer, KYC step, …).
  bool get interruptionRecoveryAdvanced => plan.isPro;

  bool get gripDetection => plan.isPro;
  bool get circadianRhythm => plan.isPro;

  /// The behavioral suggestion engine itself + its 3 base checks
  /// (navigation shortcut, zone promotion, dark mode auto).
  bool get behavioralSuggestions => plan.isPro;

  bool get navigationTracking => plan.isPro;
  bool get behavioralAnalyticsLocal => plan.isPro;
  bool get batteryAwareUI => plan.isPro;

  // ─── AGENCY ─────────────────────────────────────────────────────────────

  bool get fatigueCognitiveDetection => plan.isAgency;
  bool get gpsContextUI => plan.isAgency;
  bool get analyticsDashboard => plan.isAgency;
  bool get claudeInsights => plan.isAgency;
  bool get industryPresets => plan.isAgency;

  // ─── Helpers ────────────────────────────────────────────────────────────

  /// Returns `condition` and, when blocked in debug builds, prints a
  /// pointer to the upgrade URL. Used internally by the `check…`
  /// shortcuts below. Production builds never log (the assert closure is
  /// stripped).
  bool check(
    String featureName,
    bool condition,
    MorphPlan requiredPlan,
  ) {
    if (condition) return true;
    assert(() {
      debugPrint(
        '🦎 Morph: "$featureName" requires '
        '${requiredPlan.label} plan. Current plan: ${plan.label}. '
        'Upgrade at ${MorphPlan.upgradeUrl}',
      );
      return true;
    }());
    return false;
  }

  bool checkGripDetection() =>
      check('Grip Detection', gripDetection, MorphPlan.pro);

  bool checkBatteryAwareUI() =>
      check('Battery-Aware UI', batteryAwareUI, MorphPlan.pro);

  bool checkBehavioralSuggestions() => check(
        'Behavioral Suggestions',
        behavioralSuggestions,
        MorphPlan.pro,
      );

  bool checkFatigueDetection() => check(
        'Fatigue Detection',
        fatigueCognitiveDetection,
        MorphPlan.agency,
      );

  bool checkGpsContext() =>
      check('GPS Context UI', gpsContextUI, MorphPlan.agency);

  bool checkAnalyticsDashboard() => check(
        'Analytics Dashboard',
        analyticsDashboard,
        MorphPlan.agency,
      );

  bool checkClaudeInsights() =>
      check('Claude Insights', claudeInsights, MorphPlan.agency);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphPlanFeatures && plan == other.plan;

  @override
  int get hashCode => plan.hashCode;
}
