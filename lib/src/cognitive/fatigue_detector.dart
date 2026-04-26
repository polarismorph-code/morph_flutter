import 'dart:async';

import 'package:flutter/widgets.dart';

import '../behavior/behavior_db.dart';
import 'fatigue_baseline.dart';

/// Coarse fatigue bucket. Kept for backward compatibility — new code
/// should prefer [FatigueDetector.scoreStream] for a continuous 0..100
/// signal that allows progressive UI adaptations instead of three
/// discrete steps.
enum FatigueLevel { none, medium, high }

/// A single tap event. Public so consumers can feed taps from custom
/// gesture detectors (in addition to the auto-instrumentation).
@immutable
class TapEvent {
  final DateTime timestamp;
  final bool isMissed;
  final double distance;

  const TapEvent({
    required this.timestamp,
    required this.isMissed,
    required this.distance,
  });
}

/// Estimates user cognitive fatigue from aggregate behavioral signals.
/// Operates on PATTERNS — never on content. The score is a 0..1 blend
/// of weighted signals:
///
///   • Missed-tap ratio over the last 10 taps   → 40%
///   • Typing slowdown (early vs late samples)  → 20%
///   • Tap errors (typed signal)                → 5%
///   • Typing errors (typed signal)             → 5%
///   • Navigation errors (typed signal)         → 15%
///   • Untyped retries (legacy [recordRetry])   → 5%
///   • Session duration past 30 min             → 10%
///
/// **Per-user baseline.** Once the user has completed
/// [baselineSessionCount] sessions, missed-tap and typing-slowdown
/// signals are graded against the user's personal averages, not a
/// universal threshold. A tap miss rate that's "high" for a careful
/// user can be perfectly normal for someone naturally less precise —
/// the baseline catches both.
///
/// **False-positive guards.**
///   1. The first 30 seconds of the day's first session are excluded
///      from scoring — cold or stiff fingers on the morning's first
///      tap shouldn't count as fatigue.
///   2. For 30 seconds after returning from background (notification,
///      system dialog, screen-off), retries don't accumulate. A user
///      who came back after dismissing a notification is allowed one
///      "reorientation" tap without being flagged.
///
/// **Auto-reset.** When the app stays paused for 5+ minutes, the next
/// resume rolls the buffers — the user came back fresh, the previous
/// session's fatigue shouldn't carry over.
///
/// The score recompute is debounced to ≤1Hz to avoid thrashing the
/// downstream `StreamBuilder`s.
class FatigueDetector with WidgetsBindingObserver {
  final BehaviorDB db;

  FatigueDetector({required this.db});

  /// Number of completed sessions required before the baseline is
  /// trusted. See [FatigueBaseline.isLocked].
  static const int baselineSessionCount = FatigueBaselineLimits.requiredSessions;

  // Buffers — sliding windows of recent activity.
  static const int _maxTaps = 50;
  static const int _maxTypingSamples = 30;
  static const int _highScore = 70;
  static const int _mediumScore = 40;

  // False-positive guards — see class doc.
  static const Duration _coldStartWindow = Duration(seconds: 30);
  static const Duration _postResumeIgnoreWindow = Duration(seconds: 30);

  /// How long the app must stay paused before the next resume triggers
  /// an auto-reset. Below this, the same session continues.
  static const Duration _autoResetIdle = Duration(minutes: 5);

  final List<TapEvent> _tapEvents = [];
  final List<double> _typingSpeeds = [];

  // Typed error counters — see [recordTapError], [recordTypingError],
  // [recordNavigationError]. Untyped [recordRetry] feeds [_legacyRetries].
  int _tapErrors = 0;
  int _typingErrors = 0;
  int _navigationErrors = 0;
  int _legacyRetries = 0;

  DateTime? _sessionStart;
  DateTime? _lastResumeAt;
  DateTime? _lastPauseAt;

  // Set the first time the day's first session is started in
  // [startSession] — used to gate the cold-start window.
  bool _isFirstSessionToday = false;

  Timer? _analysisDebounce;

  FatigueBaseline _baseline = FatigueBaseline.empty;
  FatigueBaseline get baseline => _baseline;

  // Score state — the 0..1 raw score is the source of truth; both
  // [stream] and [scoreStream] are derived from it.
  double _score = 0;
  FatigueLevel _level = FatigueLevel.none;

  final _levelController = StreamController<FatigueLevel>.broadcast();
  final _scoreController = StreamController<double>.broadcast();

  /// Bucketed level stream (none/medium/high). Backward-compat default.
  Stream<FatigueLevel> get stream => _levelController.stream;

  /// Continuous 0..100 score stream. Use this when the UI can adapt
  /// progressively — e.g. interpolating field scale, animation
  /// duration, or vibration intensity smoothly.
  Stream<double> get scoreStream => _scoreController.stream;

  /// Last bucketed level emitted.
  FatigueLevel get currentLevel => _level;

  /// Last continuous score emitted (0..100).
  double get currentScore => _score * 100;

  /// True when the user has been observed long enough for the
  /// per-baseline grading to take effect.
  bool get hasBaseline => _baseline.isLocked;

