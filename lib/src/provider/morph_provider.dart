import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../analytics/analytics_reporter.dart';
import '../analytics/morph_analytics_config.dart';
import '../battery/battery_adapter.dart';
import '../behavior/behavior_db.dart';
import '../cognitive/fatigue_detector.dart';
import '../context/gps_context_adapter.dart';
import '../ergonomics/grip_detector.dart';
import '../features/morph_features.dart';
import '../license/app_identity.dart';
import '../license/morph_plan.dart';
import '../license/morph_plan_features.dart';
import '../license/license_validator.dart';
import '../models/morph_system_settings.dart';
import '../models/theme_model.dart';
import '../models/zone_model.dart';
import '../navigation/morph_navigator_observer.dart';
import '../recovery/interruption_recovery.dart';
import '../suggestions/suggestion_engine.dart';
import '../suggestions/suggestion_history.dart';
import '../suggestions/suggestion_overlay.dart';
import '../theme/morph_adapted_colors.dart';
import '../theme/morph_colors.dart';
import '../theme/morph_raw_colors.dart';
import '../theme/color_extractor.dart';
import '../theme/theme_adapter.dart';
import '../theme/theme_generator.dart';
import '../zone/zone_scorer.dart';

/// Root widget — wraps the app and coordinates storage, scoring, and theme
/// detection. Use exactly once, typically in `main.dart`.
///
/// ```dart
/// runApp(MorphProvider(
///   licenseKey: 'cha-pro-xxx',
///   child: MyApp(),
/// ));
/// ```
///
/// **Privacy by default**: when [analytics] is null (the default), nothing
/// behavioral ever leaves the device. Only the theme generation endpoint is
/// hit, and only when needed. Pass [MorphAnalyticsConfig] to opt into
/// anonymized usage reporting — both `enabled` and `userConsent` must be
/// true for any upload to happen.
///
/// With [safeMode] enabled, system detection runs but nothing is persisted
/// and no reorder is applied — useful for tests and gradual rollouts.
class MorphProvider extends StatefulWidget {
  final Widget child;
  final String licenseKey;
  final bool safeMode;
  final MorphConfig config;

  /// CAS 1 — When provided, Morph auto-calls `/flutter/theme/generate`
  /// at boot and on every brightness change, using this theme's colors.
  /// The adapted ThemeData lands on `context.morph.adaptedTheme`.
  final ThemeData? baseTheme;

  /// CAS 2 / CAS 3 — Dev-declared palette from their own `AppColors` file.
  /// When passed, [ColorExtractor] uses these values first and fills any
  /// remaining slots from [baseTheme] (or the ambient `Theme.of(context)`).
  /// Leave null for CAS 1.
  final MorphColors? colors;

  /// Animation duration when the generated theme lands and replaces the
  /// previous one. Set to [Duration.zero] to opt out.
  final Duration themeAnimationDuration;

  /// Optional. When null (the default) **no behavioral data ever leaves the
  /// device** — local scoring still runs for in-app reorders, but nothing is
  /// transmitted. Pass a [MorphAnalyticsConfig] with both `enabled: true`
  /// and `userConsent: true` to start uploading anonymized aggregates to
  /// `/api/flutter/behavior/report`. See the analytics config doc for the
  /// full privacy contract.
  final MorphAnalyticsConfig? analytics;

  /// Hook the suggestion engine calls when the user accepts a "Night
  /// mode" suggestion. The dev decides what dark-mode actually means in
  /// their app (toggle ThemeMode in Riverpod, persist in SharedPreferences,
  /// etc.). When null, the dark-mode-auto suggestion is never proposed.
  final DarkModeRequestCallback? onDarkModeRequested;

  /// Hook the suggestion engine calls when the user accepts a
  /// "Continue where you left off" suggestion. Receives the route name
  /// and depth percentage (0..100); the dev's implementation typically
  /// scrolls a controller. When null, the resume-position suggestion is
  /// never proposed.
  final ResumePositionCallback? onResumePosition;

  /// Opt-in flags for the commercial feature engines (interruption
  /// recovery, grip detection, battery, fatigue, GPS context). Defaults
  /// to "interruption recovery only" — use
  /// [MorphFeatures.ecommerce] / [MorphFeatures.fintech] for
  /// the curated presets.
  final MorphFeatures features;

