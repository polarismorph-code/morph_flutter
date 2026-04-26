import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'morph_suggestion.dart';

/// Per-suggestion outcome record. One row per suggestion id in the
/// `cml_suggestions` Hive box.
@immutable
class SuggestionHistory {
  final String suggestionId;
  final bool accepted;
  final int refusedCount;
  final int ignoredCount;
  final DateTime? lastRefused;
  final DateTime? lastIgnored;
  final DateTime? acceptedAt;

  const SuggestionHistory({
    required this.suggestionId,
    this.accepted = false,
    this.refusedCount = 0,
    this.ignoredCount = 0,
    this.lastRefused,
    this.lastIgnored,
    this.acceptedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': suggestionId,
        'accepted': accepted,
        'refusedCount': refusedCount,
        'ignoredCount': ignoredCount,
        'lastRefused': lastRefused?.millisecondsSinceEpoch,
        'lastIgnored': lastIgnored?.millisecondsSinceEpoch,
        'acceptedAt': acceptedAt?.millisecondsSinceEpoch,
      };

  factory SuggestionHistory.fromMap(Map map) => SuggestionHistory(
        suggestionId: map['id'] as String,
        accepted: map['accepted'] as bool? ?? false,
        refusedCount: map['refusedCount'] as int? ?? 0,
        ignoredCount: map['ignoredCount'] as int? ?? 0,
        lastRefused: _parseTs(map['lastRefused']),
        lastIgnored: _parseTs(map['lastIgnored']),
        acceptedAt: _parseTs(map['acceptedAt']),
      );

  static DateTime? _parseTs(Object? raw) {
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }
}

/// Hive-backed store enforcing the cooldown rules from the spec:
///   • accepted        → never show again
///   • 3+ refusals     → never show again
///   • last refused    → wait 7 days
///   • last ignored    → wait 3 days
class SuggestionHistoryStore {
  static const String boxName = 'cml_suggestions';

  // Cooldown windows — exposed as constants so tests can verify the policy
  // and devs can read it from the UI ("we'll ask again in 7 days").
  static const Duration refusalCooldown = Duration(days: 7);
  static const Duration ignoreCooldown = Duration(days: 3);
  static const int refusalLimit = 3;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    // Hive itself is initialized by [BehaviorDB.init] — we just open our box.
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox(boxName);
    }
    _initialized = true;
  }

  /// Convenience for the privacy/settings screen — wipes every recorded
  /// outcome. Forces all suggestions to become eligible again.
  Future<void> clear() async {
    if (!_initialized) return;
    await Hive.box(boxName).clear();
  }

  Future<SuggestionHistory?> get(String id) async {
    if (!_initialized) return null;
    final raw = Hive.box(boxName).get(id);
    if (raw is Map) return SuggestionHistory.fromMap(raw);
    return null;
  }

  /// Should the engine surface this suggestion right now? The single
  /// authoritative gate — every check in the engine must call this before
  /// returning a suggestion.
  Future<bool> canShow(String id) async {
    final h = await get(id);
    if (h == null) return true;
    if (h.accepted) return false;
    if (h.refusedCount >= refusalLimit) return false;

    final now = DateTime.now();
    if (h.lastRefused != null &&
        now.difference(h.lastRefused!) < refusalCooldown) {
      return false;
    }
    if (h.lastIgnored != null &&
        now.difference(h.lastIgnored!) < ignoreCooldown) {
      return false;
    }
    return true;
  }

  /// Persist an outcome and bump the relevant counters / timestamps.
  /// Idempotent for [SuggestionResponse.accepted] — repeated accepted
  /// records overwrite to the same accepted state.
  Future<void> record(String id, SuggestionResponse response) async {
    if (!_initialized) return;
    final box = Hive.box(boxName);
    final existing = await get(id);
    final now = DateTime.now();
    late SuggestionHistory updated;

    switch (response) {
      case SuggestionResponse.accepted:
        updated = SuggestionHistory(
          suggestionId: id,
          accepted: true,
          refusedCount: existing?.refusedCount ?? 0,
          ignoredCount: existing?.ignoredCount ?? 0,
          lastRefused: existing?.lastRefused,
          lastIgnored: existing?.lastIgnored,
          acceptedAt: now,
        );
        break;
      case SuggestionResponse.refused:
        updated = SuggestionHistory(
          suggestionId: id,
          accepted: false,
          refusedCount: (existing?.refusedCount ?? 0) + 1,
          ignoredCount: existing?.ignoredCount ?? 0,
          lastRefused: now,
          lastIgnored: existing?.lastIgnored,
        );
        break;
      case SuggestionResponse.ignored:
        updated = SuggestionHistory(
          suggestionId: id,
          accepted: false,
          refusedCount: existing?.refusedCount ?? 0,
          ignoredCount: (existing?.ignoredCount ?? 0) + 1,
          lastRefused: existing?.lastRefused,
          lastIgnored: now,
        );
        break;
    }

    await box.put(id, updated.toMap());
  }
}