  /// Starts a fresh session. Loads the persisted baseline (if any) and
  /// clears all buffers. Call from [MorphProvider] on bootstrap.
  Future<void> startSession() async {
    _sessionStart = DateTime.now();
    _tapEvents.clear();
    _typingSpeeds.clear();
    _tapErrors = 0;
    _typingErrors = 0;
    _navigationErrors = 0;
    _legacyRetries = 0;
    _score = 0;
    _level = FatigueLevel.none;
    _baseline = await _loadBaseline();
    _isFirstSessionToday = await _resolveFirstSessionToday();
    _emit();

    // Subscribe to lifecycle on the first session — idempotent across
    // resets.
    WidgetsBinding.instance.addObserver(this);
  }

  /// Manually reset the detector — typically wired to a "Reset" button
  /// on the fatigue banner. Async because it reloads the baseline.
  Future<void> resetFatigue() => startSession();

  // ─── Public ingestion API ──────────────────────────────────────────────

  /// Records a tap. Pass [position], [targetCenter] and [targetSize]
  /// when available to enable miss detection — when [targetSize] is
  /// `Size.zero`, the tap is recorded as on-target.
  void recordTap({
    required Offset position,
    required Offset targetCenter,
    required Size targetSize,
  }) {
    final distance = (position - targetCenter).distance;
    // Half the average dimension is "near enough to count as on-target".
    final maxDistance = (targetSize.width + targetSize.height) / 4;
    final isMissed = targetSize == Size.zero ? false : distance > maxDistance;

    _tapEvents.add(TapEvent(
      timestamp: DateTime.now(),
      isMissed: isMissed,
      distance: distance,
    ));
    if (_tapEvents.length > _maxTaps) _tapEvents.removeAt(0);
    _scheduleAnalyze();
  }

  /// Records a keystroke. Use the time delta between consecutive calls
  /// to estimate typing speed.
  void recordKeystroke() {
    final now = DateTime.now();
    if (_tapEvents.isNotEmpty) {
      final last = _tapEvents.last;
      final intervalMs = now.difference(last.timestamp).inMilliseconds;
      if (intervalMs > 0 && intervalMs < 5000) {
        _typingSpeeds.add(1000 / intervalMs); // keystrokes per second
        if (_typingSpeeds.length > _maxTypingSamples) {
          _typingSpeeds.removeAt(0);
        }
      }
    }
    _scheduleAnalyze();
  }

  /// Records a tap error — the user tapped where there was no target
  /// or hit the wrong target. Lighter weight than a missed tap.
  void recordTapError() {
    if (_isInPostResumeWindow()) return;
    _tapErrors++;
    _scheduleAnalyze();
  }

  /// Records a typing correction — the user backspaced and retyped a
  /// word. Common during fatigue but also during normal editing — kept
  /// at low weight in the score.
  void recordTypingError() {
    if (_isInPostResumeWindow()) return;
    _typingErrors++;
    _scheduleAnalyze();
  }

  /// Records a navigation error — back-then-forward through the same
  /// pair of routes within a few seconds. Strong fatigue signal because
  /// it reveals the user lost track of where they wanted to go.
  void recordNavigationError() {
    if (_isInPostResumeWindow()) return;
    _navigationErrors++;
    _scheduleAnalyze();
  }

