import 'package:flutter_test/flutter_test.dart';
import 'package:morphui/morphui.dart';

void main() {
  group('GpsContextAdapter — speed classification', () {
    late GpsContextAdapter a;

    setUp(() => a = GpsContextAdapter());
    tearDown(() => a.stop());

    test('initial state is stationary, no fix needed', () {
      expect(a.currentContext, MovementContext.stationary);
    });

    test('< 2.5 km/h → stationary', () {
      a.onLocationUpdate(speedKmh: 0.5, accuracy: 10);
      expect(a.currentContext, MovementContext.stationary);
    });

    test('5 km/h → walking', () {
      a.onLocationUpdate(speedKmh: 5, accuracy: 10);
      expect(a.currentContext, MovementContext.walking);
    });

    test('15 km/h → cycling', () {
      a.onLocationUpdate(speedKmh: 15, accuracy: 10);
      expect(a.currentContext, MovementContext.cycling);
    });

    test('40 km/h → vehicle', () {
      a.onLocationUpdate(speedKmh: 40, accuracy: 10);
      expect(a.currentContext, MovementContext.vehicle);
    });
  });

  group('GpsContextAdapter — accuracy gate', () {
    test('accuracy > 50m starts the tunnel grace, does NOT flip to unknown', () {
      // Contract: a single bad fix should NOT pop us back to unknown.
      // The 30s grace expires later via Timer; the immediate state
      // must be the previously emitted context.
      final a = GpsContextAdapter();
      // Establish "walking" first.
      a.onLocationUpdate(speedKmh: 5, accuracy: 10);
      expect(a.currentContext, MovementContext.walking);

      // Now a degraded fix arrives.
      a.onLocationUpdate(speedKmh: 0, accuracy: 75);
      expect(
        a.currentContext,
        MovementContext.walking,
        reason: 'should hold the last good context inside the 30s grace',
      );
      a.stop();
    });

    test('a fresh good fix cancels the tunnel grace', () {
      final a = GpsContextAdapter();
      a.onLocationUpdate(speedKmh: 5, accuracy: 10);
      a.onLocationUpdate(speedKmh: 0, accuracy: 100); // bad
      a.onLocationUpdate(speedKmh: 30, accuracy: 5); // good — should drive
      expect(a.currentContext, MovementContext.vehicle);
      a.stop();
    });
  });

  group('GpsContextAdapter — hysteresis', () {
    test('walking does NOT downgrade to stationary at 2 km/h (entry was 2.5)',
        () {
      // walking → stationary requires speed < _stationaryReentry (1.5)
      final a = GpsContextAdapter();
      a.onLocationUpdate(speedKmh: 5, accuracy: 10); // walking
      a.onLocationUpdate(speedKmh: 2, accuracy: 10); // boundary
      expect(a.currentContext, MovementContext.walking);
      a.stop();
    });

    test('cycling does NOT downgrade to walking at 7 km/h (reentry is 6)', () {
      final a = GpsContextAdapter();
      a.onLocationUpdate(speedKmh: 15, accuracy: 10); // cycling
      a.onLocationUpdate(speedKmh: 7, accuracy: 10); // sits at boundary
      expect(
        a.currentContext,
        MovementContext.cycling,
        reason: 'should remain in cycling — 7 is above _walkingReentry (6)',
      );
      a.stop();
    });

    test('vehicle stays vehicle through a brief slowdown to 24 km/h', () {
      // Real-world case: brief red-light slowdown shouldn't pop us
      // back to cycling.
      final a = GpsContextAdapter();
      a.onLocationUpdate(speedKmh: 50, accuracy: 10); // vehicle
      a.onLocationUpdate(speedKmh: 24, accuracy: 10);
      expect(a.currentContext, MovementContext.vehicle);
      a.stop();
    });

    test('vehicle does eventually downgrade once below cycling reentry (23)',
        () {
      final a = GpsContextAdapter();
      a.onLocationUpdate(speedKmh: 50, accuracy: 10); // vehicle
      a.onLocationUpdate(speedKmh: 18, accuracy: 10); // below 23
      expect(a.currentContext, MovementContext.cycling);
      a.stop();
    });
  });

  group('GpsContextAdapter — stream emissions', () {
    test('only flips emit on the stream — same context twice is silent',
        () async {
      final a = GpsContextAdapter();
      final received = <MovementContext>[];
      a.stream.listen(received.add);

      a.onLocationUpdate(speedKmh: 5, accuracy: 10);
      a.onLocationUpdate(speedKmh: 5.5, accuracy: 10); // still walking
      a.onLocationUpdate(speedKmh: 6, accuracy: 10); // still walking
      a.onLocationUpdate(speedKmh: 30, accuracy: 10); // → vehicle

      // Drain the microtasks so the broadcast controller flushes.
      await Future<void>.delayed(Duration.zero);

      expect(received, [MovementContext.walking, MovementContext.vehicle]);
      a.stop();
    });
  });
}