  const MorphProvider({
    required this.child,
    required this.licenseKey,
    this.safeMode = false,
    this.config = const MorphConfig(),
    this.baseTheme,
    this.colors,
    this.themeAnimationDuration = const Duration(milliseconds: 400),
    this.analytics,
    this.onDarkModeRequested,
    this.onResumePosition,
    this.features = const MorphFeatures(),
    super.key,
  });

  @override
  State<MorphProvider> createState() => _MorphProviderState();
}

class _MorphProviderState extends State<MorphProvider>
    with WidgetsBindingObserver {
  final BehaviorDB _db = BehaviorDB();
  late final ThemeAdapter _themeAdapter;
  late final ThemeGenerator _themeGenerator;
  late final ZoneScorer _scorer;
  final ZoneReorder _reorder = ZoneReorder();

  Timer? _analysisTimer;
  MorphState? _state;
  bool _initStarted = false;
  // Zones declared with <MorphZone> — the scorer needs their base priority.
  final Map<String, int> _priorities = {};

  // Latest OS-reported state. Compared against each new reading to skip
  // rebuilds when nothing actually changed.
  MorphSystemSettings _systemSettings = const MorphSystemSettings();

  // Extracted palette from ColorExtractor — the canonical input to the
  // opposite-generation path. Rebuilt when MorphColors or the ambient
  // theme changes.
  MorphRawColors? _rawColors;

  // In-memory cache of generated palettes, keyed by
  // `${rawBackgroundHex}_${target}`. Survives brightness toggles but NOT
  // app restarts — the backend's own (licenseKey, colors, adaptation)
  // cache picks up the slack across process boundaries.
  final Map<String, _CachedPalette> _paletteCache = {};

  // Guards against overlapping generation calls triggered by rapid
  // platform events (brightness + metrics can both fire on toggle).
  bool _generating = false;

  // Outbound analytics — null when the dev didn't pass an analytics config,
  // or when safeMode is on. The reporter does its own consent gating.
  AnalyticsReporter? _reporter;

  // Suggestion system — local-only. Always created (no consent needed
  // since nothing leaves the device), unless safeMode is on.
  SuggestionHistoryStore? _historyStore;
  SuggestionEngine? _suggestionEngine;

  // Commercial feature engines — instantiated only when the matching
  // feature flag is on (and never in safeMode). All dispose() calls are
  // null-safe so the provider's dispose can fire blindly.
  InterruptionRecovery? _recovery;
  GripDetector? _grip;
  BatteryAdapter? _battery;
  FatigueDetector? _fatigue;
  GpsContextAdapter? _gps;

  // License-resolved plan + capability matrix. Populated by
  // [LicenseValidator] before any engine init. Default to FREE so reads
  // are always safe even before bootstrap completes (the build guard
  // also short-circuits while [_state] is null).
  LicenseValidator? _licenseValidator;
  MorphPlan _plan = MorphPlan.free;
  MorphPlanFeatures _planFeatures =
      const MorphPlanFeatures(plan: MorphPlan.free);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeAdapter = ThemeAdapter(licenseKey: widget.licenseKey);
    _themeGenerator = ThemeGenerator(_themeAdapter);
    _scorer = ZoneScorer(_db, minInteractions: widget.config.minInteractions);

    // Rule: no network calls in initState. Defer to the first post-frame
    // callback so BuildContext / MediaQuery are ready.
    SchedulerBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_initStarted || !mounted) return;
    _initStarted = true;

    // Fast path — `safeMode` means "detect, don't act". Skip the
    // license HTTP, the Hive init, every feature engine. Just read
    // the system state, expose it synchronously, and return. Anything
    // network-bound here (license validation in particular) would hang
    // the test harness or burn the host app's first frame for nothing.
    if (widget.safeMode) {
      final theme = _themeAdapter.detect(context);
      _systemSettings = _themeAdapter.readSettings(context);
      _rawColors = ColorExtractor.extract(
        context: context,
        declaredColors: widget.colors,
        baseTheme: widget.baseTheme,
      );
      final adapted = _buildAdapted(_systemSettings, theme.generated);
      if (!mounted) return;
      setState(
        () => _state = MorphState.safe(theme).copyWith(
          systemSettings: _systemSettings,
          adaptedTheme: adapted,
          adaptedColors:
              _buildAdaptedColors(_systemSettings, adapted, theme.generated),
          analyticsConfig: widget.analytics,
        ),
      );
      return;
    }

    // Phase −1 — resolve the host app's package identifier so every
    // subsequent backend call (validate, theme, behavior, impact) can
    // include `appId` in its payload. The backend rejects calls whose
    // appId doesn't match the license's `allowed_packages` binding.
    // Cached after the first call, so this is one platform-channel
    // round-trip per app process.
    try {
      await AppIdentity.resolve();
    } catch (_) {
      // Silent — calls will send '' and the backend will return a
      // descriptive 403, which is still better than failing init.
    }

    // Phase 0 — resolve the license plan BEFORE touching any engine. The
    // validator opens its own Hive box (cml_config), so it doesn't depend
    // on _db.init() running first. Any failure degrades to FREE so the
    // app never blocks on an unreachable backend.
    _licenseValidator = LicenseValidator(licenseKey: widget.licenseKey);
    _plan = await _licenseValidator!.validate();
    _planFeatures = MorphPlanFeatures(plan: _plan);
    _logPlanInfo();

    // Honor the dev's retention setting for the local store. The DB clamps
    // to its own ceiling (max 30 days) defensively.
    await _db.init(
      retentionDays:
          widget.analytics?.retentionDays ?? BehaviorDB.maxRetentionDays,
    );

    // Wire the singleton navigator observer to our DB. The dev plugged it
    // into their router earlier; this is what makes the calls actually
    // land in Hive instead of being no-ops.
    MorphNavigatorObserver.instance.attach(_db);

    // Suggestion store + engine — entirely local, no consent gate. Skipped
    // in safeMode to keep test environments hermetic. Each engine is
    // gated by `wants AND allows` — the dev opts in via [features], the
    // plan grants permission via [_planFeatures]. Either alone is not
    // enough.
    if (!widget.safeMode) {
      _historyStore = SuggestionHistoryStore();
      await _historyStore!.init();

      // ── Commercial feature engines ───────────────────────────────────
      final wants = widget.features;
      final allows = _planFeatures;

      // Interruption recovery — FREE plan is allowed (basic mode only).
      // The `advancedContexts` flag toggles rich snapshot capture.
      if (wants.interruptionRecovery && allows.interruptionRecoveryBasic) {
        _recovery = InterruptionRecovery(
          db: _db,
          historyStore: _historyStore!,
          advancedContexts: allows.interruptionRecoveryAdvanced,
        );
        _recovery!.start();
      }
      if (wants.gripDetection && allows.gripDetection) {
        _grip = GripDetector(db: _db);
        unawaited(_grip!.start());
      } else if (wants.gripDetection) {
        allows.checkGripDetection(); // logs upgrade hint in debug
      }
      if (wants.batteryAware && allows.batteryAwareUI) {
        _battery = BatteryAdapter(db: _db);
        unawaited(_battery!.start());
      } else if (wants.batteryAware) {
        allows.checkBatteryAwareUI();
      }
      if (wants.fatigueDetection && allows.fatigueCognitiveDetection) {
        _fatigue = FatigueDetector(db: _db);
        unawaited(_fatigue!.startSession());
      } else if (wants.fatigueDetection) {
        allows.checkFatigueDetection();
      }
      if (wants.gpsContext && allows.gpsContextUI) {
        _gps = GpsContextAdapter();
        // Subscribes to the accelerometer for the train-detection
        // fallback. No-op on platforms without an accelerometer (web,
        // some emulators) — the GPS path keeps working.
        _gps!.start();
      } else if (wants.gpsContext) {
        allows.checkGpsContext();
      }

      // Suggestion engine — PRO+ only. FREE plans get the recovery card
      // (still routed through this engine when constructed) but no
      // behavioral checks. We construct the engine when EITHER recovery
      // or behavioral suggestions are eligible, so the recovery card
      // path stays alive on FREE.
      final wantsEngine = _recovery != null || allows.behavioralSuggestions;
      if (wantsEngine) {
        _suggestionEngine = SuggestionEngine(
          db: _db,
          historyStore: _historyStore!,
          navObserver: MorphNavigatorObserver.instance,
          zoneReorder: _reorder,
          onDarkModeRequested:
              allows.behavioralSuggestions ? widget.onDarkModeRequested : null,
          recovery: _recovery,
          batteryAdapter:
              allows.behavioralSuggestions ? _battery : null,
        );
      }
    }

    final theme = _themeAdapter.detect(context);
    _systemSettings = _themeAdapter.readSettings(context);
    _rawColors = ColorExtractor.extract(
      context: context,
      declaredColors: widget.colors,
      baseTheme: widget.baseTheme,
    );
    _logColorSourceOnce(_rawColors!);
    final adapted = _buildAdapted(_systemSettings, theme.generated);

    if (widget.safeMode) {
      if (!mounted) return;
      setState(() => _state = MorphState.safe(theme).copyWith(
            systemSettings: _systemSettings,
            adaptedTheme: adapted,
            adaptedColors: _buildAdaptedColors(_systemSettings, adapted, theme.generated),
            analyticsConfig: widget.analytics,
          ));
      return;
    }

    final sessionId = await _db.startSession();
    if (!mounted) return;
    setState(() {
      _state = MorphState(
        theme: theme,
        sessionId: sessionId,
        systemSettings: _systemSettings,
        adaptedTheme: adapted,
        adaptedColors: _buildAdaptedColors(_systemSettings, adapted, theme.generated),
        analyticsConfig: widget.analytics,
      );
    });

    // Local scorer — runs every analysisInterval, never touches the network.
    _analysisTimer = Timer.periodic(
      widget.config.analysisInterval,
      (_) => _analyze(),
    );
    unawaited(_analyze());

    // Analytics — created only when the dev configured it. The reporter's
    // start() handles consent gating internally (no upload until both
    // enabled & userConsent are true).
    _spawnReporter();

    // Theme generation is core SDK — runs regardless of analytics consent.
    // Only fires when the OS brightness is the OPPOSITE of the base.
    if (kDebugMode) {
      debugPrint(
        '🦎 [DEBUG] bootstrap → calling _refreshOppositeTheme '
        '(system=${_systemSettings.brightness})',
      );
    }
    unawaited(_refreshOppositeTheme(_systemSettings.brightness));
  }

  void _spawnReporter() {
    if (widget.analytics == null || widget.safeMode) return;
    // Analytics dashboard is an Agency feature. FREE / PRO licenses still
    // collect locally (so the dev can see local stats) but never upload.
    if (!_planFeatures.analyticsDashboard) {
      _planFeatures.checkAnalyticsDashboard(); // logs upgrade hint
      return;
    }
    _reporter = AnalyticsReporter(
      licenseKey: widget.licenseKey,
      config: widget.analytics!,
      db: _db,
    );
    _reporter!.start();
  }

  /// Reacts to the dev passing a new [MorphAnalyticsConfig] (toggling
  /// consent in their settings screen, for example). Implements rule 5:
  /// **immediate revocation** — stop the timer and wipe the local store as
  /// soon as `userConsent` flips from true to false.
  @override
  void didUpdateWidget(MorphProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCfg = oldWidget.analytics;
    final newCfg = widget.analytics;
    if (oldCfg == newCfg) return;

    final wasUploading = oldCfg?.canUpload ?? false;
    final isUploading = newCfg?.canUpload ?? false;

    _reporter?.dispose();
    _reporter = null;

    if (wasUploading && !isUploading) {
      // Consent revocation — stop AND clear, no questions asked.
      unawaited(_db.clearAll());
      assert(() {
        debugPrint(
          '🦎 Morph Analytics: consent revoked → '
          'local behavioral data cleared',
        );
        return true;
      }());
    }

    _spawnReporter();

    // Reflect the new config in state so descendants reading via the
    // analytics extensions see the change immediately.
    if (_state != null) {
      setState(() {
        _state = _state!.copyWith(
          analyticsConfig: newCfg,
          clearAnalyticsConfig: newCfg == null,
        );
      });
    }
  }

  /// Fetch an AI-adapted ColorScheme for the opposite of the current raw
  /// palette when [systemBrightness] demands it. No-op when the raw
  /// brightness matches the OS, when we have nothing to extract from, or
  /// when the backend fails (fallback lives in [ThemeAdapter._applyOpposite]).
  Future<void> _refreshOppositeTheme(Brightness systemBrightness) async {
    // 🔍 DEBUG — entry trace. Drop these prints once we've confirmed the
    // theme generation path fires end-to-end.
    if (kDebugMode) {
      debugPrint(
        '🦎 [DEBUG] _refreshOppositeTheme(systemBrightness=$systemBrightness) '
        'mounted=$mounted, safeMode=${widget.safeMode}, generating=$_generating, '
        'rawColors=${_rawColors == null ? "NULL" : "set"}, '
        'rawBrightness=${_rawColors?.brightness}',
      );
    }

    if (!mounted || widget.safeMode) {
      if (kDebugMode) debugPrint('🦎 [DEBUG] → bail: mounted/safeMode');
      return;
    }
    if (_generating) {
      if (kDebugMode) debugPrint('🦎 [DEBUG] → bail: already generating');
      return;
    }
    final raw = _rawColors;
    if (raw == null) {
      if (kDebugMode) debugPrint('🦎 [DEBUG] → bail: _rawColors null');
      return;
    }
    if (raw.brightness == systemBrightness) {
      if (kDebugMode) {
        debugPrint(
          '🦎 [DEBUG] → bail: no flip needed '
          '(raw.brightness=${raw.brightness} == system=$systemBrightness)',
        );
      }
      return; // no flip needed
    }

    if (kDebugMode) {
      debugPrint(
        '🦎 [DEBUG] proceeding to generate '
        '(raw=${raw.brightness}, target=$systemBrightness, '
        'source=${raw.source.name})',
      );
    }

    final targetName =
        systemBrightness == Brightness.dark ? 'dark' : 'light';
    final cacheKey =
        '${raw.toApiPayload()['background']}_$targetName';
    final cached = _paletteCache[cacheKey];
    if (cached != null && cached.isFresh) {
      if (kDebugMode) {
        debugPrint('🦎 [DEBUG] → in-memory cache HIT for $cacheKey');
      }
      _applyGenerated(cached.palette);
      return;
    }

    _generating = true;
    if (kDebugMode) {
      debugPrint('🦎 [DEBUG] → calling backend generateOppositeFromRaw…');
    }
    final result = await _themeGenerator.generateOppositeFromRaw(
      raw,
      systemBrightness,
    );
    _generating = false;
    if (!mounted || _state == null) return;
    if (result == null) {
      if (kDebugMode) {
        debugPrint(
          '🦎 Morph → API unavailable, using local fallback '
          '(base=${raw.brightness}, target=$systemBrightness)',
        );
      }
      return; // _applyOpposite's HSL fallback already kicked in via build()
    }
    _paletteCache[cacheKey] = _CachedPalette(result, DateTime.now());
    _applyGenerated(result);
    if (kDebugMode) {
      debugPrint(
        '🦎 Morph → opposite palette ready '
        '(base=${raw.brightness}, target=$systemBrightness, '
        '${result.reasoning})',
      );
    }
  }

  void _applyGenerated(GeneratedTheme result) {
    if (!mounted || _state == null) return;
    if (_state!.theme.generated == result) return;
    final adapted = _buildAdapted(_systemSettings, result);
    final newColors = _buildAdaptedColors(_systemSettings, adapted, result);
    setState(() {
      _state = _state!.copyWith(
        theme: _state!.theme.copyWith(generated: result),
        adaptedTheme: adapted,
        adaptedColors: newColors,
        // When no flip is needed (base brightness matches OS), newColors is
        // null. copyWith defaults to "keep existing" on null — explicitly
        // clear so the UI drops the previous dark palette on return to light.
        clearAdaptedColors: newColors == null,
      );
    });
  }

  /// Produces the ThemeData the app should use, given the latest OS settings
  /// and optional AI palette. Returns null when there's nothing to build
  /// from — the Theme() wrap in [build] falls back to the app's own theme.
  ThemeData? _buildAdapted(
    MorphSystemSettings settings,
    GeneratedTheme? generated,
  ) {
    final base = widget.baseTheme ?? _rawColors?.toThemeData();
    if (base == null) return null;
    return _themeAdapter.buildAdaptedTheme(base, settings, generated);
  }

  /// Builds the flat semantic color palette from [adaptedTheme]. Returns null
  /// when the brightness wasn't actually flipped (no adaptation needed) —
  /// callers fall back to their own base AppColors constants.
  MorphAdaptedColors? _buildAdaptedColors(
    MorphSystemSettings settings,
    ThemeData? adapted,
    GeneratedTheme? generated,
  ) {
    if (adapted == null) return null;
    final base = widget.baseTheme ?? _rawColors?.toThemeData();
    if (base == null) return null;
    final flipped = ThemeAdapter.brightnessOf(base) != settings.brightness;
    if (!flipped && !settings.highContrast && !settings.boldText) return null;
    return MorphAdaptedColors.fromTheme(adapted, generated: generated);
  }

  /// Boot-time summary printed once after the validator returns. Stripped
  /// from release builds via the `assert` closure trick.
  void _logPlanInfo() {
    assert(() {
      final f = _planFeatures;
      String ok(bool v, MorphPlan req) =>
          v ? '✅' : '❌ ${req.label}';
      debugPrint(
        '🦎 Morph SDK v$kMorphSdkVersion\n'
        '🦎 License: ${widget.licenseKey}\n'
        '🦎 Plan: ${_plan.label} (${_plan.dailyApiCalls}/day)\n'
        '🦎 Features:\n'
        '   Dark mode auto      : ✅\n'
        '   Recovery (basic)    : ${ok(f.interruptionRecoveryBasic, MorphPlan.free)}\n'
        '   Recovery (advanced) : ${ok(f.recoveryAdvanced, MorphPlan.professional)}\n'
        '   Grip detection      : ${ok(f.gripDetection, MorphPlan.professional)}\n'
        '   Battery-aware UI    : ${ok(f.batteryAware, MorphPlan.professional)}\n'
        '   Suggestions         : ${ok(f.suggestionEngine, MorphPlan.professional)}\n'
        '   Fatigue detection   : ${ok(f.fatigueDetection, MorphPlan.business)}\n'
        '   GPS context         : ${ok(f.gpsContext, MorphPlan.business)}\n'
        '   Analytics dashboard : ${ok(f.analyticsDashboard, MorphPlan.business)}\n'
        '   AI insights         : ${ok(f.aiInsights, MorphPlan.business)}',
      );
      return true;
    }());
  }

  bool _loggedColorSource = false;
  void _logColorSourceOnce(MorphRawColors raw) {
    assert(() {
      if (_loggedColorSource) return true;
      _loggedColorSource = true;
      debugPrint(
        '🦎 Morph color source: ${raw.source.name}\n'
        '🦎 App brightness: ${raw.brightness}\n'
        '🦎 System brightness: ${_systemSettings.brightness}',
      );
      return true;
    }());
  }

  /// Re-reads OS state, rebuilds the adapted theme and pushes into state —
  /// no-op when nothing changed so we don't stutter rebuilds.
  void _updateFromSystem() {
    if (!mounted || _state == null) return;
    final fresh = _themeAdapter.readSettings(context);
    if (fresh == _systemSettings) return;

    _systemSettings = fresh;
    // textScaleFactor bump → zoom signal for the scorer.
    if (fresh.textScaleFactor != _state!.theme.textScaleFactor) {
      _db.trackZoom(fresh.textScaleFactor);
    }
    final adapted = _buildAdapted(fresh, _state!.theme.generated);
    final newColors = _buildAdaptedColors(fresh, adapted, _state!.theme.generated);
    setState(() {
      _state = _state!.copyWith(
        systemSettings: fresh,
        adaptedTheme: adapted,
        adaptedColors: newColors,
        // Same reason as in _applyGenerated — force clear when the OS comes
        // back to the base brightness and the adapted palette is no longer
        // applicable.
        clearAdaptedColors: newColors == null,
      );
    });
    assert(() {
      debugPrint('🦎 Morph: system changed\n$fresh');
      return true;
    }());
  }

  Future<void> _analyze() async {
    if (!mounted || _state == null || widget.safeMode) return;

    final scores = await _scorer.computeScores();
    if (scores == null) return;

    final newOrder = _scorer.shouldReorder(scores, _priorities);
    final shouldScale = await _scorer.shouldScaleFont(
      threshold: widget.config.minZoomsForFontScale,
    );

    if (!mounted) return;
    setState(() {
      _state = _state!.copyWith(
        zoneOrder: newOrder ?? _state!.zoneOrder,
        fontScaleApplied: shouldScale,
        v2Enabled: true,
      );
    });
    if (newOrder != null) _reorder.apply(newOrder);

    // Behavioral upload is owned exclusively by [AnalyticsReporter] now —
    // it has its own timer and consent gate. _analyze stays local-only.
  }

  /// Called by [MorphZone] when it mounts. Lets the scorer know the
  /// zone's base priority so ties break deterministically.
  void registerZonePriority(String id, int priority) {
    _priorities[id] = priority;
  }

  void unregisterZonePriority(String id) {
    _priorities.remove(id);
  }

  @override
  void didChangePlatformBrightness() {
    if (kDebugMode) {
      debugPrint('🦎 [DEBUG] didChangePlatformBrightness fired');
    }
    if (!mounted || _state == null) {
      if (kDebugMode) {
        debugPrint('🦎 [DEBUG] → bail: mounted=$mounted, state=${_state == null ? "NULL" : "set"}');
      }
      return;
    }
    // Re-detect on the NEXT frame so MediaQuery has had a chance to
    // propagate through the tree — detect() reads from PlatformDispatcher
    // directly but other consumers rely on MediaQuery being up to date.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _state == null) return;
      final fresh = _themeAdapter.detect(context);
      final modeChanged = fresh.mode != _state!.theme.mode;
      if (kDebugMode) {
        debugPrint(
          '🦎 [DEBUG] brightness post-frame: fresh.mode=${fresh.mode}, '
          'state.mode=${_state!.theme.mode}, modeChanged=$modeChanged',
        );
      }
      if (modeChanged) {
        setState(() => _state = _state!.copyWith(theme: fresh.copyWith()));
      }
      // Re-read full settings + rebuild adapted theme.
      _updateFromSystem();
      if (modeChanged) {
        final systemBrightness =
            fresh.mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
        unawaited(_refreshOppositeTheme(systemBrightness));
      }
    });
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (!mounted || _state == null) return;
    final freshTheme = _themeAdapter.detect(context);
    if (freshTheme != _state!.theme) {
      setState(() => _state = _state!.copyWith(theme: freshTheme));
    }
    _updateFromSystem();
  }

  @override
  void didChangeMetrics() {
    // textScaleFactor changes sometimes surface here before
    // didChangeAccessibilityFeatures fires. Drive the same path.
    _updateFromSystem();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      // Render children unchanged until bootstrap completes — no flash.
      return widget.child;
    }
    // When an adapted theme exists, wrap the child in an AnimatedTheme so
    // widgets that read from InheritedTheme (Cupertino, bare Material
    // widgets) pick up the adaptation with a smooth cross-fade. Apps using
    // MaterialApp.theme should instead consume `context.morph.adaptedTheme`
    // — MaterialApp builds its own Theme that shadows this one.
    final adapted = state.adaptedTheme;
    final Widget child;
    if (adapted == null) {
      child = widget.child;
    } else if (widget.themeAnimationDuration == Duration.zero) {
      child = Theme(data: adapted, child: widget.child);
    } else {
      child = AnimatedTheme(
        data: adapted,
        duration: widget.themeAnimationDuration,
        child: widget.child,
      );
    }
    // Publish the suggestion engine + history through an inherited scope
    // so [MorphSuggestionOverlay] (placed inside MaterialApp.builder
    // by the dev) can pick them up without manual wiring.
    Widget scoped = child;
    if (_suggestionEngine != null && _historyStore != null) {
      scoped = MorphSuggestionScope(
        engine: _suggestionEngine!,
        historyStore: _historyStore!,
        child: scoped,
      );
    }

    return MorphInheritedWidget(
      state: state,
      db: _db,
      reorder: _reorder,
      registerZonePriority: registerZonePriority,
      unregisterZonePriority: unregisterZonePriority,
      onResumePosition: widget.onResumePosition,
      recovery: _recovery,
      gripDetector: _grip,
      batteryAdapter: _battery,
      fatigueDetector: _fatigue,
      gpsAdapter: _gps,
      analyticsReporter: _reporter,
      plan: _plan,
      planFeatures: _planFeatures,
      child: scoped,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MorphNavigatorObserver.instance.detach();
    _reporter?.dispose();
    _reporter = null;
    _recovery?.stop();
    _grip?.stop();
    _battery?.stop();
    _fatigue?.stop();
    _gps?.stop();
    _analysisTimer?.cancel();
    if (_state?.sessionId.isNotEmpty ?? false) {
      unawaited(_db.endSession(_state!.sessionId));
    }
    unawaited(_db.close());
    super.dispose();
  }
}

