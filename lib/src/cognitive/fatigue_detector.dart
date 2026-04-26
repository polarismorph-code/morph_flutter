import 'dart:async';

import 'package:flutter/widgets.dart';

import '../behavior/behavior_db.dart';

enum FatigueLevel { none, medium, high }

@immutable
class TapEvent {
  final DateTime timestamp;
  final bool isMissed;
  final double distance;

  const TapEvent({
    required this.timestamp,
    required this.isMissed,
    required this.distance,
  });
}

/// Estimates user cognitive fatigue from aggregate behavioral signals.
/// Operates on PATTERNS — never on content. Four signals weighted into a
/// 0..1 score:
///
///   • Missed-tap ratio over the last 10 taps   → 40%
///   • Typing slowdown (early vs late samples)  → 30%
///   • Retry count this session                 → 20%
///   • Session duration past 30 min             → 10%
///
/// Score buckets to [FatigueLevel]: ≥0.70 high, ≥0.40 medium, else none.
/// The score recompute is debounced to ≤1Hz to avoid thrashing the
/// downstream `StreamBuilder`s.
class FatigueDetector {
  final BehaviorDB db;

  FatigueDetector({required this.db});

  // Buffers — sliding windows of recent activity.
  static const int _maxTaps = 50;
  static const int _maxTypingSamples = 30;
  static const int _highScore = 70;
  static const int _mediumScore = 40;

  final List<TapEvent> _tapEvents = [];
  final List<double> _typingSpeeds = [];
  int _retryCount = 0;
  DateTime? _sessionStart;
  Timer? _analysisDebounce;

  FatigueLevel _level = FatigueLevel.none;
  final _controller = StreamController<FatigueLevel>.broadcast();

  Stream<FatigueLevel> get stream => _controller.stream;
  FatigueLevel get currentLevel => _level;

  void startSession() {
    _sessionStart = DateTime.now();
    _tapEvents.clear();
    _typingSpeeds.clear();
    _retryCount = 0;
    _level = FatigueLevel.none;
    _controller.add(_level);
  }

  /// Manually reset the detector — typically wired to a "Reset" button on
  /// the fatigue banner.
  void resetFatigue() {
    startSession();
  }

  void recordTap({
    required Offset position,
    required Offset targetCenter,
    required Size targetSize,
  }) {
    final distance = (position - targetCenter).distance;
    // Half the average dimension is "near enough to count as on-target".
    final maxDistance = (targetSize.width + targetSize.height) / 4;
    final isMissed = targetSize == Size.zero ? false : distance > maxDistance;

    _tapEvents.add(TapEvent(
      timestamp: DateTime.now(),
      isMissed: isMissed,
      distance: distance,
    ));
    if (_tapEvents.length > _maxTaps) _tapEvents.removeAt(0);
    _scheduleAnalyze();
  }

  void recordKeystroke() {
    final now = DateTime.now();
    if (_tapEvents.isNotEmpty) {
      final last = _tapEvents.last;
      final intervalMs = now.difference(last.timestamp).inMilliseconds;
      if (intervalMs > 0 && intervalMs < 5000) {
        _typingSpeeds.add(1000 / intervalMs); // keystrokes per second
        if (_typingSpeeds.length > _maxTypingSamples) {
          _typingSpeeds.removeAt(0);
        }
      }
    }
    _scheduleAnalyze();
  }

  void recordRetry() {
    _retryCount++;
    _scheduleAnalyze();
  }

  void _scheduleAnalyze() {
    _analysisDebounce?.cancel();
    _analysisDebounce = Timer(const Duration(milliseconds: 800), _analyze);
  }

  void _analyze() {
    final score = _computeScore();
    final newLevel = _bucket(score);
    if (newLevel == _level) return;
    _level = newLevel;
    _controller.add(newLevel);
    assert(() {
      debugPrint(
        '🦎 Morph fatigue: ${newLevel.name} '
        '(score: ${score.toStringAsFixed(2)})',
      );
      return true;
    }());
  }

  double _computeScore() {
    var score = 0.0;

    // Signal 1 — recent missed taps
    if (_tapEvents.length >= 10) {
      final recent = _tapEvents.sublist(_tapEvents.length - 10);
      final missed = recent.where((e) => e.isMissed).length;
      score += (missed / 10) * 0.40;
    }

    // Signal 2 — typing slowdown (compare first 5 vs last 5 samples)
    if (_typingSpeeds.length >= 10) {
      final early = _typingSpeeds.take(5).reduce((a, b) => a + b) / 5;
      final lateSamples = _typingSpeeds.sublist(_typingSpeeds.length - 5);
      final late = lateSamples.reduce((a, b) => a + b) / 5;
      if (early > 0) {
        final slowdown = (early - late) / early;
        score += slowdown.clamp(0.0, 1.0) * 0.30;
      }
    }

    // Signal 3 — retries this session
    if (_retryCount > 0) {
      score += (_retryCount / 5).clamp(0.0, 1.0) * 0.20;
    }

    // Signal 4 — long session (cognitive load builds over time)
    if (_sessionStart != null) {
      final minutes =
          DateTime.now().difference(_sessionStart!).inMinutes.toDouble();
      if (minutes > 30) {
        score += ((minutes - 30) / 60).clamp(0.0, 1.0) * 0.10;
      }
    }

    return score.clamp(0.0, 1.0);
  }

  FatigueLevel _bucket(double score) {
    if (score * 100 >= _highScore) return FatigueLevel.high;
    if (score * 100 >= _mediumScore) return FatigueLevel.medium;
    return FatigueLevel.none;
  }

  void stop() {
    _analysisDebounce?.cancel();
    _controller.close();
  }
}
