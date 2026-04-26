import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../behavior/behavior_db.dart';

/// Inferred dominant hand of the current grip.
enum GripHand {
  /// Device leans right → user is gripping with the LEFT hand.
  left,

  /// Device leans left → user is gripping with the RIGHT hand.
  right,

  /// Held centered or two-handed — no clear lateral tilt.
  both,

  /// Not enough samples yet, or signal is too noisy to call.
  unknown,
}

/// Coarse posture inference — used as a guard against repositioning while
/// the device is moving (walking, in-pocket).
enum GripPosture { portrait, landscape, moving, unknown }

/// Reads the accelerometer to infer left/right grip and an approximate
/// posture (portrait, landscape, moving). Subscribers (typically
/// [GripAdaptiveLayout]) react to [handStream] to reposition CTAs on the
/// dominant side.
///
/// Detection rule: a sustained positive X-axis tilt means the device is
/// leaning right → user is probably gripping with the LEFT hand. The
/// signal is smoothed across a 20-sample sliding window to ignore micro
/// motion.
///
/// **Persistence:** when [persistPreference] is true (the default), the
/// last detected hand is stored in [BehaviorDB]. On the next session
/// [start] reads that value and seeds the detector so the UI lands on
/// the right alignment immediately, AND a matching live signal is
/// accepted after only [_eagerMinSamples] samples instead of
/// [_minSamples] (prior-aware fast lock). A signal that contradicts the
/// stored preference still goes through the full [_minSamples] window —
/// switching hands mid-session works as before.
class GripDetector {
  final BehaviorDB db;

  /// When true, store the detected hand in [BehaviorDB] and read it back
  /// on the next [start] to seed the initial value + bias the lock.
  final bool persistPreference;

  GripDetector({
    required this.db,
    this.persistPreference = true,
  });

  static const int _sampleWindow = 20;
  static const int _minSamples = 10;
  static const int _eagerMinSamples = 5;
  static const double _tiltThreshold = 1.5; // m/s² on the X axis

  StreamSubscription<AccelerometerEvent>? _accelSub;

  GripHand _hand = GripHand.unknown;
  GripPosture _posture = GripPosture.unknown;
  GripHand? _priorHand;
  final List<double> _xSamples = [];

  final _handController = StreamController<GripHand>.broadcast();

  /// Live stream of detected hands. Replays the latest value via
  /// [GripAdaptiveLayout]'s `initialData`.
  Stream<GripHand> get handStream => _handController.stream;

  GripHand get currentHand => _hand;
  GripPosture get currentPosture => _posture;

  /// Starts listening to the accelerometer. When [persistPreference] is
  /// true, also reads the previously stored hand from [BehaviorDB] and
  /// uses it as a prior — see the class docs for the lock-window logic.
  ///
  /// Safe to `unawaited()` — the prior is applied opportunistically and
  /// missing it just means the first detection follows the regular
  /// [_minSamples] path.
  Future<void> start() async {
    if (persistPreference) {
      final stored = db.readPreference('grip.hand');
      if (stored is String) {
        final parsed = _parseHand(stored);
        if (parsed != GripHand.unknown) {
          _priorHand = parsed;
          _hand = parsed;
          // Replay so subscribers attached before the first sample see
          // the prior immediately.
          _handController.add(parsed);
        }
      }
    }

    // sensors_plus 4.x: `accelerometerEvents` is the public stream;
    // 5.x renames it to `accelerometerEventStream()`. We pin to 4.x in
    // pubspec, so the deprecation note is informational only.
    //
    // The whole subscription is guarded — the platform channel throws
    // `MissingPluginException` in unit tests and on devices without an
    // accelerometer. The persistence-driven prior is already applied
    // above, so failing here just disables live detection without
    // erasing the seeded state.
    try {
      // ignore: deprecated_member_use
      _accelSub ??= accelerometerEvents.listen(
        _onAccel,
        onError: (Object e) {
          if (kDebugMode) {
            debugPrint('🦎 Morph grip: accelerometer error: $e');
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🦎 Morph grip: accelerometer unavailable, '
            'persisted prior is still active ($e)');
      }
    }
  }

  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _xSamples.clear();
    _handController.close();
  }

  void _onAccel(AccelerometerEvent e) {
    _xSamples.add(e.x);
    if (_xSamples.length > _sampleWindow) _xSamples.removeAt(0);

    // Lock window depends on whether the candidate matches the prior.
    final avgX = _xSamples.isEmpty
        ? 0.0
        : _xSamples.reduce((a, b) => a + b) / _xSamples.length;
    final candidate = _detectHand(avgX);
    final required =
        (_priorHand != null && candidate == _priorHand) ? _eagerMinSamples : _minSamples;
    if (_xSamples.length < required) return;

    final newHand = candidate;
    final newPosture = _detectPosture(e);

    if (newHand == _hand && newPosture == _posture) return;
    _hand = newHand;
    _posture = newPosture;
    _handController.add(newHand);

    if (persistPreference) {
      // Best-effort persistence — never await this from the sensor callback.
      unawaited(
        db.saveGripPreference(
          hand: newHand.name,
          posture: newPosture.name,
        ),
      );
    }

    assert(() {
      debugPrint(
        '🦎 Morph grip: ${newHand.name} hand, ${newPosture.name}',
      );
      return true;
    }());
  }

  GripHand _detectHand(double avgX) {
    if (avgX > _tiltThreshold) return GripHand.left;
    if (avgX < -_tiltThreshold) return GripHand.right;
    return GripHand.both;
  }

  GripHand _parseHand(String name) {
    for (final h in GripHand.values) {
      if (h.name == name) return h;
    }
    return GripHand.unknown;
  }

  GripPosture _detectPosture(AccelerometerEvent e) {
    // Magnitude well above 1g implies the device is being shaken or the
    // user is walking — reposition is risky, fall back to "moving".
    final magnitude = e.x * e.x + e.y * e.y + e.z * e.z;
    if (magnitude > 225) return GripPosture.moving; // > ~15 m/s²
    if (e.z.abs() > 8) return GripPosture.portrait;
    return GripPosture.landscape;
  }
}
