import 'dart:async';

import 'package:flutter/widgets.dart';

import '../behavior/behavior_db.dart';
import '../suggestions/morph_suggestion.dart';
import '../suggestions/suggestion_history.dart';
import 'recovery_snapshot.dart';

/// Detects significant app interruptions (paused 30s+) and produces a
/// recovery suggestion to surface on resume. Sits on top of the existing
/// suggestion system — the engine pulls a pending recovery via
/// [consumeSuggestion] before running its other checks.
///
/// The host app declares its current context (cart, transfer, KYC step…)
/// through the `context.morphSet…Context` extensions. That data is
/// snapshotted on `paused` and restored on `resumed`.
class InterruptionRecovery with WidgetsBindingObserver {
  final BehaviorDB db;
  final SuggestionHistoryStore historyStore;

  /// FREE plans get scroll-position recovery only — checkout / transfer /
  /// KYC contexts collapse into a generic "Pick up where you left off"
  /// snapshot. PRO+ unlocks the rich contextual messages by passing
  /// `advancedContexts: true` (wired automatically by MorphProvider
  /// based on the resolved plan).
  final bool advancedContexts;

  /// Below this many seconds the pause is treated as background
  /// hand-off (notification, app-switcher peek) and ignored.
  static const int minPauseSeconds = 30;

  DateTime? _pausedAt;
  RecoverySnapshot? _activeContext;
  MorphSuggestion? _pending;
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
    _started = false;
  }

  /// Updates the in-memory context for the screen the user is looking
  /// at. Persisted on `paused` so the snapshot survives an app kill.
  /// The dev calls this via `context.morphSet…Context` — they don't
  /// instantiate snapshots themselves.
  void declareContext({
    required String page,
    required String context,
    double scrollDepth = 0,
    Map<String, dynamic> formData = const {},
    Map<String, dynamic> metadata = const {},
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // FREE plan strips rich contexts so the recovery message stays
    // generic ("You were at X% of this page"). PRO+ plans persist the
    // full payload — that's what unlocks "You were transferring 50€ to
    // Alice" on resume.
    final ctx = advancedContexts ? context : 'basic';
    final form = advancedContexts ? formData : const <String, dynamic>{};
    final meta = advancedContexts ? metadata : const <String, dynamic>{};
    _activeContext = RecoverySnapshot(
      id: '${page}_$ts',
      page: page,
      scrollDepth: scrollDepth,
      context: ctx,
      formData: form,
      metadata: meta,
      timestamp: ts,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _pausedAt = DateTime.now();
        // Best-effort persistence — never block the platform thread.
        if (_activeContext != null) {
          unawaited(db.saveSnapshot(_activeContext!));
        }
      case AppLifecycleState.resumed:
        if (_pausedAt == null) break;
        final pauseSec =
            DateTime.now().difference(_pausedAt!).inSeconds;
        _pausedAt = null;
        if (pauseSec < minPauseSeconds) break;
        unawaited(_onSignificantInterruption(pauseSec));
      default:
        break;
    }
  }

  Future<void> _onSignificantInterruption(int pauseSeconds) async {
    final snap = await db.getLastSnapshot();
    if (snap == null) return;
    _pending = await _buildRecoverySuggestion(snap, pauseSeconds);
  }

  Future<MorphSuggestion?> _buildRecoverySuggestion(
    RecoverySnapshot snap,
    int pauseSeconds,
  ) async {
    final id = 'recovery_${snap.page}_${snap.timestamp}';
    if (!await historyStore.canShow(id)) return null;
    return MorphSuggestion(
      id: id,
      type: SuggestionType.resumePosition,
      title: 'Continue where you left off',
      description: _buildMessage(snap),
      actionLabel: 'Resume',
      dismissLabel: 'Start over',
      confidence: 0.95,
      metadata: {
        'page': snap.page,
        'scrollDepth': snap.scrollDepth,
        'formData': snap.formData,
        'pauseSeconds': pauseSeconds,
        'context': snap.context,
        ...snap.metadata,
      },
      action: () async {
        await db.markSnapshotUsed(snap.id);
      },
    );
  }

  /// One-shot pop of the pending recovery suggestion. Returns null when
  /// nothing is waiting. The suggestion engine calls this on each tick
  /// and merges the result with its other candidates (recovery wins on
  /// confidence: 0.95 vs the others' max ~0.85).
  MorphSuggestion? consumeSuggestion() {
    final s = _pending;
    _pending = null;
    return s;
  }

  // ─── Message templates ────────────────────────────────────────────────

  String _buildMessage(RecoverySnapshot snap) {
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
        final step = snap.metadata['step'] as int? ?? 1;
        final total = snap.metadata['totalSteps'] as int?;
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

  @visibleForTesting
  RecoverySnapshot? get activeContext => _activeContext;
}
