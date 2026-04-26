import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import '../behavior/behavior_db.dart';
import 'battery_session_snapshot.dart';
import 'charge_pattern_predictor.dart';

/// Bucketed battery state. Drives [BatteryAwareWidget] and
/// [BatteryAwareTheme] without exposing raw percentages to consumers
/// (they don't need them — they just want to render less when there's
/// less juice).
enum BatteryMode { normal, medium, low, critical }

/// Read-only battery telemetry. Polls the OS for the level, listens to
/// charging-state changes, emits a coarse [BatteryMode] every time the
/// bucket flips. Morph never *controls* power — only reacts to it.
///
/// Two data trails are written to [BehaviorDB] while the adapter runs:
///   • **Sessions** — one entry per foreground run (start/end level,
///     duration, was-charging flag). Powers [getSessionStats] for dev
///     dashboards.
///   • **Charge events** — every transition INTO `BatteryState.charging`
///     is timestamped. Powers [ChargePatternPredictor], which biases the
///     emitted mode toward `medium` when the user is approaching their
///     usual charge window without yet being plugged in.
class BatteryAdapter {
  final BehaviorDB db;

  /// Stable id of the active session (passed in by the provider so the
  /// battery row joins to the same session row in `cml_sessions`). May
  /// be empty in safe-mode or tests; sessions are still recorded.
  final String sessionId;

  BatteryAdapter({
    required this.db,
    this.sessionId = '',
  });

  // Bucket thresholds, in percent.
  static const int criticalLevel = 10;
  static const int lowLevel = 20;
  static const int mediumLevel = 50;

  // How often to re-poll the level — `onBatteryStateChanged` only fires
  // on charging state transitions, so we poll for percentage decay.
  static const Duration _pollInterval = Duration(seconds: 60);

  Battery? _battery;
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _pollTimer;

  int _level = 100;
  BatteryState _state = BatteryState.full;

  // Set the first time the device transitions INTO charging during a
  // session. Persisted at session end so the dev can filter "natural
  // drain" (`wasCharging == false`) when computing energy gains.
  bool _wasCharging = false;

  // Session telemetry — captured at the first successful read of
  // [batteryLevel] in [start], finalised in [stop].
  int? _sessionStartTime;
  int? _sessionStartLevel;

  // Pattern predictor — null when the dev disables prediction or when no
  // charge events have been recorded yet. Refreshed on each poll tick.
  final ChargePatternPredictor _predictor = ChargePatternPredictor();
  bool _predictorActive = false;

  final _modeController = StreamController<BatteryMode>.broadcast();

  Stream<BatteryMode> get modeStream => _modeController.stream;
  BatteryMode get currentMode => _resolveMode();

  /// Current raw percentage. Exposed publicly so the suggestion check in
  /// `SuggestionEngine` can include it in the suggestion's metadata for
  /// the dashboard.
  int get currentLevel => _level;

  /// True when the device is currently charging (wired or wireless).
  bool get isCharging =>
      _state == BatteryState.charging || _state == BatteryState.full;

  /// True when the predictor inferred that the user is approaching a
  /// typical charge window. Read-only — set internally on each tick.
  bool get isApproachingChargeWindow => _predictorActive;

  Future<void> start() async {
    _battery = Battery();
    try {
      _level = await _battery!.batteryLevel;
      _sessionStartTime = DateTime.now().millisecondsSinceEpoch;
      _sessionStartLevel = _level;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🦎 Morph battery: initial read failed: $e');
      }
    }
    try {
      _state = await _battery!.batteryState;
    } catch (_) {
      // Stay on the default `full` — better to over-report battery than
      // surprise-degrade UX on a transient platform error.
    }
    _wasCharging = isCharging;

