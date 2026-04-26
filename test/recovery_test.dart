import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:morphui/morphui.dart';

import 'test_helpers.dart';

void main() {
  group('RecoverySnapshot — TTL', () {
    test('default TTL maps from context — transfer is 2min, kyc 24h', () {
      // The defaults are deliberately tight for high-stakes flows
      // (transfer) and loose for slow workflows (kyc).
      expect(recoveryTtlFor('transfer'), const Duration(minutes: 2));
      expect(recoveryTtlFor('kyc'), const Duration(hours: 24));
      expect(recoveryTtlFor('checkout'), const Duration(minutes: 30));
    });

    test('unknown context falls back to the basic default (1h)', () {
      expect(recoveryTtlFor('something_random'), const Duration(hours: 1));
    });

    test('per-snapshot ttl override beats the context default', () {
      const snap = RecoverySnapshot(
        id: 'x',
        page: '/p',
        scrollDepth: 0,
        context: 'transfer', // would be 2 min by default
        timestamp: 0,
        ttl: Duration(minutes: 30),
      );
      expect(snap.effectiveTtl, const Duration(minutes: 30));
    });

    test('isExpired returns true once age crosses TTL', () {
      // Build a snapshot with a 1ms TTL to force expiration.
      final snap = RecoverySnapshot(
        id: 'x',
        page: '/p',
        scrollDepth: 0,
        context: 'basic',
        timestamp: DateTime.now()
            .subtract(const Duration(seconds: 5))
            .millisecondsSinceEpoch,
        ttl: const Duration(milliseconds: 1),
      );
      expect(snap.isExpired, isTrue);
    });

    test('isExpired returns false for a fresh snapshot', () {
      final snap = RecoverySnapshot(
        id: 'x',
        page: '/p',
        scrollDepth: 0,
        context: 'kyc',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      expect(snap.isExpired, isFalse);
    });
  });

  group('RecoverySnapshot — workflow + serialisation', () {
    test('toMap / fromMap round-trip preserves all new fields', () {
      const original = RecoverySnapshot(
        id: 'kyc-step-3',
        page: '/kyc/step3',
        scrollDepth: 42.5,
        context: 'kyc',
        timestamp: 1700000000000,
        strategy: RecoveryStrategy.confirm,
        workflowId: 'kyc-2026-04',
        workflowStep: 3,
        workflowTotalSteps: 7,
        ttl: Duration(hours: 12),
      );
      final round = RecoverySnapshot.fromMap(original.toMap());
      expect(round.id, 'kyc-step-3');
      expect(round.workflowId, 'kyc-2026-04');
      expect(round.workflowStep, 3);
      expect(round.workflowTotalSteps, 7);
      expect(round.strategy, RecoveryStrategy.confirm);
      expect(round.ttl, const Duration(hours: 12));
    });

    test('strategy defaults to confirm when missing in the map', () {
      // Forward-compat: snapshots written by older versions of the SDK
      // (before strategy existed) should default to the safe choice.
      final snap = RecoverySnapshot.fromMap(const <String, dynamic>{
        'id': 'x',
        'page': '/p',
        'scrollDepth': 0,
        'context': 'cart',
        'timestamp': 1700000000000,
        // no 'strategy' key
      });
      expect(snap.strategy, RecoveryStrategy.confirm);
    });

    test('workflow fields are nullable — basic snapshots stay basic', () {
      const snap = RecoverySnapshot(
        id: 'p',
        page: '/page',
        scrollDepth: 0,
        context: 'basic',
        timestamp: 0,
      );
      expect(snap.workflowId, isNull);
      expect(snap.workflowStep, isNull);
    });
  });

  group('BehaviorDB — workflow chain', () {
    late dynamic tempDir;
    late BehaviorDB db;

    setUpAll(() async {
      tempDir = await setUpFakePathProvider(prefix: 'cml_recovery_test');
    });

    tearDownAll(() async {
      await tearDownFakePathProvider(tempDir);
    });

    setUp(() async {
      db = BehaviorDB();
      await db.init();
    });

    tearDown(() async {
      if (Hive.isBoxOpen(BehaviorDB.snapshotsBox)) {
        await Hive.box<Map>(BehaviorDB.snapshotsBox).clear();
      }
    });

    test('getSnapshotsByWorkflow returns chain ordered by step', () async {
      // Save 3 KYC steps in reverse order — the lookup should still
      // return them ordered by workflowStep ascending.
      for (final step in [3, 1, 2]) {
        await db.saveSnapshot(
          RecoverySnapshot(
            id: 'kyc-$step',
            page: '/kyc/$step',
            scrollDepth: 0,
            context: 'kyc',
            timestamp: DateTime.now().millisecondsSinceEpoch + step,
            workflowId: 'kyc-w1',
            workflowStep: step,
            workflowTotalSteps: 7,
          ),
        );
      }
      final chain = await db.getSnapshotsByWorkflow('kyc-w1');
      expect(chain.map((s) => s.workflowStep).toList(), [1, 2, 3]);
    });

    test('getSnapshotsByWorkflow excludes used snapshots', () async {
      // Used snapshots shouldn't reappear in subsequent recoveries.
      await db.saveSnapshot(
        const RecoverySnapshot(
          id: 'kyc-1',
          page: '/kyc/1',
          scrollDepth: 0,
          context: 'kyc',
          timestamp: 100,
          workflowId: 'wf',
          workflowStep: 1,
        ),
      );
      await db.markSnapshotUsed('kyc-1');
      final chain = await db.getSnapshotsByWorkflow('wf');
      expect(chain, isEmpty);
    });

    test('getSnapshotsByWorkflow filters by exact workflow id', () async {
      await db.saveSnapshot(
        const RecoverySnapshot(
          id: 's-a',
          page: '/p',
          scrollDepth: 0,
          context: 'kyc',
          timestamp: 100,
          workflowId: 'wf-a',
          workflowStep: 1,
        ),
      );
      await db.saveSnapshot(
        const RecoverySnapshot(
          id: 's-b',
          page: '/p',
          scrollDepth: 0,
          context: 'kyc',
          timestamp: 200,
          workflowId: 'wf-b',
          workflowStep: 1,
        ),
      );
      final chain = await db.getSnapshotsByWorkflow('wf-a');
      expect(chain, hasLength(1));
      expect(chain.first.id, 's-a');
    });
  });
}
