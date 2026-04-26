/// The three subscription tiers Morph licenses can hold. Resolved at
/// boot by [LicenseValidator] from the backend response (or from the
/// 24-hour Hive cache, or from the demo-key shortcut).
///
/// Pricing + daily-call limits live here so the SDK and the dashboard
/// stay in sync without a second source of truth.
enum MorphPlan {
  free,
  pro,
  agency;

  /// Lenient parser — anything we don't recognize collapses to [free]
  /// (the safe default). Used by [LicenseValidator] when the backend
  /// returns an unexpected plan string from a future-version API.
  static MorphPlan fromString(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'pro':
        return MorphPlan.pro;
      case 'agency':
        return MorphPlan.agency;
      default:
        return MorphPlan.free;
    }
  }

  /// Display name used in dialogs / paywalls / debug logs.
  String get label {
    switch (this) {
      case MorphPlan.free:
        return 'Free';
      case MorphPlan.pro:
        return 'Pro';
      case MorphPlan.agency:
        return 'Agency';
    }
  }

  /// Marketing-facing monthly price. Kept as a string because the SaaS
  /// already formats currency this way on morphui.app/pricing.
  String get price {
    switch (this) {
      case MorphPlan.free:
        return '\$0/mo';
      case MorphPlan.pro:
        return '\$19/mo';
      case MorphPlan.agency:
        return '\$49/mo';
    }
  }

  /// Backend-enforced cap on `/api/flutter/*` calls per 24h. Mirrored
  /// here so the dashboard can render quotas without an extra round-trip.
  /// Agency uses a sentinel large value to keep the type as `int` while
  /// signalling "no practical cap".
  int get dailyApiCalls {
    switch (this) {
      case MorphPlan.free:
        return 50;
      case MorphPlan.pro:
        return 2000;
      case MorphPlan.agency:
        return 999999;
    }
  }

  bool get isFree => this == MorphPlan.free;

  /// True for both Pro AND Agency — the inclusive interpretation.
  /// Use this when checking "can the user have a Pro feature?".
  bool get isPro =>
      this == MorphPlan.pro || this == MorphPlan.agency;

  bool get isAgency => this == MorphPlan.agency;

  /// Where to send users who hit a paywall. Used by [PlanGate]'s default
  /// upgrade affordance — the dev can override the callback if they
  /// prefer an in-app billing flow.
  static const String upgradeUrl = 'https://morphui.dev/#pricing';
}