/// In-memory cache entry for a generated palette. TTL mirrors the backend's
/// 48h cache so repeated brightness toggles within a session stay cheap.
/// Persistent (cross-restart) caching is left to the backend side.
class _CachedPalette {
  final GeneratedTheme palette;
  final DateTime generatedAt;

  _CachedPalette(this.palette, this.generatedAt);

  static const _ttl = Duration(hours: 48);

  bool get isFresh => DateTime.now().difference(generatedAt) < _ttl;
}

/// InheritedWidget that lets any descendant read Morph state.
/// Reach it with `MorphInheritedWidget.of(context)` or use the
/// `context.morph` extension.
class MorphInheritedWidget extends InheritedWidget {
  final MorphState state;
  final BehaviorDB db;
  final ZoneReorder reorder;
  final void Function(String id, int priority) registerZonePriority;
  final void Function(String id) unregisterZonePriority;

  /// Optional dev-provided callback for the resume-position suggestion.
  /// Null when the dev didn't pass one — the engine then never proposes
  /// the suggestion (no fallback default would scroll the right widget
  /// for the dev anyway).
  final ResumePositionCallback? onResumePosition;

  /// Commercial feature engines — null when the dev hasn't enabled the
  /// matching flag in [MorphFeatures]. Widgets that consume them
  /// (`GripAdaptiveLayout`, `BatteryAwareTheme`, …) handle the null
  /// case by passing through to a static fallback so the dev can wrap
  /// their screens unconditionally.
  final InterruptionRecovery? recovery;
  final GripDetector? gripDetector;
  final BatteryAdapter? batteryAdapter;
  final FatigueDetector? fatigueDetector;
  final GpsContextAdapter? gpsAdapter;

