import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:morphui/morphui.dart';

/// Minimal in-memory path_provider stub so Hive.initFlutter() resolves to a
/// temp directory during widget tests (no platform channels).
class _FakePathProvider extends PathProviderPlatform {
  final Directory dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override
  Future<String?> getTemporaryPath() async => dir.path;
  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cml_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('MorphState', () {
    test('safe factory marks the state as safeMode', () {
      const theme = MorphTheme(
        mode: ThemeMode.light,
        isHighContrast: false,
        textScaleFactor: 1.0,
        locale: Locale('en'),
      );
      final state = MorphState.safe(theme);
      expect(state.safeMode, isTrue);
      expect(state.zoneOrder, isEmpty);
      expect(state.v2Enabled, isFalse);
    });

    test('copyWith preserves untouched fields', () {
      const theme = MorphTheme(
        mode: ThemeMode.dark,
        isHighContrast: false,
        textScaleFactor: 1.2,
        locale: Locale('fr'),
      );
      const s = MorphState(theme: theme, sessionId: 's-1');
      final reordered = s.copyWith(zoneOrder: const {'a': 0, 'b': 1});
      expect(reordered.theme, equals(theme));
      expect(reordered.sessionId, 's-1');
      expect(reordered.zoneOrder, const {'a': 0, 'b': 1});
    });
  });

  group('ZoneScorer', () {
    late BehaviorDB db;
    late ZoneScorer scorer;

    setUp(() async {
      db = BehaviorDB();
      await db.init();
      scorer = ZoneScorer(db, minInteractions: 3); // small threshold for tests
    });

    tearDown(() async {
      // Wipe between tests so counts don't leak.
      for (final name in [
        BehaviorDB.clicksBox,
        BehaviorDB.timeBox,
        BehaviorDB.sequencesBox,
        BehaviorDB.zoomBox,
        BehaviorDB.sessionsBox,
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box<Map>(name).clear();
      }
    });

    test('computeScores returns null below minInteractions', () async {
      await db.trackClick('zone-a', 'section');
      final scores = await scorer.computeScores();
      expect(scores, isNull);
    });

    test('computeScores ranks zones once threshold is met', () async {
      for (var i = 0; i < 5; i++) {
        await db.trackClick('zone-a', 'section');
      }
      await db.trackClick('zone-b', 'section');
      final scores = await scorer.computeScores();
      expect(scores, isNotNull);
      expect(scores!['zone-a']! > scores['zone-b']!, isTrue);
    });

    test('shouldReorder stays quiet when scores are near-equal', () {
      final map = scorer.shouldReorder({'a': 50, 'b': 48}, {'a': 0, 'b': 1});
      expect(map, isNull); // delta < swap threshold (15)
    });

    test('shouldReorder proposes a new order when delta is significant', () {
      final map = scorer.shouldReorder({'a': 20, 'b': 80}, {'a': 0, 'b': 1});
      expect(map, isNotNull);
      expect(map!['b'], 0); // highest score goes first
      expect(map['a'], 1);
    });
  });

  group('BehaviorDB', () {
    late BehaviorDB db;

    setUp(() async {
      db = BehaviorDB();
      await db.init();
    });

    tearDown(() async {
      for (final name in [
        BehaviorDB.clicksBox,
        BehaviorDB.timeBox,
        BehaviorDB.sequencesBox,
        BehaviorDB.zoomBox,
        BehaviorDB.sessionsBox,
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box<Map>(name).clear();
      }
    });

    test('trackZoom ignores scales below 1.2', () async {
      await db.trackZoom(1.0);
      await db.trackZoom(1.1);
      expect(await db.getZoomCount(), 0);
      await db.trackZoom(1.3);
      expect(await db.getZoomCount(), 1);
    });

    test('trackTimeSpent accumulates total and count', () async {
      await db.trackTimeSpent('zone-x', 1200);
      await db.trackTimeSpent('zone-x', 800);
      final stats = await db.getZoneStats('zone-x');
      expect(stats!['totalTimeMs'], 2000);
      expect(stats['visitCount'], 2);
    });

    test('trackTimeSpent drops sub-500ms flashes', () async {
      await db.trackTimeSpent('zone-x', 100);
      final stats = await db.getZoneStats('zone-x');
      expect(stats!['totalTimeMs'], 0);
    });
  });

  group('MorphProvider', () {
    testWidgets('safeMode exposes state without opening sessions',
        (tester) async {
      await tester.pumpWidget(
        const MorphProvider(
          licenseKey: '',
          safeMode: true,
          child: MaterialApp(home: _Probe()),
        ),
      );
      // Wait for post-frame bootstrap.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final probe = find.byType(_Probe);
      expect(probe, findsOneWidget);
      final context = tester.element(probe);
      final state = MorphInheritedWidget.maybeOf(context)?.state;
      expect(state, isNotNull);
      expect(state!.safeMode, isTrue);
      expect(state.sessionId, isEmpty);
    });
  });
}

/// Helper widget that simply mounts inside the provider so tests can grab
/// its BuildContext.
class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
