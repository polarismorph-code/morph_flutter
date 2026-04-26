import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../recovery/recovery_snapshot.dart';

/// Hive-backed behavioral store — the Flutter equivalent of BehaviorDB.js
/// (which uses IndexedDB on the web). Six boxes: clicks, time, sequences,
/// zooms, sessions, scroll. Auto-cleanup of entries older than [retentionDays]
/// (capped at 30) runs at init() and then every 24h.
///
/// All data stays on device unless the dev opts in via
/// [MorphAnalyticsConfig] — see analytics/analytics_reporter.dart.
class BehaviorDB {
  static const String clicksBox = 'cml_clicks';
  static const String timeBox = 'cml_time';
  static const String sequencesBox = 'cml_seq';
  static const String zoomBox = 'cml_zoom';
  static const String sessionsBox = 'cml_sessions';
  static const String scrollBox = 'cml_scroll';
  static const String snapshotsBox = 'cml_snapshots';
  static const String prefsBox = 'cml_prefs';

  /// Hard ceiling — we refuse to keep behavioral data longer than this no
  /// matter what the dev configures. Privacy floor.
  static const int maxRetentionDays = 30;

  /// Effective retention. Set via [init], clamped to [maxRetentionDays].
  int _retentionDays = maxRetentionDays;
  Duration get _maxAge => Duration(days: _retentionDays);

  bool _initialized = false;
  Timer? _cleanupTimer;

