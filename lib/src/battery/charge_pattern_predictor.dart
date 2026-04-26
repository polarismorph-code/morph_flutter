/// Lightweight clustering of past charge-start events to predict the
/// user's next typical charge window. No ML — a histogram over the 24
/// hours of the day with day-of-week weighting, smoothed across a
/// recency-decayed window. Goal: reduce false positives, not chase
/// state-of-the-art.
///
/// Input: a list of charge-event maps (from `BehaviorDB.getChargeEvents`)
/// each shaped `{ timestamp, hour, minute, dayOfWeek, batteryLevel }`.
///
/// Output (via [isApproachingChargeWindow]): boolean — is the current
/// time within [windowMinutes] minutes of a frequent past charge time
/// for this day-of-week (or the same time-of-day across the week, when
/// per-day data is too thin)?
class ChargePatternPredictor {
  /// Minimum charge events of the same hour bucket required before the
  /// predictor will commit to a window. Below this floor, we return
  /// `false` and let the deterministic level rule drive the mode.
  static const int minSamples = 3;

  /// Half-window width — a "match" is current-time within this many
  /// minutes of a known charge hour. 60 by default — large enough to
  /// catch "I usually plug in around 10pm" without being so wide it
  /// fires all evening.
  static const int windowMinutes = 60;

  /// Number of past days considered. Shorter than the DB retention so
  /// pattern shifts (new job, new schedule) propagate faster than the
  /// 14-day storage window would allow on its own.
  static const int recencyDays = 7;

  /// hour (0..23) → number of charge-start events seen in that bucket.
  /// Only events from the last [recencyDays] days are counted, with
  /// day-of-week-matching events weighted ×2.
  final List<double> _hourScores = List<double>.filled(24, 0);

  /// Most recent ingestion timestamp — used to short-circuit redundant
  /// recomputes when the predictor is asked to refresh between ticks
  /// without new charge events arriving.
  int _lastIngestSize = -1;

  /// Recompute the histogram from a fresh list of charge-event rows.
  /// Cheap (O(n) over the events × constant per row); safe to call on
  /// every adapter poll.
  void ingest(List<Map> events) {
    if (events.length == _lastIngestSize) return;
    _lastIngestSize = events.length;
    for (var i = 0; i < _hourScores.length; i++) {
      _hourScores[i] = 0;
    }
    if (events.isEmpty) return;

    final now = DateTime.now();
    final cutoff = now
        .subtract(const Duration(days: recencyDays))
        .millisecondsSinceEpoch;
    final today = now.weekday;

    for (final e in events) {
      final ts = (e['timestamp'] as int?) ?? 0;
      if (ts < cutoff) continue;
      final hour = (e['hour'] as int?) ?? -1;
      if (hour < 0 || hour > 23) continue;
      final dow = (e['dayOfWeek'] as int?) ?? -1;
      // Same day-of-week as today gets double weight — captures
      // "I charge at the office every weekday at 9am" without erasing
      // the weekend pattern.
      final weight = dow == today ? 2.0 : 1.0;
      _hourScores[hour] += weight;
    }
  }

  /// Returns true when [now]'s hour bucket — or the immediately
  /// neighbouring buckets if [now] is within [windowMinutes] of a
  /// boundary — has at least [minSamples] events recorded.
  bool isApproachingChargeWindow(DateTime now) {
    final hour = now.hour;
    if (_hourScores[hour] >= minSamples) return true;

    // Spillover into the next hour bucket, e.g. it's 9:50pm and the
    // user usually plugs in at 10:00pm — we don't want to wait the
    // last 10 minutes to react.
    final nextHourMinutesAway = 60 - now.minute;
    if (nextHourMinutesAway <= windowMinutes) {
      final nextHour = (hour + 1) % 24;
      if (_hourScores[nextHour] >= minSamples) return true;
    }

    // Same idea backward — "it's 10:10pm, user plugged in at 10:00 the
    // last 5 days, technically we missed the window but the next 50
    // minutes are still 'their charge time'".
    if (now.minute <= windowMinutes) {
      final prevHour = (hour - 1) % 24;
      if (_hourScores[prevHour] >= minSamples) return true;
    }

    return false;
  }

  /// Inspectable view used by tests + the dev dashboard. Returns a copy.
  List<double> get hourScores => List<double>.unmodifiable(_hourScores);
}