  /// Generic retry signal — kept for backward compatibility with the
  /// pre-0.1.2 API. New code should prefer the typed methods above.
  @Deprecated('Use recordTapError / recordTypingError / recordNavigationError')
  void recordRetry() {
    if (_isInPostResumeWindow()) return;
    _legacyRetries++;
    _scheduleAnalyze();
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = DateTime.now();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lastPauseAt = now;
    } else if (state == AppLifecycleState.resumed) {
      _lastResumeAt = now;
      final pausedAt = _lastPauseAt;
      if (pausedAt != null && now.difference(pausedAt) >= _autoResetIdle) {
        // Long idle — fresh session.
        unawaited(startSession());
      }
    }
  }

  // ─── Score computation ─────────────────────────────────────────────────

  void _scheduleAnalyze() {
    _analysisDebounce?.cancel();
    _analysisDebounce = Timer(const Duration(milliseconds: 800), _analyze);
  }

  void _analyze() {
    // Hard suppression — the score stays at 0 inside the cold-start
    // window even if signals come in, so banners can't fire on the
    // first 30s of the day's first session.
    if (_isInColdStartWindow()) {
      _score = 0;
    } else {
      _score = _computeScore();
    }
    final newLevel = _bucket(_score);
    final scoreOutOf100 = _score * 100;

    final levelChanged = newLevel != _level;
    if (levelChanged) _level = newLevel;
    _emit(levelChanged: levelChanged, score: scoreOutOf100);

    assert(() {
      debugPrint(
        '🦎 Morph fatigue: score ${scoreOutOf100.toStringAsFixed(1)} '
        '→ ${_level.name} '
        '${hasBaseline ? '[per-baseline]' : '[universal]'}',
      );
      return true;
    }());
  }

  void _emit({bool levelChanged = true, double? score}) {
    if (levelChanged) _levelController.add(_level);
    _scoreController.add(score ?? _score * 100);
  }

  double _computeScore() {
    var score = 0.0;

    // Signal 1 — recent missed taps (graded against baseline if locked).
    if (_tapEvents.length >= 10) {
      final recent = _tapEvents.sublist(_tapEvents.length - 10);
      final missed = recent.where((e) => e.isMissed).length;
      final ratio = missed / 10;
      final normalised = _gradeMissedTaps(ratio);
      score += normalised * 0.40;
    }

    // Signal 2 — typing slowdown (graded against baseline typing speed).
    if (_typingSpeeds.length >= 10) {
      final early = _typingSpeeds.take(5).reduce((a, b) => a + b) / 5;
      final lateSamples = _typingSpeeds.sublist(_typingSpeeds.length - 5);
      final late = lateSamples.reduce((a, b) => a + b) / 5;
      final reference = hasBaseline && _baseline.typingSpeed > 0
          ? _baseline.typingSpeed
          : (early > 0 ? early : 1);
      if (reference > 0) {
        final slowdown = (reference - late) / reference;
        score += slowdown.clamp(0.0, 1.0) * 0.20;
      }
    }

    // Signals 3a/3b/3c — typed errors. Each saturates after 5 events.
    score += (_tapErrors / 5).clamp(0.0, 1.0) * 0.05;
    score += (_typingErrors / 5).clamp(0.0, 1.0) * 0.05;
    score += (_navigationErrors / 5).clamp(0.0, 1.0) * 0.15;

    // Signal 3d — legacy untyped retries.
    score += (_legacyRetries / 5).clamp(0.0, 1.0) * 0.05;

    // Signal 4 — long session.
    if (_sessionStart != null) {
      final minutes =
          DateTime.now().difference(_sessionStart!).inMinutes.toDouble();
      if (minutes > 30) {
        score += ((minutes - 30) / 60).clamp(0.0, 1.0) * 0.10;
      }
    }

    return score.clamp(0.0, 1.0);
  }

  /// Maps an observed missed-tap ratio onto a 0..1 contribution. With a
  /// locked baseline, the user's own ratio is the zero point and the
  /// score scales up to 1 at +25 percentage points above baseline.
  /// Without a baseline, falls back to the universal "missed/10" rule.
  double _gradeMissedTaps(double ratio) {
    if (!hasBaseline) return ratio.clamp(0.0, 1.0);
    final delta = ratio - _baseline.missedTapRatio;
    if (delta <= 0) return 0;
    return (delta / 0.25).clamp(0.0, 1.0);
  }

  FatigueLevel _bucket(double score) {
    if (score * 100 >= _highScore) return FatigueLevel.high;
    if (score * 100 >= _mediumScore) return FatigueLevel.medium;
    return FatigueLevel.none;
  }

  bool _isInColdStartWindow() {
    if (!_isFirstSessionToday) return false;
    final start = _sessionStart;
    if (start == null) return false;
    return DateTime.now().difference(start) < _coldStartWindow;
  }

  bool _isInPostResumeWindow() {
    final resumed = _lastResumeAt;
    if (resumed == null) return false;
    return DateTime.now().difference(resumed) < _postResumeIgnoreWindow;
  }

  // ─── Baseline persistence ──────────────────────────────────────────────

  Future<FatigueBaseline> _loadBaseline() async {
    final raw = db.readPreference('fatigue.baseline');
    if (raw is Map) return FatigueBaseline.fromMap(raw);
    return FatigueBaseline.empty;
  }

  /// Folds the current session's stats into the baseline, but only if
  /// the baseline isn't yet locked. Locked baselines never absorb new
  /// data so a chronically-fatigued user can't drift their own normal
  /// upward and silence the detector.
  Future<void> _accrueBaseline() async {
    if (_baseline.isLocked) return;
    if (_tapEvents.length < 10) return; // not enough data this session
    final missedRatio = _tapEvents.where((e) => e.isMissed).length /
        _tapEvents.length;
    final avgSpeed = _typingSpeeds.isEmpty
        ? 0.0
        : _typingSpeeds.reduce((a, b) => a + b) / _typingSpeeds.length;
    _baseline = _baseline.merge(
      missedTapRatio: missedRatio,
      typingSpeed: avgSpeed,
    );
    await _saveBaselineToDb();
  }

  Future<void> _saveBaselineToDb() async {
    // [BehaviorDB] does not yet expose a typed setter for the baseline;
    // we write through the generic prefs box at a stable key. Cleared
    // by [BehaviorDB.clearAll] when the user revokes consent.
    await db.savePreference('fatigue.baseline', _baseline.toMap());
  }

  Future<bool> _resolveFirstSessionToday() async {
    final raw = db.readPreference('fatigue.lastSessionDate');
    final today = _dateKey(DateTime.now());
    final isFirst = raw != today;
    if (isFirst) {
      await db.savePreference('fatigue.lastSessionDate', today);
    }
    return isFirst;
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> stop() async {
    _analysisDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await _accrueBaseline();
    await _levelController.close();
    await _scoreController.close();
  }
}
