import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../behavior/behavior_db.dart';
import '../config/endpoints.dart';
import '../license/app_identity.dart';
import '../navigation/morph_navigator_observer.dart';
import 'morph_analytics_config.dart';

/// Pushes anonymized aggregates to `/api/flutter/behavior/report` on the
/// dev's [config.uploadInterval]. Runs **only** when [config.canUpload] is
/// true — otherwise stays dormant.
///
/// The payload is intentionally coarse: aggregated zone scores, confirmed
/// sequences, scroll summary, zoom count, an opaque app hash, and a
/// month-only timestamp. See [MorphAnalyticsConfig] for the full
/// privacy contract (what's sent vs. never sent).
class AnalyticsReporter {
  final String licenseKey;
  final MorphAnalyticsConfig config;
  final BehaviorDB db;

  Timer? _uploadTimer;
  bool _started = false;

  AnalyticsReporter({
    required this.licenseKey,
    required this.config,
    required this.db,
  });

  /// Idempotent — calling twice is a no-op. Triggers the consent callback
  /// when [config.enabled] is true but the user hasn't consented yet.
  void start() {
    if (_started) return;
    _started = true;

    if (!config.canUpload) {
      // Enabled but no consent → notify the dev so they can show their
      // banner. Disabled entirely → silent (this is the privacy default).
      if (config.enabled && !config.userConsent) {
        config.onConsentRequired?.call();
        assert(() {
          debugPrint(
            '🦎 Morph Analytics: enabled but userConsent is false.\n'
            'No data will be sent until userConsent is true.\n'
            'Use onConsentRequired to show your consent banner.',
          );
          return true;
        }());
      }
      return;
    }

    _uploadTimer = Timer.periodic(
      config.uploadInterval,
      (_) => _upload(),
    );
    // First upload immediately so the dashboard sees activity within minutes,
    // not days.
    unawaited(_upload());
  }