  /// Outbound analytics reporter. Null when the dev didn't pass an
  /// [MorphAnalyticsConfig] (the privacy default). Exposed so devs
  /// can manually `flush()` the buffered payload — useful in dev to
  /// verify the dashboard pipeline without waiting `uploadInterval`.
  final AnalyticsReporter? analyticsReporter;

  /// Resolved subscription tier. Defaults to FREE during the brief
  /// window between widget mount and validator completion (the build
  /// guard short-circuits during that window anyway).
  final MorphPlan plan;

  /// Capability matrix derived from [plan]. Used by [PlanGate] and the
  /// `requireMorphPro` / `requireMorphAgency` extensions.
  final MorphPlanFeatures planFeatures;

  const MorphInheritedWidget({
    required this.state,
    required this.db,
    required this.reorder,
    required this.registerZonePriority,
    required this.unregisterZonePriority,
    this.onResumePosition,
    this.recovery,
    this.gripDetector,
    this.batteryAdapter,
    this.fatigueDetector,
    this.gpsAdapter,
    this.analyticsReporter,
    this.plan = MorphPlan.free,
    this.planFeatures =
        const MorphPlanFeatures(plan: MorphPlan.free),
    required super.child,
    super.key,
  });

  static MorphInheritedWidget of(BuildContext context) {
    final w = context
        .dependOnInheritedWidgetOfExactType<MorphInheritedWidget>();
    assert(w != null, 'No MorphProvider found in context');
    return w!;
  }

  static MorphInheritedWidget? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MorphInheritedWidget>();

  @override
  bool updateShouldNotify(MorphInheritedWidget old) =>
      state != old.state ||
      onResumePosition != old.onResumePosition ||
      plan != old.plan;
}
