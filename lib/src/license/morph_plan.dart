/// The four subscription tiers Morph licenses can hold. Resolved at
/// boot by [LicenseValidator] from the backend response (or from the
/// 24-hour Hive cache, or from the demo-key shortcut).
///
/// Pricing + daily-call limits live here so the SDK and the dashboard
/// stay in sync without a second source of truth. Mirrors `PlanService`
/// in chameleon-backend.
enum MorphPlan {
  free,
  professional,
  business,
  enterprise;

  /// Lenient parser — accepts the new 4-tier vocabulary AND the legacy
  /// names ('pro' → professional, 'agency' → business). Anything we
  /// don't recognize collapses to [free] (the safe default). Used by
  /// [LicenseValidator] when the backend returns an unexpected plan
  /// string from a future-version API or an old cached row.
  static MorphPlan fromString(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'professional':
        return MorphPlan.professional;
      case 'pro':
        // Legacy alias — pre-Day-2 backend spelled the Professional tier
        // as 'pro'. Kept for old Hive caches and old API responses.
        return MorphPlan.professional;
      case 'business':
        return MorphPlan.business;
      case 'agency':
        // Legacy alias — pre-Day-2 backend spelled the Business tier
        // as 'agency'. Same backward-compat note as 'pro'.
        return MorphPlan.business;
      case 'enterprise':
        return MorphPlan.enterprise;
      default:
        return MorphPlan.free;
    }
  }

  /// Display name used in dialogs / paywalls / debug logs.
  String get label {
    switch (this) {
      case MorphPlan.free:
        return 'Free';
      case MorphPlan.professional:
        return 'Professional';
      case MorphPlan.business:
        return 'Business';
      case MorphPlan.enterprise:
        return 'Enterprise';
    }
  }

  /// Marketing-facing monthly price. Kept as a string because the SaaS
  /// already formats currency this way on morphui.dev/pricing. Enterprise
  /// is contact-sales — no published number.
  String get price {
    switch (this) {
      case MorphPlan.free:
        return '\$0/mo';
      case MorphPlan.professional:
        return '\$29/mo';
      case MorphPlan.business:
        return '\$99/mo';
      case MorphPlan.enterprise:
        return 'Custom';
    }
  }

  /// Backend-enforced cap on `/api/flutter/*` calls per 24h. Mirrored
  /// here so the dashboard can render quotas without an extra round-trip.
  /// Enterprise uses a sentinel large value to keep the type as `int`
  /// while signalling "no practical cap".
  int get dailyApiCalls {
    switch (this) {
      case MorphPlan.free:
        return 100;
      case MorphPlan.professional:
        return 5000;
      case MorphPlan.business:
        return 50000;
      case MorphPlan.enterprise:
        return 999999999;
    }
  }

  bool get isFree => this == MorphPlan.free;

  /// True for Professional, Business, AND Enterprise — the inclusive
  /// interpretation. Use this when checking "can the user have a
  /// Pro-tier feature?".
  bool get isProfessional =>
      this == MorphPlan.professional ||
      this == MorphPlan.business ||
      this == MorphPlan.enterprise;

  /// True for Business AND Enterprise.
  bool get isBusiness =>
      this == MorphPlan.business || this == MorphPlan.enterprise;

  bool get isEnterprise => this == MorphPlan.enterprise;

  /// Legacy alias for [isProfessional]. Kept so app code that pre-dates
  /// the rename keeps compiling. Prefer the new name in new code.
  @Deprecated('Renamed to isProfessional. Will be removed in v0.4.')
  bool get isPro => isProfessional;

  /// Legacy alias for [isBusiness]. Same deprecation contract as [isPro].
  @Deprecated('Renamed to isBusiness. Will be removed in v0.4.')
  bool get isAgency => isBusiness;

  /// Where to send users who hit a paywall. Used by [PlanGate]'s default
  /// upgrade affordance — the dev can override the callback if they
  /// prefer an in-app billing flow.
  static const String upgradeUrl = 'https://morphui.dev/pricing';
}
