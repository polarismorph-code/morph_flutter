import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:morphui/morphui.dart';

import 'test_helpers.dart';

void main() {
  group('FatigueBaseline (pure)', () {
    test('empty baseline is not locked', () {
      expect(FatigueBaseline.empty.isLocked, isFalse);
      expect(FatigueBaseline.empty.sessionsRecorded, 0);
    });

    test('locks exactly at the configured session count', () {
      // The contract: don't lock before requiredSessions, do lock at
      // exactly that count.
      var b = FatigueBaseline.empty;
      for (var i = 1;
          i <= FatigueBaselineLimits.requiredSessions;
          i++) {
        b = b.merge(missedTapRatio: 0.05, typingSpeed: 4.0);
        if (i < FatigueBaselineLimits.requiredSessions) {
          expect(b.isLocked, isFalse, reason: 'session $i should be open');
        }
      }
      expect(b.isLocked, isTrue);
      expect(b.sessionsRecorded, FatigueBaselineLimits.requiredSessions);
    });

    test('merge is the running mean — equal samples produce stable averages',
        () {
      var b = FatigueBaseline.empty;
      b = b.merge(missedTapRatio: 0.10, typingSpeed: 5.0);
      b = b.merge(missedTapRatio: 0.10, typingSpeed: 5.0);
      b = b.merge(missedTapRatio: 0.10, typingSpeed: 5.0);
      expect(b.missedTapRatio, closeTo(0.10, 0.001));
      expect(b.typingSpeed, closeTo(5.0, 0.001));
    });

    test('merge averages distinct samples correctly', () {
      // 3 sessions with miss rates 0, 6%, 12% → average 6%.
      var b = FatigueBaseline.empty;
      b = b.merge(missedTapRatio: 0.00, typingSpeed: 6.0);
      b = b.merge(missedTapRatio: 0.06, typingSpeed: 4.0);
      b = b.merge(missedTapRatio: 0.12, typingSpeed: 2.0);
      expect(b.missedTapRatio, closeTo(0.06, 0.001));
      expect(b.typingSpeed, closeTo(4.0, 0.001));
    });

    test('toMap / fromMap round-trip preserves all fields', () {
      const original = FatigueBaseline(
        missedTapRatio: 0.07,
        typingSpeed: 4.2,
        sessionsRecorded: 3,
      );
      final round = FatigueBaseline.fromMap(original.toMap());
      expect(round.missedTapRatio, closeTo(0.07, 0.001));
      expect(round.typingSpeed, closeTo(4.2, 0.001));
      expect(round.sessionsRecorded, 3);
      expect(round.isLocked, isTrue);
    });

    test('fromMap survives missing or null fields gracefully', () {
      // Forward-compat: older snapshots that didn't write some fields
      // should still parse without throwing.
      final partial = FatigueBaseline.fromMap(const <String, dynamic>{
        'sessionsRecorded': 1,
      });
      expect(partial.missedTapRatio, 0);
      expect(partial.typingSpeed, 0);
      expect(partial.sessionsRecorded, 1);
    });
  });

  group('FatigueDetector (DB-backed)', () {
    late dynamic tempDir;
    late BehaviorDB db;
    late FatigueDetector detector;

    setUpAll(() async {
      tempDir = await setUpFakePathProvider(prefix: 'cml_fatigue_test');
    });

    tearDownAll(() async {
      await tearDownFakePathProvider(tempDir);
    });

    setUp(() async {
      db = BehaviorDB();
      await db.init();
      detector = FatigueDetector(db: db);
    });

    tearDown(() async {
      await detector.stop();
      if (Hive.isBoxOpen(BehaviorDB.prefsBox)) {
        await Hive.box(BehaviorDB.prefsBox).clear();
      }
    });

    test('startSession returns Future<void> and seeds defaults', () async {
      await detector.startSession();
      expect(detector.currentLevel, FatigueLevel.none);
      expect(detector.currentScore, 0);
      expect(detector.hasBaseline, isFalse);
    });

    test('typed error API increments the score above threshold', () async {
      // Pre-stamp today's date so startSession() doesn't classify this
      // as first-of-day → bypasses the 30s cold-start filter that
      // would otherwise hold the score at 0 for new users.
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await db.savePreference('fatigue.lastSessionDate', todayKey);

      await detector.startSession();
      // Each navigation error contributes 15% / 5 = 3% per call, so 5
      // navigation errors should put the score at the medium boundary.
      for (var i = 0; i < 5; i++) {
        detector.recordNavigationError();
      }
      // The score is debounced 800ms before emitting — wait it out.
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      // 5 nav errors × 0.15 weight = 0.15 score = 15/100. Below the
      // 40 medium threshold but above 0.
      expect(detector.currentScore, greaterThan(0));
      expect(detector.currentScore, lessThan(40));
    });

    test('persisted baseline survives a fresh detector instance', () async {
      await detector.startSession();
      await db.savePreference(
        'fatigue.baseline',
        const FatigueBaseline(
          missedTapRatio: 0.04,
          typingSpeed: 5.0,
          sessionsRecorded: FatigueBaselineLimits.requiredSessions,
        ).toMap(),
      );

      // Spin up a new detector — it should pick up the stored
      // baseline on startSession.
      await detector.stop();
      detector = FatigueDetector(db: db);
      await detector.startSession();
      expect(detector.hasBaseline, isTrue);
      expect(detector.baseline.missedTapRatio, closeTo(0.04, 0.001));
    });
  });
}
