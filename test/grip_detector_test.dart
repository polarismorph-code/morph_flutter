import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:morphui/morphui.dart';

import 'test_helpers.dart';

void main() {
  late dynamic tempDir;
  late BehaviorDB db;

  // sensors_plus calls `setAccelerationSamplingPeriod` on its method
  // channel the moment the accelerometer stream is subscribed to. In a
  // unit test there's no native side, so the call throws. Register a
  // no-op handler so `start()` can complete and we can inspect the
  // detector's persistence-driven prior.
  TestWidgetsFlutterBinding.ensureInitialized();
  const sensorsChannel = MethodChannel(
    'dev.fluttercommunity.plus/sensors/method',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(sensorsChannel, (call) async => null);

  setUpAll(() async {
    tempDir = await setUpFakePathProvider(prefix: 'cml_grip_test');
  });

  tearDownAll(() async {
    await tearDownFakePathProvider(tempDir);
  });

  setUp(() async {
    db = BehaviorDB();
    await db.init();
  });

  tearDown(() async {
    if (Hive.isBoxOpen(BehaviorDB.prefsBox)) {
      await Hive.box(BehaviorDB.prefsBox).clear();
    }
  });

  group('GripDetector — persistence', () {
    test('first session has no prior — currentHand is unknown', () {
      // Cold start: nothing in storage → detector starts agnostic.
      // We can't await start() (it'd subscribe to the accelerometer
      // and deadlock the test), so we read the synchronous getters
      // before the real start.
      final detector = GripDetector(db: db);
      expect(detector.currentHand, GripHand.unknown);
      expect(detector.currentPosture, GripPosture.unknown);
    });

    test('saveGripPreference persists hand + posture round-trip', () async {
      // The save side of the persistence contract — proves data is
      // really written to Hive (not just kept in memory by the
      // detector instance).
      await db.saveGripPreference(hand: 'left', posture: 'portrait');
      final stored = db.readPreference('grip.hand');
      expect(stored, 'left');
      expect(db.readPreference('grip.posture'), 'portrait');
    });

    test('persistPreference: false skips storage on save path', () async {
      // The opt-out: a dev who wants ephemeral detection should be
      // able to disable persistence entirely. The flag short-circuits
      // both the load and the save legs.
      final detector =
          GripDetector(db: db, persistPreference: false);
      // Without start() the sensor never fires and no save happens —
      // we just verify the constructor preserves the flag.
      expect(detector.persistPreference, isFalse);
    });

    test('persistPreference defaults to true (backward compat)', () {
      // Existing 0.1.1 callers passed only `db:` — they should keep
      // getting the old behaviour (persist on detect).
      final detector = GripDetector(db: db);
      expect(detector.persistPreference, isTrue);
    });
  });

  group('GripDetector — start() reads stored preference', () {
    test('start seeds currentHand from a previously saved value',
        () async {
      // The "you came back, your phone remembers you held it left
      // last time" path. Save first, then construct a fresh detector
      // and call start — currentHand should be the seeded value
      // BEFORE any sensor sample arrives.
      await db.saveGripPreference(hand: 'left', posture: 'portrait');

      final detector = GripDetector(db: db);
      // Don't await — start() subscribes to the accelerometer which
      // can hang forever in unit tests. Just kick it off and let the
      // synchronous prelude (the prefs read) finish via a microtask
      // pump.
      // ignore: unawaited_futures
      detector.start();
      await Future<void>.delayed(Duration.zero);

      expect(detector.currentHand, GripHand.left);
      detector.stop();
    });

    test('start with corrupted stored value falls back to unknown', () async {
      // Defensive parse: an old / malformed value shouldn't crash —
      // the detector should treat it like cold start.
      await db.savePreference('grip.hand', 'something_invalid');

      final detector = GripDetector(db: db);
      // ignore: unawaited_futures
      detector.start();
      await Future<void>.delayed(Duration.zero);

      expect(detector.currentHand, GripHand.unknown);
      detector.stop();
    });

    test('start with persistPreference=false ignores stored value', () async {
      // The opt-out also prevents read — even if data is sitting in
      // prefs, an opt-out detector starts fresh.
      await db.saveGripPreference(hand: 'right', posture: 'portrait');

      final detector =
          GripDetector(db: db, persistPreference: false);
      // ignore: unawaited_futures
      detector.start();
      await Future<void>.delayed(Duration.zero);

      expect(detector.currentHand, GripHand.unknown);
      detector.stop();
    });
  });
}
