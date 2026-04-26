import 'package:flutter/foundation.dart';

/// How the recovery should be presented to the user when the snapshot
/// is restored. Each snapshot declares its own strategy so the
/// suggestion engine can adapt — a saved address can come back
/// silently, a half-typed transfer amount must be confirmed.
enum RecoveryStrategy {
  /// Restore values directly without showing the suggestion card.
  /// Use for values that can't surprise the user — last viewed page,
  /// saved scroll position, pre-filled form fields the user already
  /// entered earlier in the session.
  auto,

  /// Show the suggestion card and require an explicit tap before
  /// restoring. Use for high-stakes flows: payments, transfers,
  /// account changes, anything where a stale value could mislead.
  confirm,

  /// Don't surface anything to the user — the snapshot is captured
  /// for analytics or recovery-of-recovery purposes only. Useful for
  /// debugging the recovery flow without disrupting the UX.
  silent,
}

/// Default time-to-live per declared context. Once a snapshot is older
/// than its TTL, recovery refuses to surface it — a transfer amount
/// from 30 minutes ago is more likely to mislead than help.
///
/// Devs can override per-snapshot via the `ttl` field on
/// `morphSetTransferContext(... ttl: Duration(minutes: 5))`.
const Map<String, Duration> kRecoveryDefaultTtl = {
  // E-commerce
  'cart': Duration(hours: 24),
  'checkout': Duration(minutes: 30),
  'product': Duration(hours: 6),

  // Fintech — short windows because amounts decay fast.
  'transfer': Duration(minutes: 2),
  'payment': Duration(minutes: 2),
  'kyc': Duration(hours: 24),

  // Generic — anything else falls back to this.
  'basic': Duration(hours: 1),
};

/// Resolves the effective TTL for [context], falling back to the
/// "basic" entry when no specific match is configured.
Duration recoveryTtlFor(String context) =>
    kRecoveryDefaultTtl[context] ?? kRecoveryDefaultTtl['basic']!;

/// Snapshot of where the user was when the app was paused. Built by the
/// host app via the `morphSet…Context` extensions and restored by
/// `InterruptionRecovery` when the user comes back from a pause that
/// crosses the configured threshold.
@immutable
class RecoverySnapshot {
  /// Stable id used as the Hive box key. Typically `'<page>_<timestamp>'`
  /// so each declaration produces a fresh row.
  final String id;
  final String page;
  final double scrollDepth;

  /// Free-form classifier — `'checkout' | 'cart' | 'product' | 'transfer'
  /// | 'kyc' | …`. Drives the message in the recovery suggestion AND
  /// the default TTL.
  final String context;

  /// Recoverable form values keyed by field name. Stays on-device, never
  /// transmitted. The dev decides what's safe to put here.
  final Map<String, dynamic> formData;

  /// Free-form payload passed through to the suggestion (product name,
  /// transfer amount, KYC step, …). Read by the message builder in
  /// [InterruptionRecovery].
  final Map<String, dynamic> metadata;

  final int timestamp;
  final bool used;

  /// Per-snapshot TTL override. When null, the default for [context]
  /// applies (see [kRecoveryDefaultTtl]).
  final Duration? ttl;

  /// Strategy hint for how to present this snapshot's recovery. The
  /// engine respects it to pick between auto-restore and confirm.
  final RecoveryStrategy strategy;

  /// Workflow chain identifier — when present, the snapshot belongs
  /// to a multi-step flow (KYC, multi-page checkout) and the recovery
  /// engine should restore the entire chain, not just this snapshot.
  /// Example: `'kyc-2026-04-26-abc123'`.
  final String? workflowId;

  /// 1-based step index inside [workflowId]. Null when [workflowId] is
  /// null. Used to order the chain on resume.
  final int? workflowStep;

  /// Total step count in the workflow — surfaced in the recovery
  /// message ("step 4 of 7") and used to detect if the user was almost
  /// done vs. just starting.
  final int? workflowTotalSteps;

  const RecoverySnapshot({
    required this.id,
    required this.page,
    required this.scrollDepth,
    required this.context,
    this.formData = const {},
    this.metadata = const {},
    required this.timestamp,
    this.used = false,
    this.ttl,
    this.strategy = RecoveryStrategy.confirm,
    this.workflowId,
    this.workflowStep,
    this.workflowTotalSteps,
  });

  /// Effective TTL — snapshot's own override if set, else the default
  /// from [kRecoveryDefaultTtl] keyed on [context].
  Duration get effectiveTtl => ttl ?? recoveryTtlFor(context);

  /// True when this snapshot has lived past its TTL.
  bool get isExpired {
    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    return age > effectiveTtl.inMilliseconds;
  }

  RecoverySnapshot copyWith({
    bool? used,
    String? id,
    String? page,
    double? scrollDepth,
    String? context,
    Map<String, dynamic>? formData,
    Map<String, dynamic>? metadata,
    int? timestamp,
    Duration? ttl,
    RecoveryStrategy? strategy,
    String? workflowId,
    int? workflowStep,
    int? workflowTotalSteps,
  }) =>
      RecoverySnapshot(
        id: id ?? this.id,
        page: page ?? this.page,
        scrollDepth: scrollDepth ?? this.scrollDepth,
        context: context ?? this.context,
        formData: formData ?? this.formData,
        metadata: metadata ?? this.metadata,
        timestamp: timestamp ?? this.timestamp,
        used: used ?? this.used,
        ttl: ttl ?? this.ttl,
        strategy: strategy ?? this.strategy,
        workflowId: workflowId ?? this.workflowId,
        workflowStep: workflowStep ?? this.workflowStep,
        workflowTotalSteps: workflowTotalSteps ?? this.workflowTotalSteps,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'page': page,
        'scrollDepth': scrollDepth,
        'context': context,
        'formData': formData,
        'metadata': metadata,
        'timestamp': timestamp,
        'used': used,
        if (ttl != null) 'ttlMs': ttl!.inMilliseconds,
        'strategy': strategy.name,
        if (workflowId != null) 'workflowId': workflowId,
        if (workflowStep != null) 'workflowStep': workflowStep,
        if (workflowTotalSteps != null)
          'workflowTotalSteps': workflowTotalSteps,
      };

  factory RecoverySnapshot.fromMap(Map m) {
    final ttlMs = m['ttlMs'] as int?;
    final strategyName = m['strategy'] as String?;
    return RecoverySnapshot(
      id: m['id'] as String,
      page: m['page'] as String,
      scrollDepth: (m['scrollDepth'] as num?)?.toDouble() ?? 0,
      context: m['context'] as String? ?? '',
      formData:
          Map<String, dynamic>.from(m['formData'] as Map? ?? const {}),
      metadata:
          Map<String, dynamic>.from(m['metadata'] as Map? ?? const {}),
      timestamp: m['timestamp'] as int,
      used: m['used'] as bool? ?? false,
      ttl: ttlMs == null ? null : Duration(milliseconds: ttlMs),
      strategy: RecoveryStrategy.values.firstWhere(
        (s) => s.name == strategyName,
        orElse: () => RecoveryStrategy.confirm,
      ),
      workflowId: m['workflowId'] as String?,
      workflowStep: m['workflowStep'] as int?,
      workflowTotalSteps: m['workflowTotalSteps'] as int?,
    );
  }
}
