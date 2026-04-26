import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../behavior/behavior_db.dart';

enum GripHand { left, right, both, unknown }

enum GripPosture { portrait, landscape, moving, unknown }

/// Reads the accelerometer to infer left/right grip and an approximate
/// posture (portrait, landscape, moving). Subscribers (typically
/// [GripAdaptiveLayout]) react to [handStream] to reposition CTAs on the
/// dominant side.
///
/// Detection rule: a sustained positive X-axis tilt means the device is
/// leaning right → user is probably gripping with the LEFT hand
/// (right-thumb apps lean the device the other way and vice versa). The
/// signal is smoothed across a 20-sample sliding window to ignore micro
/// motion.
class GripDetector {
  final BehaviorDB db;

  GripDetector({required this.db});

  static const int _sampleWindow = 20;
  static const int _minSamples = 10;
  static const double _tiltThreshold = 1.5; // m/s² on the X axis

  StreamSubscription<AccelerometerEvent>? _accelSub;

  GripHand _hand = GripHand.unknown;
  GripPosture _posture = GripPosture.unknown;
  final List<double> _xSamples = [];

  final _handController = StreamController<GripHand>.broadcast();

  /// Live stream of detected hands. Replays the latest value via
  /// [GripAdaptiveLayout]'s `initialData`.
  Stream<GripHand> get handStream => _handController.stream;

  GripHand get currentHand => _hand;
  GripPosture get currentPosture => _posture;

  void start() {
    // sensors_plus 4.x: `accelerometerEvents` is the public stream;
    // 5.x renames it to `accelerometerEventStream()`. We pin to 4.x in
    // pubspec, so the deprecation note is informational only.
    // ignore: deprecated_member_use
    _accelSub ??= accelerometerEvents.listen(
      _onAccel,
      onError: (Object e) {
        if (kDebugMode) {
          debugPrint('🦎 Morph grip: accelerometer error: $e');
        }
      },
    );
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
    if (_xSamples.length < _minSamples) return;

    final avgX =
        _xSamples.reduce((a, b) => a + b) / _xSamples.length;
    final newHand = _detectHand(avgX);
    final newPosture = _detectPosture(e);

    if (newHand == _hand && newPosture == _posture) return;
    _hand = newHand;
    _posture = newPosture;
    _handController.add(newHand);

    // Best-effort persistence — never await this from the sensor callback.
    unawaited(db.saveGripPreference(
      hand: newHand.name,
      posture: newPosture.name,
    ));

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

  GripPosture _detectPosture(AccelerometerEvent e) {
    // Magnitude well above 1g implies the device is being shaken or the
    // user is walking — reposition is risky, fall back to "moving".
    final magnitude = e.x * e.x + e.y * e.y + e.z * e.z;
    if (magnitude > 225) return GripPosture.moving; // > ~15 m/s²
    if (e.z.abs() > 8) return GripPosture.portrait;
    return GripPosture.landscape;
  }
}
