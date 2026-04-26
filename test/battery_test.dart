import 'package:flutter_test/flutter_test.dart';
import 'package:morphui/morphui.dart';

void main() {
  group('BatteryAdapter.bucketFor', () {
    test('charging short-circuits to normal regardless of level', () {
      // The whole point of charging-aware: 5% on a charger should NOT
      // degrade the UI. This is the contract documented in the README.
      expect(
        BatteryAdapter.bucketFor(level: 5, charging: true),
        BatteryMode.normal,
      );
      expect(
        BatteryAdapter.bucketFor(level: 0, charging: true),
        BatteryMode.normal,
      );
    });

    test('thresholds: 100→normal, 49→medium, 19→low, 9→critical', () {
      expect(
        BatteryAdapter.bucketFor(level: 100, charging: false),
        BatteryMode.normal,
      );
      expect(
        BatteryAdapter.bucketFor(level: 49, charging: false),
        BatteryMode.medium,
      );
      expect(
        BatteryAdapter.bucketFor(level: 19, charging: false),
        BatteryMode.low,
      );
      expect(
        BatteryAdapter.bucketFor(level: 9, charging: false),
        BatteryMode.critical,
      );
    });

    test('boundaries: 50 is normal, 20 is low, 10 is critical', () {
      // Verifies the inclusive/exclusive choice: <= for the lower
      // bucket, < for the upper.
      expect(
        BatteryAdapter.bucketFor(level: 51, charging: false),
        BatteryMode.normal,
      );
      expect(
        BatteryAdapter.bucketFor(level: 50, charging: false),
        BatteryMode.medium,
      );
      expect(
        BatteryAdapter.bucketFor(level: 20, charging: false),
        BatteryMode.low,
      );
      expect(
        BatteryAdapter.bucketFor(level: 10, charging: false),
        BatteryMode.critical,
      );
    });
  });

  group('BatterySessionSnapshot', () {
    test('drainPerMinute returns null for sub-30s sessions', () {
      // Short sessions are too noisy to grade — caller should drop.
      const snap = BatterySessionSnapshot(
        sessionId: 's1',
        startTime: 1000,
        endTime: 1000 + 25 * 1000, // 25s
        batteryAtStart: 80,
        batteryAtEnd: 79,
        wasCharging: false,
      );
      expect(snap.drainPerMinute, isNull);
    });

    test('drainPerMinute computed correctly over a 5-min run', () {
      const snap = BatterySessionSnapshot(
        sessionId: 's1',
        startTime: 0,
        endTime: 5 * 60 * 1000, // 5min
        batteryAtStart: 80,
        batteryAtEnd: 75, // -5%
        wasCharging: false,
      );
      // -5% over 5 min = 1.0 %/min
      expect(snap.drainPerMinute, closeTo(1.0, 0.001));
    });

    test('batteryDrop is negative when the device gained charge', () {
      const snap = BatterySessionSnapshot(
        sessionId: 's1',
        startTime: 0,
        endTime: 60 * 1000,
        batteryAtStart: 50,
        batteryAtEnd: 60, // +10
        wasCharging: true,
      );
      expect(snap.batteryDrop, -10);
    });

    test('toMap / fromMap round-trip preserves all fields', () {
      const original = BatterySessionSnapshot(
        sessionId: 's-abc',
        startTime: 1700000000000,
        endTime: 1700000300000,
        batteryAtStart: 90,
        batteryAtEnd: 85,
        wasCharging: false,
      );
      final round = BatterySessionSnapshot.fromMap(original.toMap());
      expect(round.sessionId, 's-abc');
      expect(round.startTime, 1700000000000);
      expect(round.batteryAtEnd, 85);
      expect(round.wasCharging, false);
    });
  });

  group('ChargePatternPredictor', () {
    DateTime monday(int hour, int minute) =>
        DateTime(2026, 4, 27, hour, minute); // 2026-04-27 is a Monday

    test('empty input never predicts a charge window', () {
      final p = ChargePatternPredictor();
      p.ingest(const []);
      expect(p.isApproachingChargeWindow(monday(8, 0)), isFalse);
    });

    test('below minSamples threshold the predictor stays silent', () {
      final p = ChargePatternPredictor();
      // 2 events at 8am on a Monday — minSamples is 3, so no fire.
      p.ingest([
        for (var i = 0; i < 2; i++)
          {
            'timestamp':
                DateTime.now().subtract(Duration(days: i)).millisecondsSinceEpoch,
            'hour': 8,
            'minute': 0,
            'dayOfWeek': DateTime.monday,
            'batteryLevel': 50,
          },
      ]);
      expect(p.isApproachingChargeWindow(monday(8, 30)), isFalse);
    });

    test('three same-hour events trip the predictor', () {
      final p = ChargePatternPredictor();
      p.ingest([
        for (var i = 0; i < 3; i++)
          {
            'timestamp':
                DateTime.now().subtract(Duration(days: i)).millisecondsSinceEpoch,
            'hour': 8,
            'minute': 0,
            'dayOfWeek': DateTime.monday,
            'batteryLevel': 50,
          },
      ]);
      expect(p.isApproachingChargeWindow(monday(8, 30)), isTrue);
    });

    test('predictor spills into the next hour when within window', () {
      // Events at 22:00 — at 21:50 (10min before) the predictor should
      // already say "approaching".
      final p = ChargePatternPredictor();
      p.ingest([
        for (var i = 0; i < 3; i++)
          {
            'timestamp':
                DateTime.now().subtract(Duration(days: i)).millisecondsSinceEpoch,
            'hour': 22,
            'minute': 0,
            'dayOfWeek': DateTime.monday,
            'batteryLevel': 30,
          },
      ]);
      expect(p.isApproachingChargeWindow(monday(21, 50)), isTrue);
    });

    test('events older than recencyDays are ignored', () {
      // 3 charges at 8am, but all 14 days old (recencyDays is 7).
      final p = ChargePatternPredictor();
      p.ingest([
        for (var i = 0; i < 3; i++)
          {
            'timestamp': DateTime.now()
                .subtract(Duration(days: 14 + i))
                .millisecondsSinceEpoch,
            'hour': 8,
            'minute': 0,
            'dayOfWeek': DateTime.monday,
            'batteryLevel': 40,
          },
      ]);
      expect(p.isApproachingChargeWindow(monday(8, 0)), isFalse);
    });
  });
}
