import 'dart:async';

import 'package:flutter/widgets.dart';

import '../behavior/behavior_db.dart';
import '../suggestions/morph_suggestion.dart';
import '../suggestions/suggestion_history.dart';
import 'recovery_snapshot.dart';

/// Coarse classification of how disruptive a pause was. The recovery
/// engine adapts message tone, confidence and the auto-restore vs
/// confirm path based on the bucket.
enum InterruptionBucket {
  /// Pause too short to count — typically a notification dismissed in
  /// a few seconds. Recovery is suppressed.
  brief,

  /// 30 seconds to 2 minutes — user briefly switched apps (paste an
  /// amount, look something up). Recovery favours auto-restore for
  /// safe values, "you were here" tone.
  quick,

  /// 2 minutes to 10 minutes — likely a phone call or real interrupt.
  /// Recovery surfaces the suggestion card with normal tone.
  real,

  /// More than 10 minutes — probable session abandonment. Recovery
  /// asks more cautiously ("you came back later — still want to
  /// resume?") and respects the per-context TTL strictly.
  abandonment,
}

/// Outcome the dev signals back via [InterruptionRecovery.recordOutcome]
/// after the user has interacted with (or ignored) a recovery card.
/// Feeds the local learning loop in [F.1].
enum RecoveryOutcome {
  /// User tapped "Resume" / accepted the suggestion.
  accepted,

  /// User tapped the dismiss action / explicitly chose to start over.
  rejected,

  /// User ignored the card until it timed out / they navigated away.
  /// Treated separately from explicit rejection — softer signal.
  ignored,
}

/// Detects significant app interruptions and produces a recovery
/// suggestion to surface on resume. Sits on top of the existing
/// suggestion system — the engine pulls a pending recovery via
/// [consumeSuggestion] before running its other checks.
///
/// **The 6 production-ready behaviours** wired in 0.1.2:
///
/// 1. **Pause bucketing.** Pause durations are bucketed into
///    quick / real / abandonment ranges with different defaults for
///    confidence and presentation strategy. See [InterruptionBucket].
///
/// 2. **Robust persistence.** The active context is now written to
///    Hive on every [declareContext] call (debounced to 1 entry per
///    second). An app crash between `declareContext` and `paused` no
///    longer loses the snapshot.
///
/// 3. **Recovery strategies.** Each snapshot declares a
///    [RecoveryStrategy] — `auto` (silent restore, no card), `confirm`
///    (card before restore, default for stakes-sensitive flows),
///    `silent` (analytics-only, no UI). Devs set this via the
///    `morphSet…Context(strategy: …)` extensions.
///
/// 4. **Multi-step workflows.** Snapshots can declare a `workflowId` +
///    `workflowStep`. On resume, the engine fetches the entire chain
///    and exposes it via [pendingChain] so the host app can restore
///    every step (KYC 1→4) in one go.
///
/// 5. **Per-context TTL.** Every snapshot has a TTL — see
///    [kRecoveryDefaultTtl]. Transfer amounts expire in 2 minutes,
///    KYC progress in 24 hours. Recovery refuses expired snapshots.
///
/// 6. **Local learning.** [recordOutcome] feeds an
///    accept/reject/ignore counter per pause bucket. After enough
///    samples, the engine refuses to surface a recovery for buckets
///    where the user consistently rejects it. Stays on-device, never
///    transmitted.
class InterruptionRecovery with WidgetsBindingObserver {
  final BehaviorDB db;
  final SuggestionHistoryStore historyStore;

  /// FREE plans get scroll-position recovery only — checkout / transfer
  /// / KYC contexts collapse into a generic "Pick up where you left
  /// off" snapshot. PRO+ unlocks the rich contextual messages, the
  /// multi-step chain, and the recovery strategies.
  final bool advancedContexts;

  /// Below this many seconds the pause is treated as a [InterruptionBucket.brief]
  /// hand-off (notification, app-switcher peek) and ignored.
  static const int minPauseSeconds = 30;

  /// Above this many samples in a bucket, the rejection-rate gate
  /// kicks in. Below it, every suggestion surfaces normally — too
  /// little signal to act on.
  static const int _learningMinSamples = 5;

