import 'package:flutter/foundation.dart';

/// Opt-in flag bag passed to [MorphProvider]. Each commercial feature
/// is dormant unless the dev explicitly enables it — only
/// [interruptionRecovery] is on by default because it has zero runtime
/// cost and requires no permissions.
///
/// Use the named constructors [ecommerce] / [fintech] for the curated
/// presets; pass an explicit `MorphFeatures(...)` for custom mixes.
@immutable
class MorphFeatures {
  /// Detects 30s+ app pauses and surfaces a "Continue where you left off"
  /// suggestion via the existing [SuggestionEngine]. Zero permissions.
  final bool interruptionRecovery;

  /// Reads the accelerometer to infer left/right grip and lets
  /// `GripAdaptiveLayout` place CTAs on the user's dominant side.
  /// Requires `sensors_plus` runtime support; no OS permission needed.
  final bool gripDetection;

  /// Listens to `Battery.onBatteryStateChanged` and exposes a
  /// `BatteryMode` stream that `BatteryAwareWidget` / `BatteryAwareTheme`
  /// can react to. Read-only access — Morph never controls power.
  final bool batteryAware;

  /// Buffers tap accuracy + typing cadence to estimate a `FatigueLevel`.
  /// Operates on aggregate signals only — no PII, no content inspection.
  final bool fatigueDetection;

  /// Receives location updates from the host app's existing GPS pipeline
  /// (no extra permission requested by the SDK) and exposes a
  /// `MovementContext` stream.
  final bool gpsContext;

  const MorphFeatures({
    this.interruptionRecovery = true,
    this.gripDetection = false,
    this.batteryAware = false,
    this.fatigueDetection = false,
    this.gpsContext = false,
  });

  /// Curated mix for shopping apps: protect the cart through interruptions
  /// and let CTAs follow the user's hand on long product pages.
  factory MorphFeatures.ecommerce() => const MorphFeatures(
        interruptionRecovery: true,
        gripDetection: true,
      );

  /// Curated mix for finance apps: protect multi-step flows, react to
  /// battery + cognitive load, and adapt the UI when the user starts
  /// moving (handoff from desk to commute).
  factory MorphFeatures.fintech() => const MorphFeatures(
        interruptionRecovery: true,
        batteryAware: true,
        fatigueDetection: true,
        gpsContext: true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphFeatures &&
          interruptionRecovery == other.interruptionRecovery &&
          gripDetection == other.gripDetection &&
          batteryAware == other.batteryAware &&
          fatigueDetection == other.fatigueDetection &&
          gpsContext == other.gpsContext;

  @override
  int get hashCode => Object.hash(
        interruptionRecovery,
        gripDetection,
        batteryAware,
        fatigueDetection,
        gpsContext,
      );
}
