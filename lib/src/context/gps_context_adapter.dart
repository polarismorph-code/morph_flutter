import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Coarse movement classification — derived from speed + GPS accuracy +
/// (optionally) an accelerometer fallback when the satellite signal is
/// degraded.
enum MovementContext { stationary, walking, cycling, vehicle, unknown }

/// Receives location updates from the host app's *existing* GPS pipeline
/// and exposes a coarse [MovementContext] stream. **Morph never
/// requests location permission itself** — the dev pipes their own
/// `Position` updates in via [onLocationUpdate].
///
/// **Threshold mapping** — speeds are in km/h. Hysteresis bands prevent
/// oscillation at the boundaries: each mode has an *entry* threshold
/// (the speed it takes to flip *into* the mode) higher than its *exit*
/// threshold (the speed it takes to flip *out*). A user steady at
/// 7 km/h won't flicker between walking and cycling on every fix.
///
///   • stationary entry: < 1.5     exit: ≥ 2.5
///   • walking    entry: ≥ 2.5     exit: ≥ 8 (up) or < 1.5 (down)
///   • cycling    entry: ≥ 8       exit: ≥ 27 (up) or < 6 (down)
///   • vehicle    entry: ≥ 27      exit: < 23
///
/// **Accuracy gate.** Updates with `accuracy > 50m` don't drive
/// classification on their own — they trigger the tunnel-mode path
/// described below.
///
/// **Tunnel mode.** When a series of updates arrive with degraded
/// accuracy (or no updates arrive at all), the adapter keeps emitting
/// the last *good* context for [tunnelGracePeriod]. Past that, it
/// falls back to [MovementContext.unknown]. Going through a tunnel or
/// under a bridge no longer pops the UI back to a default state.
///
/// **Accelerometer fallback.** When the adapter is `start()`ed it also
/// subscribes to the accelerometer. If GPS reports `stationary` but
/// the accelerometer detects sustained train-like vibration for
/// [_vibrationConfirmWindow], the emitted context is upgraded to
/// `vehicle`. Useful in metros, trains, and underground parking
/// where GPS is unreliable for minutes at a time.
class GpsContextAdapter {
  /// How long after the last good fix the adapter keeps reporting the
  /// previous context before falling back to [MovementContext.unknown].
  /// Tuned for typical urban tunnels (~10–20s) plus a margin.
  static const Duration tunnelGracePeriod = Duration(seconds: 30);

  // Hysteresis bands. Numbers chosen to be wider than the typical
  // measurement noise on a phone GPS at street level.
  static const double _stationaryUpper = 2.5;
  static const double _walkingUpper = 8;
  static const double _cyclingUpper = 27;
  static const double _stationaryReentry = 1.5;
  static const double _walkingReentry = 6;
  static const double _cyclingReentry = 23;

  // Accelerometer fusion thresholds.
  static const double _vibrationVarianceThreshold = 0.6; // m²/s⁴
  static const Duration _vibrationConfirmWindow = Duration(seconds: 5);
  static const int _accelSampleCap = 60; // ~3 s at 20 Hz

  MovementContext _context = MovementContext.stationary;
  MovementContext _lastGoodContext = MovementContext.stationary;
  DateTime? _lastGoodFixAt;
  Timer? _tunnelTimer;

  // Accelerometer state.
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final List<double> _accelMagnitudes = [];
  DateTime? _vibrationStartedAt;

  final _controller = StreamController<MovementContext>.broadcast();

  /// True when the most recent emit was driven by the
  /// [tunnelGracePeriod] held over a degraded-accuracy update.
  bool get isHoldingThroughTunnel {
    final last = _lastGoodFixAt;
    if (last == null) return false;
    final age = DateTime.now().difference(last);
    return age > Duration.zero && age < tunnelGracePeriod;
  }

  Stream<MovementContext> get stream => _controller.stream;
  MovementContext get currentContext => _context;

  /// Subscribes to the accelerometer for the train-detection fallback.
  /// Idempotent — calling twice is a no-op.
  void start() {
    if (_accelSub != null) return;
    // sensors_plus 7.x — `accelerometerEventStream` is the supported
    // accessor; the deprecation note guards 4.x→7.x users while we
    // sit on the bridge.
    try {
      // ignore: deprecated_member_use
      _accelSub = accelerometerEvents.listen(
        _onAccel,
        onError: (Object e) {
          if (kDebugMode) {
            debugPrint('🦎 Morph GPS: accelerometer error: $e');
          }
        },
      );
    } catch (_) {
      // Sensor not available (iOS simulator, some emulators) —
      // fallback fusion is silently skipped.
    }
  }

  /// Pipe an update from your existing GPS subscription. The dev does:
  /// ```dart
  /// final adapter =
  ///     MorphInheritedWidget.of(ctx).gpsAdapter;
  /// adapter?.onLocationUpdate(
  ///   speedKmh: pos.speed * 3.6,
  ///   accuracy: pos.accuracy,
  /// );
  /// ```
  void onLocationUpdate({
    required double speedKmh,
    required double accuracy,
  }) {
    // Bad fix? Trigger the tunnel-mode path — keep emitting the last
    // good context until the grace period expires.
    if (accuracy > 50) {
      _enterTunnelMode();
      return;
    }

    final next = _classifyWithHysteresis(speedKmh);
    _lastGoodFixAt = DateTime.now();
    _lastGoodContext = next;
    _cancelTunnelTimer();
    _emit(next, speedKmh: speedKmh, accuracy: accuracy);
  }

