/// Morph for Flutter — automatic UI adaptation.
///
/// ```dart
/// import 'package:morph_flutter/morph_flutter.dart';
///
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   runApp(MorphProvider(
///     licenseKey: 'cha-pro-xxx',
///     child: MyApp(),
///   ));
/// }
/// ```
library morph_flutter;

// Provider + inherited widget.
export 'src/provider/morph_provider.dart';

// Privacy / analytics — opt-in usage reporting and consent helpers.
export 'src/analytics/analytics_reporter.dart';
export 'src/analytics/morph_analytics_config.dart';

// Navigation — drop-in NavigatorObserver compatible with GoRouter, AutoRoute
// and vanilla MaterialApp.
export 'src/navigation/morph_navigator_observer.dart';

// Suggestions — opt-in card overlay that proposes contextual UI changes.
// Morph NEVER mutates the UI without an explicit tap on the action
// button. Place MorphSuggestionOverlay inside MaterialApp.builder.
export 'src/suggestions/morph_suggestion.dart';
export 'src/suggestions/suggestion_engine.dart' show DarkModeRequestCallback,
    ResumePositionCallback, SuggestionEngine;
export 'src/suggestions/suggestion_history.dart';
export 'src/suggestions/suggestion_overlay.dart';
export 'src/suggestions/widgets/suggestion_card.dart';

// Commercial features — opt-in via MorphFeatures.
export 'src/features/morph_features.dart';

// Subscription plans + capability matrix + license validator + paywall.
export 'src/license/morph_plan.dart';
export 'src/license/morph_plan_features.dart';
export 'src/license/license_validator.dart' show kMorphSdkVersion;
export 'src/license/plan_gate.dart';

// Interruption recovery — re-surfaces "Continue where you left off"
// after 30s+ pauses. Pair with the recovery extensions on BuildContext.
export 'src/recovery/interruption_recovery.dart';
export 'src/recovery/recovery_snapshot.dart';

// Grip detection — accelerometer-driven left/right hand inference.
export 'src/ergonomics/grip_adaptive_layout.dart';
export 'src/ergonomics/grip_detector.dart';

// Battery adapter — read-only mode + adaptive widgets/theme.
export 'src/battery/battery_adapter.dart';
export 'src/battery/battery_aware_widgets.dart';

// Cognitive fatigue — pattern-based estimate + adaptive form scaffold.
export 'src/cognitive/fatigue_adaptive_form.dart';
export 'src/cognitive/fatigue_detector.dart';

// GPS context — uses dev-supplied GPS data, no extra permission.
export 'src/context/gps_adaptive_scaffold.dart';
export 'src/context/gps_context_adapter.dart';

// Zone wrappers + reorderable containers.
export 'src/zone/morph_zone.dart';
export 'src/zone/reorderable_column.dart';
export 'src/zone/zone_scorer.dart';

// Theme detection + AI-generated palettes.
export 'src/theme/morph_adapted_colors.dart';
export 'src/theme/morph_colors.dart';
export 'src/theme/morph_palette_stops.dart';
export 'src/theme/morph_theme_extension.dart';
export 'src/theme/theme_adapter.dart';
export 'src/theme/theme_generator.dart';

// Behavior storage (Hive).
export 'src/behavior/behavior_db.dart';

// Value models.
export 'src/models/morph_system_settings.dart';
export 'src/models/theme_model.dart';
export 'src/models/zone_model.dart';

// BuildContext extensions — `context.morph`, `context.isMorphDark`, …
export 'src/morph_extensions.dart';

// Static entry points — `Morph.systemLocale`, …
export 'src/morph.dart';
