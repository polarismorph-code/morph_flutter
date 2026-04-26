import 'package:flutter/material.dart';

import 'analytics/morph_analytics_config.dart';
import 'behavior/behavior_db.dart';
import 'license/morph_plan.dart';
import 'license/morph_plan_features.dart';
import 'license/plan_gate.dart';
import 'models/morph_system_settings.dart';
import 'models/theme_model.dart';
import 'models/zone_model.dart';
import 'navigation/morph_navigator_observer.dart';
import 'provider/morph_provider.dart';
import 'theme/morph_adapted_colors.dart';
import 'zone/zone_scorer.dart';

/// Flutter-native equivalent of the `useMorph()` hook.
/// Reach the Morph state from any descendant via `context.morph`.
extension MorphContext on BuildContext {
  /// Full state snapshot. Throws if called outside a [MorphProvider].
  MorphState get morph => MorphInheritedWidget.of(this).state;

  /// Theme details — what the system says + any AI-generated palette.
  MorphTheme get morphTheme => morph.theme;

  /// True when the system is asking for dark. Use this instead of a
  /// local theme toggle when you want to respect the user's device.
  bool get isMorphDark => morphTheme.mode == ThemeMode.dark;

  /// True when OS high-contrast is enabled.
  bool get isHighContrast => morphTheme.isHighContrast;

  /// Raw OS-reported settings (brightness, boldText, disableAnimations, …).
  MorphSystemSettings get systemSettings => morph.systemSettings;

  /// ThemeData with dark/high-contrast/bold/reduced-motion tweaks already
  /// applied. Null when the dev didn't pass a `baseTheme` to
  /// [MorphProvider] — in that case fall back to your own theme.
  ThemeData? get adaptedTheme => morph.adaptedTheme;

  /// True once the scorer has decided to boost body text sizes.
  bool get isFontScaleApplied => morph.fontScaleApplied;

  /// Zone-id → order map. Empty until the scorer has enough data.
  Map<String, int> get zoneOrder => morph.zoneOrder;

  /// The persistent behavior store — call `trackClick`, `trackTimeSpent`, …
  BehaviorDB get morphDB => MorphInheritedWidget.of(this).db;

  /// Reorder notifier — listen for fine-grained updates if you need them.
  ZoneReorder get morphReorder => MorphInheritedWidget.of(this).reorder;

  /// Safe, null-able variant — returns null if no provider is mounted
  /// (useful for widgets that want to render in isolation tests).
  MorphState? get maybeMorph =>
      MorphInheritedWidget.maybeOf(this)?.state;

  /// Adapted semantic color palette. Null when no adaptation is needed
  /// (system brightness matches the app's base theme). Use this in
  /// [AppColors]-style helpers:
  /// ```dart
  /// static Color background(BuildContext ctx) =>
  ///     ctx.morphPalette?.background ?? AppColorsNeutral.s50;
  /// ```
  MorphAdaptedColors? get morphPalette =>
      MorphInheritedWidget.maybeOf(this)?.state.adaptedColors;

  /// The [MorphAnalyticsConfig] the dev passed to [MorphProvider],
  /// or null when analytics is disabled (the default).
  MorphAnalyticsConfig? get morphAnalyticsConfig =>
      MorphInheritedWidget.maybeOf(this)?.state.analyticsConfig;

  /// Convenience accessor for the singleton [MorphNavigatorObserver].
  /// Equivalent to `MorphNavigatorObserver.instance` — same object,
  /// nicer to read inside a `Builder` when wiring `GoRouter.observers`.
  MorphNavigatorObserver get morphNavigatorObserver =>
      MorphNavigatorObserver.instance;
}

/// Recovery-context declarations. Devs call these from a screen's
/// `didChangeDependencies` (or anywhere with a context) so Morph knows
/// what message to surface if the user is interrupted on this page.
///
/// All four are no-ops when [MorphFeatures.interruptionRecovery] is
/// off — drop-in safe.
extension MorphRecoveryContext on BuildContext {
  /// E-commerce: declare a checkout in progress so a 30s+ background
  /// pause produces "You were completing your order" on resume.
  void morphSetCheckoutContext({
    required Map<String, dynamic> cartData,
    required double scrollDepth,
  }) {
    final r = MorphInheritedWidget.maybeOf(this)?.recovery;
    r?.declareContext(
      page: ModalRoute.of(this)?.settings.name ?? '',
      context: 'checkout',
      scrollDepth: scrollDepth,
      metadata: cartData,
    );
  }

  /// E-commerce: declare a product page so the recovery message can name
  /// the product the user was viewing.
  void morphSetProductContext({
    required String productName,
    required String productId,
    required double scrollDepth,
  }) {
    final r = MorphInheritedWidget.maybeOf(this)?.recovery;
    r?.declareContext(
      page: ModalRoute.of(this)?.settings.name ?? '',
      context: 'product',
      scrollDepth: scrollDepth,
      metadata: {'productName': productName, 'productId': productId},
    );
  }

  /// Fintech: declare an in-progress transfer so the recovery message
  /// can echo the amount + recipient.
  void morphSetTransferContext({
    required String amount,
    required String recipient,
    required int step,
  }) {
    final r = MorphInheritedWidget.maybeOf(this)?.recovery;
    r?.declareContext(
      page: ModalRoute.of(this)?.settings.name ?? '',
      context: 'transfer',
      scrollDepth: 0,
      metadata: {
        'amount': amount,
        'recipient': recipient,
        'step': step,
      },
    );
  }