  /// [retentionDays] is the dev-requested retention; it is clamped to
  /// [maxRetentionDays] silently (the [MorphAnalyticsConfig] constructor
  /// throws if the dev passes > 30 — so by the time we get here it should
  /// already be valid).
  Future<void> init({int retentionDays = maxRetentionDays}) async {
    if (_initialized) return;
    _retentionDays = retentionDays.clamp(1, maxRetentionDays);
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<Map>(clicksBox),
      Hive.openBox<Map>(timeBox),
      Hive.openBox<Map>(sequencesBox),
      Hive.openBox<Map>(zoomBox),
      Hive.openBox<Map>(sessionsBox),
      Hive.openBox<Map>(scrollBox),
      Hive.openBox<Map>(snapshotsBox),
      Hive.openBox(prefsBox),
    ]);
    // Run once at boot, then every 24h — keep both off the main thread by
    // letting the Hive futures resolve naturally. No `await` on the timer
    // itself.
    await _cleanup();
    _startDailyCleanup();
    _initialized = true;
  }

  void _startDailyCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => _cleanup(),
    );
  }

  /// Close all boxes. Call from [MorphProvider.dispose].
  Future<void> close() async {
    if (!_initialized) return;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await Hive.close();
    _initialized = false;
  }

  // ─── TRACKING ────────────────────────────────────────────────────────────

  Future<void> trackClick(String zoneId, String type) async {
    // Tracking can be invoked from a NavigatorObserver before _bootstrap has
    // finished opening the boxes (first navigation fires before
    // addPostFrameCallback). Bail silently rather than throwing.
    if (!_initialized) return;
    final box = Hive.box<Map>(clicksBox);
    final now = DateTime.now().millisecondsSinceEpoch;
    await box.put('${zoneId}_$now', {
      'zoneId': zoneId,
      'type': type,
      'timestamp': now,
    });
  }

  Future<void> trackTimeSpent(String zoneId, int milliseconds) async {
    if (!_initialized) return;
    if (milliseconds < 500) return; // ignore flashes
    final box = Hive.box<Map>(timeBox);
    final existing = box.get(zoneId) ?? <dynamic, dynamic>{};
    await box.put(zoneId, {
      'zoneId': zoneId,
      'total': ((existing['total'] as int?) ?? 0) + milliseconds,
      'count': ((existing['count'] as int?) ?? 0) + 1,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> trackSequence(String fromId, String toId) async {
    if (!_initialized) return;
    if (fromId == toId) return;
    final box = Hive.box<Map>(sequencesBox);
    final key = '$fromId→$toId';
    final existing = box.get(key) ?? <dynamic, dynamic>{};
    await box.put(key, {
      'from': fromId,
      'to': toId,
      'count': ((existing['count'] as int?) ?? 0) + 1,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// A zoom is recorded only when the system text-scale factor crosses 1.2×.
  Future<void> trackZoom(double scaleFactor) async {
    if (!_initialized) return;
    if (scaleFactor < 1.2) return;
    final box = Hive.box<Map>(zoomBox);
    final existing = box.get('zoom') ?? <dynamic, dynamic>{};
    await box.put('zoom', {
      'count': ((existing['count'] as int?) ?? 0) + 1,
      'lastScale': scaleFactor,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Aggregated scroll snapshot per session. [behavior] is one of
  /// 'reading' | 'browsing' | 'skipping' (the dev's classifier decides).
  Future<void> trackScrollSample({
    required double depth,
    required double speed,
    required String behavior,
  }) async {
    if (!_initialized) return;
    final box = Hive.box<Map>(scrollBox);
    final existing = box.get('summary') ?? <dynamic, dynamic>{};
    final sampleCount = ((existing['sampleCount'] as int?) ?? 0) + 1;
    final prevDepth = (existing['avgDepth'] as num?)?.toDouble() ?? 0;
    final prevSpeed = (existing['avgSpeed'] as num?)?.toDouble() ?? 0;
    // Running mean — cheap and stable enough for an aggregated metric.
    final avgDepth = prevDepth + (depth - prevDepth) / sampleCount;
    final avgSpeed = prevSpeed + (speed - prevSpeed) / sampleCount;

    final behaviorTallies = Map<String, int>.from(
      (existing['behaviorTallies'] as Map?)?.cast<String, int>() ?? const {},
    );
    behaviorTallies[behavior] = (behaviorTallies[behavior] ?? 0) + 1;
    final dominant = behaviorTallies.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    await box.put('summary', {
      'avgDepth': avgDepth,
      'avgSpeed': avgSpeed,
      'dominantBehavior': dominant,
      'behaviorTallies': behaviorTallies,
      'sampleCount': sampleCount,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<String> startSession() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final box = Hive.box<Map>(sessionsBox);
    await box.put(id, {
      'id': id,
      'start': DateTime.now().millisecondsSinceEpoch,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  Future<void> endSession(String sessionId) async {
    if (sessionId.isEmpty) return;
    final box = Hive.box<Map>(sessionsBox);
    final existing = box.get(sessionId);
    if (existing == null) return;
    await box.put(sessionId, {
      ...existing,
      'end': DateTime.now().millisecondsSinceEpoch,
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ─── QUERIES ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getZoneStats(String zoneId) async {
    final clicksB = Hive.box<Map>(clicksBox);
    final timeB = Hive.box<Map>(timeBox);

    var clicks = 0;
    var lastClickTs = 0;
    for (final key in clicksB.keys) {
      final v = clicksB.get(key);
      if (v?['zoneId'] == zoneId) {
        clicks++;
        final ts = (v?['timestamp'] as int?) ?? 0;
        if (ts > lastClickTs) lastClickTs = ts;
      }
    }

    final time = timeB.get(zoneId);
    final lastTimeTs = (time?['lastSeen'] as int?) ?? 0;

    return {
      'zoneId': zoneId,
      'totalClicks': clicks,
      'totalTimeMs': (time?['total'] as int?) ?? 0,
      'visitCount': (time?['count'] as int?) ?? 0,
      'lastSeen': lastClickTs > lastTimeTs ? lastClickTs : lastTimeTs,
    };
  }

  Future<Map<String, Map<String, dynamic>>> getAllZoneStats() async {
    final clicksB = Hive.box<Map>(clicksBox);
    final timeB = Hive.box<Map>(timeBox);
    final ids = <String>{};

    for (final key in clicksB.keys) {
      final v = clicksB.get(key);
      final id = v?['zoneId'] as String?;
      if (id != null) ids.add(id);
    }
    for (final key in timeB.keys) {
      ids.add(key.toString());
    }

    final result = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      final stats = await getZoneStats(id);
      if (stats != null) result[id] = stats;
    }
    return result;
  }

  Future<int> getZoomCount() async {
    final data = Hive.box<Map>(zoomBox).get('zoom');
    return (data?['count'] as int?) ?? 0;
  }

  Future<int> getSessionCount() async {
    if (!_initialized) return 0;
    return Hive.box<Map>(sessionsBox).length;
  }

  /// Total recorded clicks across all zones — both UI taps and the
  /// `'navigation'` taps emitted by [MorphNavigatorObserver]. Used by
  /// [SuggestionEngine] as the gating "20+ interactions" threshold so we
  /// don't pop suggestions on a brand-new install.
  Future<int> getTotalInteractions() async {
    if (!_initialized) return 0;
    return Hive.box<Map>(clicksBox).length;
  }

  /// Number of sessions that started in [hour] (0–23, local time). Powers
  /// the time-of-day suggestions ("you often use the app at night").
  Future<int> getSessionsByHour(int hour) async {
    if (!_initialized) return 0;
    if (hour < 0 || hour > 23) return 0;
    final box = Hive.box<Map>(sessionsBox);
    var count = 0;
    for (final key in box.keys) {
      final v = box.get(key);
      final start = v?['start'] as int?;
      if (start == null) continue;
      final ts = DateTime.fromMillisecondsSinceEpoch(start);
      if (ts.hour == hour) count++;
    }
    return count;
  }

  Future<List<Map<String, dynamic>>> getSequences() async {
    final box = Hive.box<Map>(sequencesBox);
    return box.values
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Per-route stats — visit count, dwell time, last seen — computed by
  /// filtering clicks where `type == 'navigation'` (set by
  /// [MorphNavigatorObserver]) and joining with the time box.
  ///
  /// Returns a map keyed by route name. Each value contains:
  ///   • `visitCount` — number of visits this session window
  ///   • `totalTimeMs` — cumulative dwell time across all visits
  ///   • `lastSeen` — epoch ms of the most recent visit
  ///   • `firstSeen` — epoch ms of the earliest visit (entry-page heuristic)
  ///
  /// Route names already arrive normalized in production (the dev-defined
  /// route paths like `/home`, `/profile`) — we don't try to strip dynamic
  /// path segments here. If the dev wants `/product/:id` instead of
  /// `/product/123` they should set the route name to the template.
  Future<Map<String, Map<String, dynamic>>> getAllPageStats() async {
    if (!_initialized) return const {};
    final clicksB = Hive.box<Map>(clicksBox);
    final timeB = Hive.box<Map>(timeBox);

    final stats = <String, Map<String, dynamic>>{};

    // Walk clicks once, accumulate visit counts and timestamps per route.
    for (final key in clicksB.keys) {
      final v = clicksB.get(key);
      if (v == null) continue;
      if (v['type'] != 'navigation') continue;
      final route = v['zoneId'] as String?;
      if (route == null) continue;
      final ts = (v['timestamp'] as int?) ?? 0;

      final entry = stats.putIfAbsent(route, () => {
            'route': route,
            'visitCount': 0,
            'totalTimeMs': 0,
            'lastSeen': 0,
            'firstSeen': ts,
          });
      entry['visitCount'] = (entry['visitCount'] as int) + 1;
      if (ts > (entry['lastSeen'] as int)) entry['lastSeen'] = ts;
      if (ts < (entry['firstSeen'] as int)) entry['firstSeen'] = ts;
    }

    // Layer in dwell time from the time box (populated by the observer).
    for (final entry in stats.entries) {
      final timeRow = timeB.get(entry.key);
      if (timeRow == null) continue;
      entry.value['totalTimeMs'] = (timeRow['total'] as int?) ?? 0;
      final timeLast = (timeRow['lastSeen'] as int?) ?? 0;
      if (timeLast > (entry.value['lastSeen'] as int)) {
        entry.value['lastSeen'] = timeLast;
      }
    }

    return stats;
  }

  /// Returns the running scroll summary or null if nothing was tracked.
  Future<Map<String, dynamic>?> getScrollSummary() async {
    final raw = Hive.box<Map>(scrollBox).get('summary');
    if (raw == null) return null;
    return {
      'avgDepth': (raw['avgDepth'] as num?)?.toDouble() ?? 0.0,
      'avgSpeed': (raw['avgSpeed'] as num?)?.toDouble() ?? 0.0,
      'dominantBehavior': raw['dominantBehavior'] as String? ?? 'browsing',
    };
  }

  // ─── RECOVERY SNAPSHOTS ──────────────────────────────────────────────────

  /// Persist the current screen's recovery snapshot. Called from
  /// [InterruptionRecovery] right before the app is paused so we can
  /// rebuild a "Continue where you left off" suggestion later.
  Future<void> saveSnapshot(RecoverySnapshot snapshot) async {
    if (!_initialized) return;
    await Hive.box<Map>(snapshotsBox).put(snapshot.id, snapshot.toMap());
  }

  /// Newest unused snapshot, or null when nothing is saved. Used by
  /// [InterruptionRecovery._onSignificantInterruption] on resume.
  Future<RecoverySnapshot?> getLastSnapshot() async {
    if (!_initialized) return null;
    final box = Hive.box<Map>(snapshotsBox);
    if (box.isEmpty) return null;
    final entries = box.values
        .map((m) => RecoverySnapshot.fromMap(m))
        .where((s) => !s.used)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries.isEmpty ? null : entries.first;
  }

  /// Mark a snapshot consumed so it doesn't trigger another suggestion.
  /// Called from the recovery suggestion's `action` after the user taps
  /// "Resume".
  Future<void> markSnapshotUsed(String id) async {
    if (!_initialized) return;
    final box = Hive.box<Map>(snapshotsBox);
    final raw = box.get(id);
    if (raw == null) return;
    final snap = RecoverySnapshot.fromMap(raw).copyWith(used: true);
    await box.put(id, snap.toMap());
  }

  // ─── PREFERENCES ─────────────────────────────────────────────────────────
  //
  // Lightweight key/value store for scalar preferences inferred at runtime
  // (last detected grip hand, battery saver acceptance, …). Lives in the
  // same Hive realm as the rest so [clearAll] wipes it too.

  Future<void> saveGripPreference({
    required String hand,
    required String posture,
  }) async {
    if (!_initialized) return;
    await Hive.box(prefsBox).putAll({
      'grip.hand': hand,
      'grip.posture': posture,
      'grip.updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> saveBatteryPreference(String value) async {
    if (!_initialized) return;
    await Hive.box(prefsBox).put('battery.preference', value);
  }

  /// Generic accessor — useful for tests and the privacy screen.
  Object? readPreference(String key) {
    if (!_initialized) return null;
    return Hive.box(prefsBox).get(key);
  }

  // ─── STORAGE / GDPR HELPERS ──────────────────────────────────────────────

  /// Approximate on-disk size in kilobytes — cheap estimate (sums entry
  /// counts × a heuristic per-entry weight). Good enough for a "Local data
  /// size: 14 KB" UI line in a privacy screen.
  Future<int> getSize() async {
    if (!_initialized) return 0;
    const perEntryBytes = 256; // rough average
    const mapBoxes = [
      clicksBox,
      timeBox,
      sequencesBox,
      zoomBox,
      sessionsBox,
      scrollBox,
      snapshotsBox,
    ];
    var total = 0;
    for (final name in mapBoxes) {
      total += Hive.box<Map>(name).length * perEntryBytes;
    }
    total += Hive.box(prefsBox).length * 64; // prefs are small scalars
    return (total / 1024).ceil();
  }

  /// Hard delete every behavioral row across all boxes. Wired to the privacy
  /// settings "Clear local data" / consent revocation flow.
  Future<void> clearAll() async {
    if (!_initialized) return;
    const mapBoxes = [
      clicksBox,
      timeBox,
      sequencesBox,
      zoomBox,
      sessionsBox,
      scrollBox,
      snapshotsBox,
    ];
    for (final name in mapBoxes) {
      await Hive.box<Map>(name).clear();
    }
    await Hive.box(prefsBox).clear();
    assert(() {
      debugPrint('🦎 Morph: all local behavioral data cleared');
      return true;
    }());
  }

  // ─── CLEANUP ─────────────────────────────────────────────────────────────

  Future<void> _cleanup() async {
    final cutoff = DateTime.now().subtract(_maxAge).millisecondsSinceEpoch;
    const boxes = [
      clicksBox,
      timeBox,
      sequencesBox,
      zoomBox,
      sessionsBox,
      scrollBox,
      snapshotsBox,
    ];
    for (final name in boxes) {
      try {
        final box = Hive.box<Map>(name);
        final toDelete = <dynamic>[];
        for (final key in box.keys) {
          final v = box.get(key);
          if (v == null) continue;
          final ts = (v['lastSeen'] as int?) ??
              (v['timestamp'] as int?) ??
              (v['start'] as int?) ??
              (v['updatedAt'] as int?);
          if (ts != null && ts < cutoff) toDelete.add(key);
        }
        if (toDelete.isNotEmpty) {
          await box.deleteAll(toDelete);
          assert(() {
            debugPrint(
              '🦎 Morph cleanup: deleted ${toDelete.length} '
              'entries from $name (older than $_retentionDays days)',
            );
            return true;
          }());
        }
      } catch (e) {
        // Cleanup must NEVER crash the app. Log and move on.
        debugPrint('🦎 Morph cleanup error on $name: $e');
      }
    }
  }
}
