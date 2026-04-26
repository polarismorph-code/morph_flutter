import 'package:flutter/foundation.dart';

import '../behavior/behavior_db.dart';

/// Dev-facing configuration for Morph analytics. Pass this to
/// [MorphProvider] to opt into anonymized usage reporting. **Privacy
/// by default**: when this object is omitted, no data ever leaves the device.
///
/// Two flags must be true for any upload to happen:
///   • [enabled]      — dev wants analytics in their app
///   • [userConsent]  — the end-user has ticked the consent checkbox
///
/// The dev manages their own consent UI (banner, dialog, settings switch)
/// and pipes the result here. Morph never shows a UI on its own.
///
/// CHAMELEON ANALYTICS — PRIVACY CONTRACT
///
/// SENT (anonymized aggregates only):
///   ✅ Zone scores (0.0 to 1.0)
///   ✅ Confirmed navigation sequences
///   ✅ Scroll behavior summary
///   ✅ Zoom count
///   ✅ App hash (non-reversible sha256)
///   ✅ Platform (ios/android)
///   ✅ Month only (not exact date)
///
/// NEVER SENT:
///   ❌ Individual clicks
///   ❌ Exact timestamps
///   ❌ User identity
///   ❌ Device fingerprint
///   ❌ App content or text
///   ❌ Location data
///   ❌ Raw behavioral sequences
///   ❌ Session recordings
///   ❌ Any personally identifiable info
///
/// All data is deleted after [retentionDays] (max 30) locally. Upload
/// requires explicit [userConsent] = true.
@immutable
class MorphAnalyticsConfig {
  /// Master switch — `false` by default. Even when true, [userConsent] must
  /// also be true before anything is transmitted.
  final bool enabled;

  /// End-user consent. The dev passes the value of their own consent state
  /// (e.g. read from SharedPreferences after a banner). Toggle to false at
  /// any time to revoke immediately.
  final bool userConsent;

  /// Called by Morph when [enabled] is true but [userConsent] is false.
  /// Hook your consent banner here. Optional — if null, Morph just stays
  /// silent and never sends anything.
  final VoidCallback? onConsentRequired;

  /// How often the reporter pushes the aggregated payload to the backend.
  /// Default: 24 h. Set to a lower value (e.g. `Duration(minutes: 1)`) in
  /// dev to verify the pipeline without waiting a full day.
  final Duration uploadInterval;

  /// Minimum total clicks/interactions required before a payload is
  /// transmitted. Default: 20 — prevents noisy zero-data uploads from
  /// fresh installs. Lower it (e.g. `1`) for dev / e2e testing.
  final int minInteractions;

  /// Local retention before auto-cleanup deletes a row. **Hard ceiling at
  /// 30 days** — passing more throws.
  final int retentionDays;

  MorphAnalyticsConfig({
    this.enabled = false,
    this.userConsent = false,
    this.onConsentRequired,
    this.uploadInterval = const Duration(hours: 24),
    this.minInteractions = 20,
    this.retentionDays = BehaviorDB.maxRetentionDays,
  }) {
    // Privacy floor — refuse to keep behavioral data more than 30 days,
    // even if the dev tries.
    if (retentionDays > BehaviorDB.maxRetentionDays) {
      throw ArgumentError(
        'Morph retentionDays cannot exceed '
        '${BehaviorDB.maxRetentionDays} days. '
        'Received: $retentionDays',
      );
    }
    if (retentionDays < 1) {
      throw ArgumentError(
        'Morph retentionDays must be at least 1. '
        'Received: $retentionDays',
      );
    }
  }

  /// True when both flags are on — the only state where the reporter
  /// actually transmits.
  bool get canUpload => enabled && userConsent;

  MorphAnalyticsConfig copyWith({
    bool? enabled,
    bool? userConsent,
    VoidCallback? onConsentRequired,
    Duration? uploadInterval,
    int? retentionDays,
  }) {
    return MorphAnalyticsConfig(
      enabled: enabled ?? this.enabled,
      userConsent: userConsent ?? this.userConsent,
      onConsentRequired: onConsentRequired ?? this.onConsentRequired,
      uploadInterval: uploadInterval ?? this.uploadInterval,
      retentionDays: retentionDays ?? this.retentionDays,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphAnalyticsConfig &&
          enabled == other.enabled &&
          userConsent == other.userConsent &&
          uploadInterval == other.uploadInterval &&
          retentionDays == other.retentionDays;

  @override
  int get hashCode =>
      Object.hash(enabled, userConsent, uploadInterval, retentionDays);
}
