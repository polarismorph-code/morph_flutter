import 'dart:async';

import 'package:flutter/foundation.dart';

/// Coarse movement classification — derived from speed + GPS accuracy.
enum MovementContext { stationary, walking, cycling, vehicle, unknown }

/// Receives location updates from the host app's *existing* GPS pipeline
/// and exposes a coarse [MovementContext] stream. **Morph never
/// requests location permission itself** — the dev pipes their own
/// `Position` updates in via [onLocationUpdate].
///
/// Threshold mapping (km/h):
///   • < 2     → stationary
///   • 2..7    → walking
///   • 7..25   → cycling
///   • ≥ 25    → vehicle
///   • accuracy > 50m → unknown (don't act on bad fixes)
class GpsContextAdapter {
  MovementContext _context = MovementContext.stationary;
  final _controller = StreamController<MovementContext>.broadcast();

  Stream<MovementContext> get stream => _controller.stream;
  MovementContext get currentContext => _context;

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
    final next = _classify(speedKmh, accuracy);
    if (next == _context) return;
    _context = next;
    _controller.add(next);
    assert(() {
      debugPrint(
        '🦎 Morph GPS: ${next.name} '
        '(${speedKmh.toStringAsFixed(1)} km/h, ±${accuracy.toStringAsFixed(0)}m)',
      );
      return true;
    }());
  }

  MovementContext _classify(double speedKmh, double accuracy) {
    if (accuracy > 50) return MovementContext.unknown;
    if (speedKmh < 2) return MovementContext.stationary;
    if (speedKmh < 7) return MovementContext.walking;
    if (speedKmh < 25) return MovementContext.cycling;
    return MovementContext.vehicle;
  }

  void stop() {
    _controller.close();
  }
}
