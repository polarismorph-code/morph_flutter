import 'package:flutter/foundation.dart';

/// Per-user baseline derived from the first few completed sessions.
///
/// Used by [FatigueDetector] to grade the *current* session against the
/// user's own normal — a tap-miss rate of 8% might be "fatigued" for a
/// careful user with a 2% baseline, but completely normal for someone
/// who naturally taps at 9%. Universal thresholds get this wrong both
/// ways. The baseline locks after [FatigueDetector.baselineSessionCount]
/// sessions and is never overwritten by later, possibly-fatigued data.
@immutable
class FatigueBaseline {
  /// Average ratio (0..1) of missed taps per session — only the first
  /// [FatigueDetector.baselineSessionCount] sessions count.
  final double missedTapRatio;

  /// Average keystrokes-per-second over the same window.
  final double typingSpeed;

  /// Number of sessions accumulated. Below
  /// [FatigueDetector.baselineSessionCount], the baseline is treated as
  /// provisional and the detector falls back to universal thresholds.
  final int sessionsRecorded;

  const FatigueBaseline({
    required this.missedTapRatio,
    required this.typingSpeed,
    required this.sessionsRecorded,
  });

  /// True once enough sessions have accumulated for the baseline to be
  /// trusted as the user's "normal".
  bool get isLocked =>
      sessionsRecorded >= FatigueBaselineLimits.requiredSessions;

  /// Folds an additional session sample into the running averages — used
  /// while the baseline is still building. After [isLocked] is true the
  /// detector should refuse to call this and treat the values as final.
  FatigueBaseline merge({
    required double missedTapRatio,
    required double typingSpeed,
  }) {
    final n = sessionsRecorded + 1;
    return FatigueBaseline(
      missedTapRatio:
          ((this.missedTapRatio * sessionsRecorded) + missedTapRatio) / n,
      typingSpeed: ((this.typingSpeed * sessionsRecorded) + typingSpeed) / n,
      sessionsRecorded: n,
    );
  }

  Map<String, Object> toMap() => {
        'missedTapRatio': missedTapRatio,
        'typingSpeed': typingSpeed,
        'sessionsRecorded': sessionsRecorded,
      };

  factory FatigueBaseline.fromMap(Map<dynamic, dynamic> raw) =>
      FatigueBaseline(
        missedTapRatio: ((raw['missedTapRatio'] as num?) ?? 0).toDouble(),
        typingSpeed: ((raw['typingSpeed'] as num?) ?? 0).toDouble(),
        sessionsRecorded: (raw['sessionsRecorded'] as int?) ?? 0,
      );

  /// Empty starting baseline — used when nothing is in storage yet.
  static const empty = FatigueBaseline(
    missedTapRatio: 0,
    typingSpeed: 0,
    sessionsRecorded: 0,
  );
}

/// Constants — split out so [FatigueBaseline.isLocked] can reference
/// them without a circular import on `FatigueDetector`.
abstract final class FatigueBaselineLimits {
  /// How many full sessions are required before the baseline is
  /// considered representative of the user's normal.
  static const int requiredSessions = 3;
}