  void _enterTunnelMode() {
    // First bad fix in this run? Schedule the unknown-fallback for
    // tunnelGracePeriod into the future. Subsequent bad fixes don't
    // reset the timer — the clock starts at the last *good* fix, not
    // the last update.
    if (_tunnelTimer != null) return;
    _tunnelTimer = Timer(tunnelGracePeriod, () {
      _emit(MovementContext.unknown);
    });
    if (kDebugMode) {
      debugPrint('🦎 Morph GPS: degraded accuracy — holding $_lastGoodContext');
    }
  }

  void _cancelTunnelTimer() {
    _tunnelTimer?.cancel();
    _tunnelTimer = null;
  }

  /// Speed → context with asymmetric thresholds. The current context
  /// influences the decision so a steady speed at the boundary doesn't
  /// oscillate.
  MovementContext _classifyWithHysteresis(double speedKmh) {
    switch (_context) {
      case MovementContext.stationary:
        // Need to clearly EXIT stationary before becoming walking.
        if (speedKmh < _stationaryUpper) return MovementContext.stationary;
        if (speedKmh < _walkingUpper) return MovementContext.walking;
        if (speedKmh < _cyclingUpper) return MovementContext.cycling;
        return MovementContext.vehicle;

      case MovementContext.walking:
        if (speedKmh < _stationaryReentry) return MovementContext.stationary;
        if (speedKmh < _walkingUpper) return MovementContext.walking;
        if (speedKmh < _cyclingUpper) return MovementContext.cycling;
        return MovementContext.vehicle;

      case MovementContext.cycling:
        if (speedKmh < _walkingReentry) return MovementContext.walking;
        if (speedKmh < _cyclingUpper) return MovementContext.cycling;
        return MovementContext.vehicle;

      case MovementContext.vehicle:
        // Once in a vehicle, keep the mode unless we drop well below
        // the bike→car boundary — saves us from a brief red light
        // briefly snapping back to "cycling".
        if (speedKmh < _walkingReentry) return MovementContext.walking;
        if (speedKmh < _cyclingReentry) return MovementContext.cycling;
        return MovementContext.vehicle;

      case MovementContext.unknown:
        // Cold start — apply the entry-thresholds path (same as
        // stationary case but distinguished for clarity).
        if (speedKmh < _stationaryUpper) return MovementContext.stationary;
        if (speedKmh < _walkingUpper) return MovementContext.walking;
        if (speedKmh < _cyclingUpper) return MovementContext.cycling;
        return MovementContext.vehicle;
    }
  }

  // ─── Accelerometer fusion ────────────────────────────────────────────

  void _onAccel(AccelerometerEvent e) {
    final magnitude = (e.x * e.x + e.y * e.y + e.z * e.z);
    _accelMagnitudes.add(magnitude);
    if (_accelMagnitudes.length > _accelSampleCap) {
      _accelMagnitudes.removeAt(0);
    }
    if (_accelMagnitudes.length < _accelSampleCap) return;

    final variance = _variance(_accelMagnitudes);
    final isVibrating = variance > _vibrationVarianceThreshold;

    if (isVibrating) {
      _vibrationStartedAt ??= DateTime.now();
      final since = DateTime.now().difference(_vibrationStartedAt!);
      // Promote to vehicle only after sustained vibration on a context
      // that GPS thinks is stationary — otherwise vehicle is already
      // emitted by the speed path and the fusion would be noise.
      if (since >= _vibrationConfirmWindow &&
          _context == MovementContext.stationary) {
        _emit(MovementContext.vehicle, source: 'accelerometer');
      }
    } else {
      _vibrationStartedAt = null;
    }
  }

  double _variance(List<double> samples) {
    if (samples.isEmpty) return 0;
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final sq = samples.fold<double>(
      0,
      (sum, x) => sum + (x - mean) * (x - mean),
    );
    return sq / samples.length;
  }

  // ─── Emission ────────────────────────────────────────────────────────

  void _emit(
    MovementContext next, {
    double? speedKmh,
    double? accuracy,
    String source = 'gps',
  }) {
    if (next == _context) return;
    _context = next;
    _controller.add(next);
    assert(() {
      final extras = [
        if (speedKmh != null) '${speedKmh.toStringAsFixed(1)} km/h',
        if (accuracy != null) '±${accuracy.toStringAsFixed(0)}m',
        if (source != 'gps') 'via $source',
      ].join(', ');
      debugPrint(
        '🦎 Morph GPS: ${next.name}'
        '${extras.isNotEmpty ? ' ($extras)' : ''}',
      );
      return true;
    }());
  }

  void stop() {
    _cancelTunnelTimer();
    _accelSub?.cancel();
    _accelSub = null;
    _accelMagnitudes.clear();
    _vibrationStartedAt = null;
    _controller.close();
  }
}
