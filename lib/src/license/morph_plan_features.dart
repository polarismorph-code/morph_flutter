import 'package:flutter/foundation.dart';

import 'morph_plan.dart';

/// What a given [MorphPlan] is **allowed** to do. The runtime gate is
/// always `wants AND allows`:
///   • `wants` = the dev's opt-in via `MorphFeatures` on the provider
///   • `allows` = an instance of this class derived from the resolved plan
///
/// The dev never instantiates this directly — it lands on
/// `BuildContext.morphPlanFeatures` once the validator has resolved
/// the plan. PlanGate / requireMorphProfessional use it to gate UI access.
///
/// **Naming note**: this class is `MorphPlanFeatures` (not
/// `MorphFeatures`) because the latter is already the dev-facing
/// opt-in flag bag from the commercial-features module. Keeping them
/// distinct means callers can pattern-match `wants && allows` without
/// type collisions.
///
/// Mirrors `PlanService.PlanFeatures` in chameleon-backend — when a
/// flag moves between tiers, both files have to change in lockstep.
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

  // ─── PROFESSIONAL — Pro+ ────────────────────────────────────────────────

  /// Premium Claude Sonnet for theme generation. Free silent-degrades
  /// to Haiku server-side (same JSON shape).
  bool get sonnetTheme => plan.isProfessional;

  /// V2 behavioral intelligence — zone reorder, morphing, suggestion
  /// engine. The umbrella flag every other Pro+ V2 widget keys off.
  bool get behavioralV2 => plan.isProfessional;

  bool get morphZone => plan.isProfessional;
  bool get reorderableColumn => plan.isProfessional;
  bool get navigatorObserver => plan.isProfessional;
  bool get suggestionEngine => plan.isProfessional;

  bool get gripDetection => plan.isProfessional;
  bool get batteryAware => plan.isProfessional;
  bool get chargePatternPredictor => plan.isProfessional;

  /// Rich context-aware recovery (cart, transfer, KYC step, …).
  bool get recoveryAdvanced => plan.isProfessional;
  bool get recoveryContextual => plan.isProfessional;
  bool get multiStepWorkflow => plan.isProfessional;

  bool get circadianRhythm => plan.isProfessional;

  // ─── BUSINESS — agency-grade ────────────────────────────────────────────

  bool get fatigueDetection => plan.isBusiness;
  bool get fatigueBaseline => plan.isBusiness;

  bool get gpsContext => plan.isBusiness;
  bool get gpsAccelerometerFusion => plan.isBusiness;

  bool get industryPresets => plan.isBusiness;

  bool get analyticsDashboard => plan.isBusiness;
  bool get metricsReporter => plan.isBusiness;
  bool get dashboardExporter => plan.isBusiness;
  bool get aiInsights => plan.isBusiness;

  bool get whiteLabel => plan.isBusiness;

  // ─── ENTERPRISE only ────────────────────────────────────────────────────

  bool get sso => plan.isEnterprise;
  bool get sla => plan.isEnterprise;
  bool get customInfrastructure => plan.isEnterprise;

  // ─── Legacy aliases — kept for backward compatibility ───────────────────
  //
  // App code written against the pre-Day-2 vocabulary still compiles.
  // New code should use the canonical names above.

  @Deprecated('Renamed to recoveryAdvanced. Will be removed in v0.4.')
  bool get interruptionRecoveryAdvanced => recoveryAdvanced;

  @Deprecated('Renamed to suggestionEngine. Will be removed in v0.4.')
  bool get behavioralSuggestions => suggestionEngine;

  @Deprecated('Renamed to navigatorObserver. Will be removed in v0.4.')
  bool get navigationTracking => navigatorObserver;

  @Deprecated('Renamed to behavioralV2. Will be removed in v0.4.')
  bool get behavioralAnalyticsLocal => behavioralV2;

  @Deprecated('Renamed to batteryAware. Will be removed in v0.4.')
  bool get batteryAwareUI => batteryAware;

  @Deprecated('Renamed to fatigueDetection. Will be removed in v0.4.')
  bool get fatigueCognitiveDetection => fatigueDetection;

  @Deprecated('Renamed to gpsContext. Will be removed in v0.4.')
  bool get gpsContextUI => gpsContext;

  @Deprecated('Renamed to aiInsights. Will be removed in v0.4.')
  bool get claudeInsights => aiInsights;

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
      check('Grip Detection', gripDetection, MorphPlan.professional);

  bool checkBatteryAware() =>
      check('Battery-Aware UI', batteryAware, MorphPlan.professional);

  bool checkSuggestionEngine() => check(
        'Suggestion Engine',
        suggestionEngine,
        MorphPlan.professional,
      );

  bool checkFatigueDetection() => check(
        'Fatigue Detection',
        fatigueDetection,
        MorphPlan.business,
      );

  bool checkGpsContext() =>
      check('GPS Context UI', gpsContext, MorphPlan.business);

  bool checkAnalyticsDashboard() => check(
        'Analytics Dashboard',
        analyticsDashboard,
        MorphPlan.business,
      );

  bool checkAiInsights() =>
      check('AI Insights', aiInsights, MorphPlan.business);

  // Legacy check-helper aliases — same compat contract as the getters.

  @Deprecated('Renamed to checkBatteryAware. Will be removed in v0.4.')
  bool checkBatteryAwareUI() => checkBatteryAware();

  @Deprecated('Renamed to checkSuggestionEngine. Will be removed in v0.4.')
  bool checkBehavioralSuggestions() => checkSuggestionEngine();

  @Deprecated('Renamed to checkAiInsights. Will be removed in v0.4.')
  bool checkClaudeInsights() => checkAiInsights();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphPlanFeatures && plan == other.plan;

  @override
  int get hashCode => plan.hashCode;
}
