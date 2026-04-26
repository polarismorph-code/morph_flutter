import 'package:flutter/foundation.dart';

/// Snapshot of where the user was when the app was paused. Built by the
/// host app via the `morphSet…Context` extensions and restored by
/// [InterruptionRecovery] when the user comes back from a 30s+ pause.
@immutable
class RecoverySnapshot {
  /// Stable id used as the Hive box key. Typically `'<page>_<timestamp>'`
  /// so each declaration produces a fresh row.
  final String id;
  final String page;
  final double scrollDepth;

  /// Free-form classifier — `'checkout' | 'cart' | 'product' | 'transfer'
  /// | 'kyc' | …`. Drives the message in the recovery suggestion.
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

  const RecoverySnapshot({
    required this.id,
    required this.page,
    required this.scrollDepth,
    required this.context,
    this.formData = const {},
    this.metadata = const {},
    required this.timestamp,
    this.used = false,
  });

  RecoverySnapshot copyWith({bool? used}) => RecoverySnapshot(
        id: id,
        page: page,
        scrollDepth: scrollDepth,
        context: context,
        formData: formData,
        metadata: metadata,
        timestamp: timestamp,
        used: used ?? this.used,
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
      };

  factory RecoverySnapshot.fromMap(Map m) => RecoverySnapshot(
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
      );
}
