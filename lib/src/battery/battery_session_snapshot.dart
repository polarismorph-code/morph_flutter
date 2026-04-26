import 'package:flutter/foundation.dart';

/// Telemetry for a single foreground battery session.
///
/// Recorded by [BatteryAdapter]: it captures the level at session start,
/// the level at session end, and the duration. Aggregating across many
/// sessions gives the dev a credible "drain per minute" baseline that
/// can be used to argue Morph's energy gains in marketing material.
@immutable
class BatterySessionSnapshot {
  /// Stable session identifier — typically [BehaviorDB.startSession]'s id
  /// so a battery row joins to the same session row in `cml_sessions`.
  final String sessionId;

  /// Wall-clock millisecond timestamp at session start.
  final int startTime;

  /// Wall-clock millisecond timestamp at session end. Equal to
  /// [startTime] for sessions still in progress (rare — recorded only
  /// on graceful close).
  final int endTime;

  /// Integer percentage 0–100 reported by the OS when the session
  /// started. May be 100 for "charged" devices.
  final int batteryAtStart;

  /// Integer percentage 0–100 at session end.
  final int batteryAtEnd;

  /// True when the device was on charger for any portion of the session.
  /// Drain numbers from charged sessions should be filtered out for
  /// "natural drain" calculations.
  final bool wasCharging;

  const BatterySessionSnapshot({
    required this.sessionId,
    required this.startTime,
    required this.endTime,
    required this.batteryAtStart,
    required this.batteryAtEnd,
    required this.wasCharging,
  });

  /// Session length in seconds. Always positive — sessions of zero
  /// duration are dropped at write time.
  int get durationSeconds => ((endTime - startTime) / 1000).round();

  /// Net drop in battery percent. Negative when the device gained
  /// charge (started uncharged, was plugged in mid-session).
  int get batteryDrop => batteryAtStart - batteryAtEnd;

  /// Drain in percent per minute. Returns `null` for sessions shorter
  /// than 30 seconds — too noisy to be meaningful.
  double? get drainPerMinute {
    final seconds = durationSeconds;
    if (seconds < 30) return null;
    return batteryDrop / (seconds / 60);
  }

  Map<String, Object> toMap() => {
        'sessionId': sessionId,
        'startTime': startTime,
        'endTime': endTime,
        'batteryAtStart': batteryAtStart,
        'batteryAtEnd': batteryAtEnd,
        'wasCharging': wasCharging,
      };

  factory BatterySessionSnapshot.fromMap(Map<dynamic, dynamic> raw) =>
      BatterySessionSnapshot(
        sessionId: raw['sessionId'] as String? ?? '',
        startTime: (raw['startTime'] as int?) ?? 0,
        endTime: (raw['endTime'] as int?) ?? 0,
        batteryAtStart: (raw['batteryAtStart'] as int?) ?? 0,
        batteryAtEnd: (raw['batteryAtEnd'] as int?) ?? 0,
        wasCharging: (raw['wasCharging'] as bool?) ?? false,
      );
}

/// Aggregated stats over a window of [BatterySessionSnapshot]s, returned
/// by [BatteryAdapter.getSessionStats]. All fields are derived — no
/// raw storage. Safe to expose in dev dashboards.
@immutable
class BatterySessionStats {
  /// Number of sessions included in the aggregation.
  final int sessionCount;

  /// Total time across all sessions, in seconds.
  final int totalSeconds;

  /// Average drain in percent per minute, computed only over sessions
  /// where [BatterySessionSnapshot.wasCharging] is false AND duration
  /// passes the 30-second floor. Null when no qualifying sessions.
  final double? averageDrainPerMinute;

  /// Median session length in seconds — robust to outlier "left the app
  /// open overnight" runs that would skew the mean.
  final int medianSessionSeconds;

  const BatterySessionStats({
    required this.sessionCount,
    required this.totalSeconds,
    required this.averageDrainPerMinute,
    required this.medianSessionSeconds,
  });

  static const empty = BatterySessionStats(
    sessionCount: 0,
    totalSeconds: 0,
    averageDrainPerMinute: null,
    medianSessionSeconds: 0,
  );
}
