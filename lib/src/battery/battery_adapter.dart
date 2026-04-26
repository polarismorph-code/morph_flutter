import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import '../behavior/behavior_db.dart';

/// Bucketed battery state. Drives [BatteryAwareWidget] and
/// [BatteryAwareTheme] without exposing raw percentages to consumers
/// (they don't need them — they just want to render less when there's
/// less juice).
enum BatteryMode { normal, medium, low, critical }

/// Read-only battery telemetry. Polls the OS for the level, listens to
/// charging-state changes, emits a coarse [BatteryMode] every time the
/// bucket flips. Morph never *controls* power — only reacts to it.
class BatteryAdapter {
  final BehaviorDB db;

  BatteryAdapter({required this.db});

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

  final _modeController = StreamController<BatteryMode>.broadcast();

  Stream<BatteryMode> get modeStream => _modeController.stream;
  BatteryMode get currentMode => _computeMode(_level, _state);

  /// Current raw percentage. Exposed publicly so the suggestion check in
  /// [SuggestionEngine] can include it in the suggestion's metadata for
  /// the dashboard.
  int get currentLevel => _level;

  Future<void> start() async {
    _battery = Battery();
    try {
      _level = await _battery!.batteryLevel;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🦎 Morph battery: initial read failed: $e');
      }
    }
    _stateSub = _battery!.onBatteryStateChanged.listen(_onStateChanged);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    _emit();
  }

  void stop() {
    _stateSub?.cancel();
    _stateSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _modeController.close();
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

  void _onStateChanged(BatteryState state) {
    _state = state;
    _emit();
  }

  void _emit() {
    final mode = currentMode;
    _modeController.add(mode);
    assert(() {
      debugPrint('🦎 Morph battery: $_level% → ${mode.name}');
      return true;
    }());
  }

  BatteryMode _computeMode(int level, BatteryState state) {
    if (state == BatteryState.charging) return BatteryMode.normal;
    if (level <= criticalLevel) return BatteryMode.critical;
    if (level <= lowLevel) return BatteryMode.low;
    if (level <= mediumLevel) return BatteryMode.medium;
    return BatteryMode.normal;
  }
}