  /// Rejection-rate (rejected + ignored) above which the bucket is
  /// considered "the user doesn't want this".
  static const double _learningRejectionGate = 0.7;

  /// How long write-through persistence batches consecutive
  /// `declareContext` calls before hitting Hive. 1s is short enough to
  /// be safe across app crashes but long enough to absorb keystroke
  /// bursts on large forms.
  static const Duration _writeDebounce = Duration(seconds: 1);

  DateTime? _pausedAt;
  RecoverySnapshot? _activeContext;
  MorphSuggestion? _pending;
  List<RecoverySnapshot> _pendingChain = const [];
  Timer? _writeDebouncer;
  bool _started = false;

  InterruptionRecovery({
    required this.db,
    required this.historyStore,
    this.advancedContexts = true,
  });

  void start() {
    if (_started) return;
    WidgetsBinding.instance.addObserver(this);
    _started = true;
  }

  void stop() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _writeDebouncer?.cancel();
    _writeDebouncer = null;
    // Flush any pending in-memory snapshot before shutdown so a
    // clean stop doesn't lose data.
    final pending = _activeContext;
    if (pending != null) {
      unawaited(db.saveSnapshot(pending));
    }
    _started = false;
  }

  /// Updates the in-memory context for the screen the user is looking
  /// at AND debounces a write-through to Hive. Persisted on `paused`
  /// too. The dev calls this via `context.morphSet…Context` — they
  /// don't instantiate snapshots themselves.
  void declareContext({
    required String page,
    required String context,
    double scrollDepth = 0,
    Map<String, dynamic> formData = const {},
    Map<String, dynamic> metadata = const {},
    Duration? ttl,
    RecoveryStrategy strategy = RecoveryStrategy.confirm,
    String? workflowId,
    int? workflowStep,
    int? workflowTotalSteps,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // FREE plan strips rich contexts so the recovery message stays
    // generic. PRO+ persists the full payload — that's what unlocks
    // "You were transferring 50€ to Alice" on resume + the multi-step
    // chain.
    final ctxClass = advancedContexts ? context : 'basic';
    final form = advancedContexts ? formData : const <String, dynamic>{};
    final meta = advancedContexts ? metadata : const <String, dynamic>{};
    final wfId = advancedContexts ? workflowId : null;
    final wfStep = advancedContexts ? workflowStep : null;
    final wfTotal = advancedContexts ? workflowTotalSteps : null;

    _activeContext = RecoverySnapshot(
      id: '${page}_$ts',
      page: page,
      scrollDepth: scrollDepth,
      context: ctxClass,
      formData: form,
      metadata: meta,
      timestamp: ts,
      ttl: ttl,
      strategy: strategy,
      workflowId: wfId,
      workflowStep: wfStep,
      workflowTotalSteps: wfTotal,
    );

    // (B) Debounced write-through — protects against crashes between
    // `declareContext` and `paused`.
    _writeDebouncer?.cancel();
    _writeDebouncer = Timer(_writeDebounce, () {
      final snap = _activeContext;
      if (snap != null) unawaited(db.saveSnapshot(snap));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _pausedAt = DateTime.now();
        // Flush immediately on pause — the debouncer might still be
        // waiting, and we'd rather pay the write twice than lose data.
        _writeDebouncer?.cancel();
        if (_activeContext != null) {
          unawaited(db.saveSnapshot(_activeContext!));
        }
      case AppLifecycleState.resumed:
        if (_pausedAt == null) break;
        final pauseSec = DateTime.now().difference(_pausedAt!).inSeconds;
        _pausedAt = null;
        unawaited(_onResume(pauseSec));
      default:
        break;
    }
  }

  // ─── Resume orchestration ────────────────────────────────────────────

  Future<void> _onResume(int pauseSeconds) async {
    final bucket = _bucketFor(pauseSeconds);
    if (bucket == InterruptionBucket.brief) return;

    // (F.1) Learning gate — if the user consistently rejects this
    // bucket, don't even try.
    if (await _shouldSuppressForBucket(bucket)) {
      assert(() {
        debugPrint(
          '🦎 Morph recovery: suppressed ${bucket.name} bucket '
          '(rejection rate above gate)',
        );
        return true;
      }());
      return;
    }

    final snap = await db.getLastSnapshot();
    if (snap == null) return;

    // (E) TTL gate — refuse stale snapshots.
    if (snap.isExpired) {
      assert(() {
        debugPrint('🦎 Morph recovery: snapshot expired '
            '(${snap.context}, age=${_ageOf(snap)})');
        return true;
      }());
      return;
    }

    // (D) If the snapshot is part of a workflow, fetch the full chain.
    final chain = (advancedContexts && snap.workflowId != null)
        ? await db.getSnapshotsByWorkflow(snap.workflowId!)
        : <RecoverySnapshot>[];
    _pendingChain = chain;

    // (C) Strategy dispatch — auto-restore silently, ask, or stay
    // quiet for analytics-only.
    switch (snap.strategy) {
      case RecoveryStrategy.silent:
        return;
      case RecoveryStrategy.auto:
        // Mark used immediately — host app reads `pendingChain` on
        // its own and restores the values without our card.
        await db.markSnapshotUsed(snap.id);
        for (final s in chain) {
          if (s.id != snap.id) await db.markSnapshotUsed(s.id);
        }
        return;
      case RecoveryStrategy.confirm:
        _pending = await _buildRecoverySuggestion(snap, pauseSeconds, bucket);
    }
  }

  Future<bool> _shouldSuppressForBucket(InterruptionBucket bucket) async {
    final stats = await _readBucketStats(bucket);
    final total = stats.accepted + stats.rejected + stats.ignored;
    if (total < _learningMinSamples) return false;
    final rejectionRate = (stats.rejected + stats.ignored) / total;
    return rejectionRate >= _learningRejectionGate;
  }

  Future<MorphSuggestion?> _buildRecoverySuggestion(
    RecoverySnapshot snap,
    int pauseSeconds,
    InterruptionBucket bucket,
  ) async {
    final id = 'recovery_${snap.page}_${snap.timestamp}';
    if (!await historyStore.canShow(id)) return null;
    return MorphSuggestion(
      id: id,
      type: SuggestionType.resumePosition,
      title: _titleFor(bucket),
      description: _buildMessage(snap, bucket),
      actionLabel: 'Resume',
      dismissLabel: 'Start over',
      // Confidence drops with bucket distance — abandonment recoveries
      // are less likely to be welcome.
      confidence: switch (bucket) {
        InterruptionBucket.quick => 0.95,
        InterruptionBucket.real => 0.90,
        InterruptionBucket.abandonment => 0.80,
        InterruptionBucket.brief => 0.0, // never reached
      },
      metadata: {
        'page': snap.page,
        'scrollDepth': snap.scrollDepth,
        'formData': snap.formData,
        'pauseSeconds': pauseSeconds,
        'pauseBucket': bucket.name,
        'context': snap.context,
        if (snap.workflowId != null) 'workflowId': snap.workflowId,
        if (snap.workflowStep != null) 'workflowStep': snap.workflowStep,
        ...snap.metadata,
      },
      action: () async {
        await db.markSnapshotUsed(snap.id);
        for (final s in _pendingChain) {
          if (s.id != snap.id) await db.markSnapshotUsed(s.id);
        }
      },
    );
  }

  /// One-shot pop of the pending recovery suggestion. Returns null when
  /// nothing is waiting. The suggestion engine calls this on each tick
  /// and merges the result with its other candidates.
  MorphSuggestion? consumeSuggestion() {
    final s = _pending;
    _pending = null;
    return s;
  }

  /// Multi-step chain associated with the most recent recovery — empty
  /// when the snapshot wasn't part of a workflow. The host app reads
  /// this to restore intermediate steps (KYC 1→4) on resume.
  List<RecoverySnapshot> get pendingChain => _pendingChain;

  /// Records the user's response to a recovery suggestion. Feeds the
  /// local learning loop ([F.1]) so future suggestions in the same
  /// pause bucket can be suppressed when the user shows a clear
  /// pattern of rejecting them. Stays on-device, never transmitted.
  Future<void> recordOutcome({
    required InterruptionBucket bucket,
    required RecoveryOutcome outcome,
  }) async {
    final stats = await _readBucketStats(bucket);
    final updated = stats.copyIncrementing(outcome);
    await db.savePreference(
      'recovery.bucket.${bucket.name}',
      updated.toMap(),
    );
  }

  Future<_BucketStats> _readBucketStats(InterruptionBucket bucket) async {
    final raw = db.readPreference('recovery.bucket.${bucket.name}');
    if (raw is Map) return _BucketStats.fromMap(raw);
    return const _BucketStats();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  InterruptionBucket _bucketFor(int pauseSeconds) {
    if (pauseSeconds < minPauseSeconds) return InterruptionBucket.brief;
    if (pauseSeconds < 120) return InterruptionBucket.quick;
    if (pauseSeconds < 600) return InterruptionBucket.real;
    return InterruptionBucket.abandonment;
  }

  String _titleFor(InterruptionBucket bucket) => switch (bucket) {
        InterruptionBucket.quick => 'Pick up where you left off',
        InterruptionBucket.real => 'Continue where you left off',
        InterruptionBucket.abandonment =>
          'Want to resume what you started earlier?',
        InterruptionBucket.brief => 'Resume',
      };

  String _buildMessage(RecoverySnapshot snap, InterruptionBucket bucket) {
    final base = _baseMessageFor(snap);
    if (bucket == InterruptionBucket.abandonment) {
      return '$base You came back a while later.';
    }
    return base;
  }

  String _baseMessageFor(RecoverySnapshot snap) {
    switch (snap.context) {
      // E-commerce
      case 'checkout':
        return 'You were completing your order. Your cart is still saved.';
      case 'cart':
        return 'Your cart is waiting for you.';
      case 'product':
        final name = snap.metadata['productName'] as String?;
        return name == null
            ? 'You were viewing a product.'
            : 'You were viewing $name.';

      // Fintech
      case 'transfer':
        final amount = snap.metadata['amount'];
        final recipient = snap.metadata['recipient'];
        if (amount != null && recipient != null) {
          return 'You were transferring $amount to $recipient.';
        }
        return 'You were making a transfer. Your progress is saved.';
      case 'kyc':
        final step = snap.workflowStep ?? snap.metadata['step'] as int? ?? 1;
        final total =
            snap.workflowTotalSteps ?? snap.metadata['totalSteps'] as int?;
        if (total != null) {
          return 'You were on step $step of $total in your verification.';
        }
        return 'You were on step $step of your verification.';

      default:
        final pct = snap.scrollDepth.toInt();
        return pct > 0
            ? 'You were at $pct% of this page.'
            : 'Pick up where you left off.';
    }
  }

  String _ageOf(RecoverySnapshot snap) {
    final ms = DateTime.now().millisecondsSinceEpoch - snap.timestamp;
    final mins = (ms / 60000).round();
    if (mins < 60) return '${mins}m';
    return '${(mins / 60).toStringAsFixed(1)}h';
  }

  @visibleForTesting
  RecoverySnapshot? get activeContext => _activeContext;
}

/// Aggregate accept/reject counters per pause bucket. Persisted in the
/// prefs box; never leaves the device.
@immutable
class _BucketStats {
  final int accepted;
  final int rejected;
  final int ignored;

  const _BucketStats({
    this.accepted = 0,
    this.rejected = 0,
    this.ignored = 0,
  });

  _BucketStats copyIncrementing(RecoveryOutcome outcome) {
    switch (outcome) {
      case RecoveryOutcome.accepted:
        return _BucketStats(
          accepted: accepted + 1,
          rejected: rejected,
          ignored: ignored,
        );
      case RecoveryOutcome.rejected:
        return _BucketStats(
          accepted: accepted,
          rejected: rejected + 1,
          ignored: ignored,
        );
      case RecoveryOutcome.ignored:
        return _BucketStats(
          accepted: accepted,
          rejected: rejected,
          ignored: ignored + 1,
        );
    }
  }

  Map<String, Object> toMap() => {
        'accepted': accepted,
        'rejected': rejected,
        'ignored': ignored,
      };

  factory _BucketStats.fromMap(Map raw) => _BucketStats(
        accepted: (raw['accepted'] as int?) ?? 0,
        rejected: (raw['rejected'] as int?) ?? 0,
        ignored: (raw['ignored'] as int?) ?? 0,
      );
}
