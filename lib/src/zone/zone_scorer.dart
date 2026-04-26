import 'package:flutter/foundation.dart';
import '../behavior/behavior_db.dart';

/// Computes per-zone scores from [BehaviorDB] stats and decides whether a
/// reorder is warranted. Mirrors the weighting used by the web SDK's
/// ScorerEngine.js.
class ZoneScorer {
  final BehaviorDB db;

  /// Total interactions required before the scorer will propose anything.
  final int minInteractions;

  /// Score delta between two adjacent zones that justifies swapping them.
  /// Too low → thrash; too high → never reorders.
  static const int _swapThreshold = 15;

  ZoneScorer(this.db, {this.minInteractions = 20});

  /// Returns a map of zoneId → normalized score (0..100). Returns null if
  /// there isn't enough data to draw conclusions yet.
  Future<Map<String, int>?> computeScores() async {
    final stats = await db.getAllZoneStats();
    if (stats.isEmpty) return null;

    final totalClicks = stats.values
        .fold<int>(0, (sum, s) => sum + ((s['totalClicks'] as int?) ?? 0));
    if (totalClicks < minInteractions) return null;

    // Normalize per-zone values against the max in this snapshot.
    final maxClicks = stats.values
        .map((s) => (s['totalClicks'] as int?) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxTime = stats.values
        .map((s) => (s['totalTimeMs'] as int?) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxVisits = stats.values
        .map((s) => (s['visitCount'] as int?) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);

    final out = <String, int>{};
    stats.forEach((id, s) {
      final clicks = (s['totalClicks'] as int?) ?? 0;
      final time = (s['totalTimeMs'] as int?) ?? 0;
      final visits = (s['visitCount'] as int?) ?? 0;

      final clickScore = maxClicks == 0 ? 0 : (clicks / maxClicks * 50);
      final timeScore = maxTime == 0 ? 0 : (time / maxTime * 30);
      final visitScore = maxVisits == 0 ? 0 : (visits / maxVisits * 20);

      out[id] = (clickScore + timeScore + visitScore).round();
    });
    return out;
  }

  /// Turn scores into a new order map (zoneId → orderIndex, 0-based).
  /// Returns null if the current order would win vs. a score-based sort by
  /// less than [_swapThreshold] — in that case, don't rearrange (anti-thrash).
  ///
  /// [currentPriorities] is the dev-provided static order, used as tie-break.
  Map<String, int>? shouldReorder(
    Map<String, int> scores,
    Map<String, int> currentPriorities,
  ) {
    if (scores.length < 2) return null;

    // Sort descending by score, tie-break on current priority (stable).
    final entries = scores.entries.toList()
      ..sort((a, b) {
        final bySc = b.value.compareTo(a.value);
        if (bySc != 0) return bySc;
        final pa = currentPriorities[a.key] ?? 0;
        final pb = currentPriorities[b.key] ?? 0;
        return pa.compareTo(pb);
      });

    // Don't propose a reorder if every zone's delta from its neighbor is tiny.
    var worthReordering = false;
    for (var i = 0; i < entries.length - 1; i++) {
      if ((entries[i].value - entries[i + 1].value).abs() >= _swapThreshold) {
        worthReordering = true;
        break;
      }
    }
    if (!worthReordering) return null;

    final result = <String, int>{};
    for (var i = 0; i < entries.length; i++) {
      result[entries[i].key] = i;
    }
    return result;
  }

  /// Font-scale should kick in when the user has zoomed at least [threshold]
  /// times during the observed window.
  Future<bool> shouldScaleFont({int threshold = 3}) async {
    final zoomCount = await db.getZoomCount();
    return zoomCount >= threshold;
  }
}

/// Applies a reorder map to the visible widget tree via [ChangeNotifier].
/// Widgets listen through [MorphInheritedWidget] — this class itself
/// is only the canonical source of truth.
class ZoneReorder extends ChangeNotifier {
  Map<String, int> _orderMap = const {};

  Map<String, int> get orderMap => _orderMap;

  void apply(Map<String, int> newOrder) {
    _orderMap = Map.unmodifiable(newOrder);
    notifyListeners();
  }

  void reset() {
    _orderMap = const {};
    notifyListeners();
  }

  int getOrder(String zoneId, int defaultPriority) =>
      _orderMap[zoneId] ?? defaultPriority;
}