  /// Fintech: declare a KYC step so recovery can resume mid-verification.
  /// [savedData] stays on-device — only the dev's recovery action ever
  /// reads it back.
  void morphSetKycContext({
    required int step,
    required int totalSteps,
    required Map<String, dynamic> savedData,
  }) {
    final r = MorphInheritedWidget.maybeOf(this)?.recovery;
    r?.declareContext(
      page: ModalRoute.of(this)?.settings.name ?? '',
      context: 'kyc',
      scrollDepth: totalSteps == 0 ? 0 : (step / totalSteps) * 100,
      formData: savedData,
      metadata: {'step': step, 'totalSteps': totalSteps},
    );
  }
}

/// Privacy-screen helpers — read the live consent state and trigger the
/// data-erase flow from any descendant widget.
///
/// ```dart
/// SwitchListTile(
///   title: const Text('Share usage data'),
///   value: context.morphAnalyticsEnabled
///       && context.morphUserConsented,
///   onChanged: (v) async {
///     if (!v) await context.clearMorphData();
///     // ...persist the new consent and pass it back via MorphProvider
///   },
/// )
/// ```
extension MorphAnalyticsContext on BuildContext {
  /// True when the dev has set `enabled: true` in [MorphAnalyticsConfig].
  /// Says nothing about whether the user has consented — pair with
  /// [morphUserConsented] for the "is data flowing" check.
  bool get morphAnalyticsEnabled =>
      MorphInheritedWidget.maybeOf(this)
          ?.state
          .analyticsConfig
          ?.enabled ??
      false;

  /// True when the end-user has consented to analytics. Mirrors the
  /// `userConsent` flag the dev passes via [MorphAnalyticsConfig].
  bool get morphUserConsented =>
      MorphInheritedWidget.maybeOf(this)
          ?.state
          .analyticsConfig
          ?.userConsent ??
      false;

  /// Approximate on-disk size of Morph's local behavioral store, in KB.
  /// Returns 0 when no provider is mounted.
  Future<int> get morphStorageSize async {
    final db = MorphInheritedWidget.maybeOf(this)?.db;
    if (db == null) return 0;
    return db.getSize();
  }

  /// Hard-delete every behavioral row across all local boxes. Wire to a
  /// "Clear local data" button or call automatically when revoking consent.
  Future<void> clearMorphData() async {
    final db = MorphInheritedWidget.maybeOf(this)?.db;
    if (db == null) return;
    await db.clearAll();
  }
}

/// License-plan helpers — read the resolved tier and gate features at the
/// call site without dragging a [PlanGate] around. Useful for
/// imperative flows (e.g. opening an Agency-only screen via a button).
///
/// ```dart
/// FilledButton(
///   onPressed: () => context.requireMorphAgency(() {
///     Navigator.push(context, ...);
///   }),
///   child: const Text('Open analytics'),
/// );
/// ```
extension MorphPlanContext on BuildContext {
  /// Resolved subscription tier. Defaults to FREE when no provider is
  /// mounted (or before the validator returns).
  MorphPlan get morphPlan =>
      MorphInheritedWidget.maybeOf(this)?.plan ?? MorphPlan.free;

  /// Capability matrix derived from [morphPlan].
  MorphPlanFeatures get morphPlanFeatures =>
      MorphInheritedWidget.maybeOf(this)?.planFeatures ??
      const MorphPlanFeatures(plan: MorphPlan.free);

  /// Shorthand — true for both Pro AND Agency plans.
  bool get isMorphPro => morphPlan.isPro;

  /// Shorthand — true only on Agency.
  bool get isMorphAgency => morphPlan.isAgency;

  /// Imperative gate — invokes [onAllowed] when the plan is Pro+, else
  /// invokes [onDenied] (or no-ops if [onDenied] is null).
  ///
  /// **The SDK never auto-shows a Morph-branded dialog to your end
  /// users.** Your customers' subscription state is your relationship
  /// with Morph, not theirs. If you want to surface a custom upsell —
  /// on YOUR admin surface, billing-recovery flow, or developer
  /// settings — wire [onDenied] to YOUR own UI:
  ///
  /// ```dart
  /// context.requireMorphPro(
  ///   () => Navigator.push(context, ...),         // happy path
  ///   onDenied: () => showSnackBar('Available soon'), // optional fallback
  /// );
  /// ```
  ///
  /// Or, on YOUR admin screen where it's safe to surface Morph
  /// branding, opt explicitly into the bundled dialog:
  /// ```dart
  /// context.requireMorphPro(
  ///   () => Navigator.push(context, ...),
  ///   onDenied: () => showDialog(
  ///     context: context,
  ///     builder: (_) => const MorphUpgradeDialog(
  ///       requiredPlan: MorphPlan.pro,
  ///     ),
  ///   ),
  /// );
  /// ```
  void requireMorphPro(
    VoidCallback onAllowed, {
    VoidCallback? onDenied,
  }) {
    if (morphPlan.isPro) {
      onAllowed();
    } else if (onDenied != null) {
      onDenied();
    }
  }

  /// Same contract as [requireMorphPro] but for the Agency tier — see
  /// that method's doc for the safety story.
  void requireMorphAgency(
    VoidCallback onAllowed, {
    VoidCallback? onDenied,
  }) {
    if (morphPlan.isAgency) {
      onAllowed();
    } else if (onDenied != null) {
      onDenied();
    }
  }
}