    _stateSub = _battery!.onBatteryStateChanged.listen(_onStateChanged);
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      await _poll();
      await _refreshPrediction();
    });
    await _refreshPrediction();
    _emit();
  }

  Future<void> stop() async {
    _stateSub?.cancel();
    _stateSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _flushSession();
    await _modeController.close();
  }

  Future<void> _flushSession() async {
    final start = _sessionStartTime;
    final startLevel = _sessionStartLevel;
    if (start == null || startLevel == null) return;
    final snapshot = BatterySessionSnapshot(
      sessionId: sessionId,
      startTime: start,
      endTime: DateTime.now().millisecondsSinceEpoch,
      batteryAtStart: startLevel,
      batteryAtEnd: _level,
      wasCharging: _wasCharging,
    );
    if (snapshot.durationSeconds < 1) return;
    await db.saveBatterySession(snapshot.toMap());
    _sessionStartTime = null;
    _sessionStartLevel = null;
  }

  Future<void> _poll() async {
    final batt = _battery;
    if (batt == null) return;
    try {
      final next = await batt.batteryLevel;
      if (next == _level) return;
      _level = next;
      _emit();
    } catch (_) {
      // OS occasionally throws on rapid polling — ignore, retry next tick.
    }
  }

  Future<void> _refreshPrediction() async {
    try {
      final events = await db.getChargeEvents(
        lookback: const Duration(days: 14),
      );
      _predictor.ingest(events);
      final next = _predictor.isApproachingChargeWindow(DateTime.now());
      if (next != _predictorActive) {
        _predictorActive = next;
        _emit();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🦎 Morph battery: prediction refresh failed: $e');
      }
    }
  }

  void _onStateChanged(BatteryState state) {
    final wasCharging = isCharging;
    _state = state;
    if (isCharging) _wasCharging = true;

    // Record only the LEADING edge of a charge — duplicate samples while
    // already charging would clutter the predictor's input.
    if (!wasCharging && isCharging) {
      unawaited(db.saveChargeEvent(batteryLevel: _level));
    }
    _emit();
  }

  void _emit() {
    final mode = currentMode;
    _modeController.add(mode);
    assert(() {
      debugPrint(
        '🦎 Morph battery: $_level% → ${mode.name}'
        '${_predictorActive ? ' (predicted charge soon)' : ''}',
      );
      return true;
    }());
  }

  // ─── Mode resolution ───────────────────────────────────────────────────

  /// Public bucket calculator — runs the same rules as [_resolveMode] but
  /// with an explicit input. Useful for tests and the dashboard.
  static BatteryMode bucketFor({
    required int level,
    required bool charging,
  }) {
    if (charging) return BatteryMode.normal;
    if (level <= criticalLevel) return BatteryMode.critical;
    if (level <= lowLevel) return BatteryMode.low;
    if (level <= mediumLevel) return BatteryMode.medium;
    return BatteryMode.normal;
  }

  BatteryMode _resolveMode() {
    final base = bucketFor(level: _level, charging: isCharging);
    // Pattern learning lift — when the predictor says the user is about
    // to charge anyway, but the level is still in the `normal` band,
    // we proactively suggest `medium` so the device arrives at the
    // charger with a few extra percent. We never *raise* the bucket
    // beyond `medium` from a prediction alone.
    if (_predictorActive && base == BatteryMode.normal && !isCharging) {
      return BatteryMode.medium;
    }
    return base;
  }

  // ─── Aggregated session stats ──────────────────────────────────────────

  /// Returns aggregated drain stats over a [lookback] window (default
  /// 14 days). Filters out sessions where the device was charging — the
  /// caller wants natural drain numbers, not artefacts of a USB cable.
  Future<BatterySessionStats> getSessionStats({
    Duration lookback = const Duration(days: 14),
  }) async {
    final raw = await db.getBatterySessions(lookback: lookback);
    if (raw.isEmpty) return BatterySessionStats.empty;

    final snapshots = raw.map(BatterySessionSnapshot.fromMap).toList();
    final naturalDrain = <double>[];
    final durations = <int>[];
    var totalSeconds = 0;
    for (final s in snapshots) {
      totalSeconds += s.durationSeconds;
      durations.add(s.durationSeconds);
      if (!s.wasCharging) {
        final dpm = s.drainPerMinute;
        if (dpm != null && dpm >= 0) naturalDrain.add(dpm);
      }
    }

    durations.sort();
    final medianSeconds = durations.isEmpty
        ? 0
        : durations[durations.length ~/ 2];

    return BatterySessionStats(
      sessionCount: snapshots.length,
      totalSeconds: totalSeconds,
      averageDrainPerMinute: naturalDrain.isEmpty
          ? null
          : naturalDrain.reduce((a, b) => a + b) / naturalDrain.length,
      medianSessionSeconds: medianSeconds,
    );
  }
}