  /// Stop the timer and forget any pending uploads. Call on
  /// [MorphProvider.dispose] or when revoking consent.
  void dispose() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _started = false;
  }

  /// Force an immediate upload. Honors the same gates as the timer
  /// (consent + [minInteractions]). Useful in dev to verify the
  /// pipeline without waiting for the next [uploadInterval], or to
  /// flush data right after onboarding completion.
  ///
  /// Returns true when a request was actually sent, false when the
  /// upload was skipped (no consent, not enough data, or network
  /// failure — check the debug logs for the reason).
  Future<bool> flush() async {
    if (!config.canUpload) return false;
    final payload = await _buildPayload();
    if (payload == null) return false;
    try {
      final uri = Uri.parse(
        '$kMorphApiBaseUrl/api/flutter/behavior/report',
      );
      final res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _upload() async {
    if (!config.canUpload) return;
    try {
      final payload = await _buildPayload();
      if (payload == null) return; // not enough data yet

      final uri = Uri.parse(
        '$kMorphApiBaseUrl/api/flutter/behavior/report',
      );
      final res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        assert(() {
          debugPrint('🦎 Morph Analytics: report sent successfully');
          return true;
        }());
      } else {
        assert(() {
          debugPrint(
            '🦎 Morph Analytics: report rejected '
            '(status ${res.statusCode}) — will retry next cycle',
          );
          return true;
        }());
      }
    } catch (e) {
      // Network errors are expected on flaky connections — retry next cycle,
      // never crash the host app.
      debugPrint('🦎 Morph Analytics upload failed: $e');
    }
  }

  /// Returns null when there's not enough behavior to be useful (under 20
  /// total clicks across all zones). Backend would just see noise otherwise.
  Future<Map<String, dynamic>?> _buildPayload() async {
    final allStats = await db.getAllZoneStats();
    if (allStats.isEmpty) return null;

    final totalInteractions = allStats.values.fold<int>(
      0,
      (sum, z) => sum + ((z['totalClicks'] as int?) ?? 0),
    );
    if (totalInteractions < config.minInteractions) return null;

    final zoneScores = <String, double>{};
    allStats.forEach((zoneId, stats) {
      zoneScores[zoneId] = _computeScore(stats);
    });

    // Only sequences with at least 5 occurrences are statistically meaningful;
    // smaller counts are noise.
    final sequences = await db.getSequences();
    final confirmedSeqs = <Map<String, dynamic>>[];
    for (final s in sequences) {
      final count = (s['count'] as int?) ?? 0;
      if (count < 5) continue;
      final from = s['from'] as String?;
      final to = s['to'] as String?;
      if (from == null || to == null) continue;
      final fromClicks = (allStats[from]?['totalClicks'] as int?) ?? 1;
      confirmedSeqs.add({
        'from': from,
        'to': to,
        'confidence': count / (fromClicks == 0 ? 1 : fromClicks),
      });
    }

    final scrollSummary = await db.getScrollSummary();
    final zoomCount = await db.getZoomCount();
    final navigation = await _buildNavigationBlock(allStats);

    return {
      'licenseKey': licenseKey,
      // Origin-binding payload — backend matches against
      // allowed_packages[platform] before processing the report.
      'appId': AppIdentity.cachedOrEmpty,
      'appHash': _hashApp(),
      'platform': _platform(),

      // Aggregates only — no raw click stream, no timestamps.
      'zoneScores': zoneScores,
      'sequences': confirmedSeqs,
      if (scrollSummary != null) 'scrollSummary': scrollSummary,
      'zoomCount': zoomCount,

      // Anonymized navigation block — page scores, confirmed sequences,
      // top journeys, entry/exit pages, average depth. All routes are the
      // dev-defined paths from the router; we never see real IDs.
      if (navigation != null) 'navigation': navigation,

      // Time bucket — month resolution, never the exact date.
      'month': _currentMonth(),
    };
  }

  /// Builds the `navigation` payload block by walking the page-level stats
  /// produced by [MorphNavigatorObserver] (via [BehaviorDB]) and the
  /// in-memory [MorphNavigatorObserver.sessionHistory]. Returns null
  /// when no navigation has been observed (no point sending an empty
  /// block).
  Future<Map<String, dynamic>?> _buildNavigationBlock(
    Map<String, Map<String, dynamic>> zoneStatsForFallback,
  ) async {
    final pageStats = await db.getAllPageStats();
    if (pageStats.isEmpty) return null;

    final allSequences = await db.getSequences();

    // Page scores — same shape as zone scores, weighted toward visits and
    // dwell time (people-spend-time-here-and-come-back).
    final pageScores = <String, double>{};
    pageStats.forEach((route, stats) {
      pageScores[route] = _computePageScore(
        visitCount: (stats['visitCount'] as int?) ?? 0,
        totalTimeMs: (stats['totalTimeMs'] as int?) ?? 0,
        lastSeen: (stats['lastSeen'] as int?) ?? 0,
      );
    });

    // Cross-page sequences with at least 5 confirmations. Both endpoints
    // must be known pages (the route name appears in pageStats).
    final confirmedNavSeqs = <Map<String, dynamic>>[];
    for (final s in allSequences) {
      final from = s['from'] as String?;
      final to = s['to'] as String?;
      final count = (s['count'] as int?) ?? 0;
      if (from == null || to == null || count < 5) continue;
      if (!pageStats.containsKey(from) || !pageStats.containsKey(to)) continue;
      final fromVisits = (pageStats[from]?['visitCount'] as int?) ?? 1;
      confirmedNavSeqs.add({
        'from': from,
        'to': to,
        'count': count,
        'confidence': count / (fromVisits == 0 ? 1 : fromVisits),
      });
    }
    confirmedNavSeqs.sort(
      (a, b) => (b['count'] as int).compareTo(a['count'] as int),
    );

    final topJourneys = _buildJourneys(confirmedNavSeqs);

    return {
      'pageScores': pageScores,
      'confirmedSequences': confirmedNavSeqs,
      'topJourneys': topJourneys,
      'uniquePagesCount': pageStats.length,
      'mostCommonEntryPage': _findEntryPage(pageStats),
      'mostCommonExitPage': _findExitPage(pageStats),
      'avgNavigationDepth': _avgDepth(),
    };
  }

  /// Page score in [0, 1]. Weighted: visits (40%), dwell time (35%),
  /// recency (25%). Different mix from zones — pages reward sustained
  /// attention more than raw click count.
  double _computePageScore({
    required int visitCount,
    required int totalTimeMs,
    required int lastSeen,
  }) {
    final normVisits = (visitCount / 50).clamp(0.0, 1.0);
    final normTime = (totalTimeMs / 300000).clamp(0.0, 1.0); // 5 min ceiling
    final lastSeenDate = DateTime.fromMillisecondsSinceEpoch(lastSeen);
    final daysSince = DateTime.now().difference(lastSeenDate).inDays;
    final normRecency = (1 - daysSince / 7).clamp(0.0, 1.0);

    return normVisits * 0.40 + normTime * 0.35 + normRecency * 0.25;
  }

  /// Chains pairwise sequences into longer journeys (A→B + B→C => A→B→C).
  /// Returns the top 10 by count. Used by the dashboard to visualize the
  /// most common multi-step paths.
  List<Map<String, dynamic>> _buildJourneys(
    List<Map<String, dynamic>> pairs,
  ) {
    final journeys = <Map<String, dynamic>>[];

    // Seed with the pairwise sequences themselves.
    for (final p in pairs) {
      journeys.add({
        'path': [p['from'] as String, p['to'] as String],
        'count': p['count'] as int,
      });
    }

    // Chain every pair with a continuation that starts where it ends.
    for (final j in List<Map<String, dynamic>>.from(journeys)) {
      final lastPage = (j['path'] as List).last as String;
      for (final p in pairs) {
        if (p['from'] == lastPage && p['to'] != lastPage) {
          final chainedCount =
              (j['count'] as int) < (p['count'] as int)
                  ? j['count'] as int
                  : p['count'] as int;
          journeys.add({
            'path': [...(j['path'] as List), p['to'] as String],
            'count': chainedCount,
          });
        }
      }
    }

    journeys.sort(
      (a, b) => (b['count'] as int).compareTo(a['count'] as int),
    );
    return journeys.take(10).toList();
  }

  /// Heuristic entry page: the route with the smallest [firstSeen] (it was
  /// seen earliest in the session window). Falls back to the most-visited
  /// page if no firstSeen data is available.
  String? _findEntryPage(Map<String, Map<String, dynamic>> pageStats) {
    if (pageStats.isEmpty) return null;
    Map<String, dynamic>? best;
    String? bestRoute;
    for (final entry in pageStats.entries) {
      final firstSeen = (entry.value['firstSeen'] as int?) ?? 0;
      if (best == null ||
          firstSeen < ((best['firstSeen'] as int?) ?? 0)) {
        best = entry.value;
        bestRoute = entry.key;
      }
    }
    return bestRoute;
  }

  /// Heuristic exit page: the route with the smallest count of OUTGOING
  /// sequences (people land here and don't navigate further). Falls back
  /// to null when nothing qualifies.
  String? _findExitPage(Map<String, Map<String, dynamic>> pageStats) {
    if (pageStats.isEmpty) return null;
    // The route appearing most often as the LAST entry in session history
    // is a good proxy for "where users stop".
    final history = MorphNavigatorObserver.instance.sessionHistory;
    if (history.isNotEmpty) return history.last;
    // Fallback: route with highest visit count and lowest "outgoing"
    // signal — without that signal we just return the most visited.
    String? winner;
    int maxVisits = -1;
    for (final entry in pageStats.entries) {
      final visits = (entry.value['visitCount'] as int?) ?? 0;
      if (visits > maxVisits) {
        maxVisits = visits;
        winner = entry.key;
      }
    }
    return winner;
  }

  /// Average number of pages per session = current session history length.
  /// Coarse but useful — the dashboard shows the trend over months.
  double _avgDepth() {
    final history = MorphNavigatorObserver.instance.sessionHistory;
    if (history.isEmpty) return 0;
    return history.length.toDouble();
  }

  /// Weighted score in [0, 1]. Same shape as the JS web SDK so backend
  /// dashboards display Flutter and React side-by-side.
  double _computeScore(Map<String, dynamic> stats) {
    final totalClicks = (stats['totalClicks'] as int?) ?? 0;
    final totalTimeMs = (stats['totalTimeMs'] as int?) ?? 0;
    final visitCount = (stats['visitCount'] as int?) ?? 0;
    final lastSeenMs = (stats['lastSeen'] as int?) ?? 0;

    final normClicks = (totalClicks / 100).clamp(0.0, 1.0);
    final normTime = (totalTimeMs / 60000).clamp(0.0, 1.0);
    final normVisits = (visitCount / 30).clamp(0.0, 1.0);

    final lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
    final daysSince = DateTime.now().difference(lastSeen).inDays;
    final normRecency = (1 - daysSince / 7).clamp(0.0, 1.0);

    return normClicks * 0.35 +
        normTime * 0.30 +
        normVisits * 0.20 +
        normRecency * 0.15;
  }

  /// Deterministic SHA-256 derivative of (licenseKey, platform). Same app
  /// always hashes to the same 16-char prefix; the underlying license/app id
  /// is not recoverable from the hash.
  String _hashApp() {
    final input = '${licenseKey}_${_platform()}';
    final digest = sha256.convert(utf8.encode(input));
    return digest.toString().substring(0, 16);
  }

  String _platform() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }
}
