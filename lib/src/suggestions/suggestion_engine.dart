import 'package:flutter/material.dart';

import '../battery/battery_adapter.dart';
import '../behavior/behavior_db.dart';
import '../navigation/morph_navigator_observer.dart';
import '../recovery/interruption_recovery.dart';
import '../zone/zone_scorer.dart';
import 'morph_suggestion.dart';
import 'suggestion_history.dart';

/// Type of the dev-provided callback that switches the host app to dark
/// mode. Wired via [MorphProvider.onDarkModeRequested]. The dev's
/// implementation typically toggles their own ThemeMode controller (e.g. a
/// Riverpod provider).
typedef DarkModeRequestCallback = void Function(BuildContext context);

/// Type of the dev-provided callback that scrolls a screen back to the
/// position the user left it at. The depth is a percentage (0..100). Wired
/// via [MorphProvider.onResumePosition].
typedef ResumePositionCallback = void Function(String route, double depth);

/// Reads BehaviorDB + the navigator observer to produce contextual
/// suggestions. The engine NEVER triggers UI changes by itself — every
/// returned [MorphSuggestion] carries an [_action] closure that only
/// runs after the user taps the action button in the card.
///
/// The set of checks below is what the SDK can do today with on-device
/// data alone. Skipped (planned, need extra infra):
///   • readingMode / contentDensity → require MorphingEngine
///   • resumePosition (the check) → requires per-route scroll storage; the
///     suggestion *type* exists so devs can build their own.
class SuggestionEngine {
  final BehaviorDB db;
  final SuggestionHistoryStore historyStore;
  final MorphNavigatorObserver navObserver;
  final ZoneReorder zoneReorder;
  final DarkModeRequestCallback? onDarkModeRequested;

  /// Optional commercial-feature engines. Each is consulted only when
  /// non-null — the engine treats them as additional checks but works
  /// fine without them (the base 3 checks remain wired).
  final InterruptionRecovery? recovery;
  final BatteryAdapter? batteryAdapter;

  /// Threshold below which we don't bother checking. Mirrors the analytics
  /// reporter's "20+ interactions" floor — too little data, too much noise.
  static const int minInteractions = 20;

  SuggestionEngine({
    required this.db,
    required this.historyStore,
    required this.navObserver,
    required this.zoneReorder,
    this.onDarkModeRequested,
    this.recovery,
    this.batteryAdapter,
  });

  /// Returns the highest-confidence eligible suggestion, or null when
  /// nothing qualifies right now. Called by the overlay on a timer.
  ///
  /// Order of operations:
  ///   1. Pending interruption recovery (skips the [minInteractions]
  ///      gate — a fresh install can be interrupted on screen 1).
  ///   2. The standard checks, sorted by confidence.
  Future<MorphSuggestion?> getNextSuggestion(BuildContext context) async {
    final pendingRecovery = recovery?.consumeSuggestion();
    if (pendingRecovery != null) return pendingRecovery;

    final total = await db.getTotalInteractions();
    if (total < minInteractions) return null;

    final candidates = <MorphSuggestion>[];
    // Each check is independent and isolated — a single failure can't
    // poison the whole tick.
    for (final check in <Future<MorphSuggestion?> Function(BuildContext)>[
      _checkNavigationShortcut,
      _checkZonePromotion,
      _checkDarkModeAuto,
      _checkBatteryMode,
    ]) {
      try {
        final s = await check(context);
        if (s != null) candidates.add(s);
      } catch (e) {
        debugPrint('🦎 Morph suggestion check failed: $e');
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.first;
  }

  // ─── Check: battery saver ────────────────────────────────────────────────

  Future<MorphSuggestion?> _checkBatteryMode(BuildContext context) async {
    final batt = batteryAdapter;
    if (batt == null) return null;
    final mode = batt.currentMode;
    if (mode != BatteryMode.low && mode != BatteryMode.critical) return null;

    const id = 'battery_saver_mode';
    if (!await historyStore.canShow(id)) return null;

    return MorphSuggestion(
      id: id,
      type: SuggestionType.contentDensity,
      title: 'Battery saver mode',
      description:
          'Your battery is low. Switch to essential view to save power.',
      actionLabel: 'Enable',
      confidence: 0.95,
      metadata: {
        'batteryLevel': batt.currentLevel,
        'mode': mode.name,
      },
      action: () async {
        // BatteryAwareTheme already applies the theme — we just record the
        // user's preference so future sessions can lean into it.
        await db.saveBatteryPreference('saver_mode_accepted');
      },
    );
  }

  // ─── Check: navigation shortcut ──────────────────────────────────────────

  Future<MorphSuggestion?> _checkNavigationShortcut(
    BuildContext context,
  ) async {
    final currentPage = navObserver.currentRoute;
    if (currentPage == null) return null;

    final sequences = await db.getSequences();
    final pageStats = await db.getAllPageStats();

    // Best outgoing sequence from the current page (count >= 5).
    Map<String, dynamic>? best;
    for (final s in sequences) {
      final from = s['from'] as String?;
      final count = (s['count'] as int?) ?? 0;
      if (from != currentPage || count < 5) continue;
      if (best == null || count > (best['count'] as int)) best = s;
    }
    if (best == null) return null;

    final toPage = best['to'] as String?;
    if (toPage == null) return null;
    final fromVisits = (pageStats[currentPage]?['visitCount'] as int?) ?? 1;
    final confidence = (best['count'] as int) / (fromVisits == 0 ? 1 : fromVisits);
    if (confidence < 0.70) return null;

    final id = 'nav_shortcut_${currentPage}_$toPage';
    if (!await historyStore.canShow(id)) return null;

    final pageName = _formatRoute(toPage);
    return MorphSuggestion(
      id: id,
      type: SuggestionType.navigationShortcut,
      title: 'Quick access',
      description:
          'You usually visit $pageName after this screen. Want a shortcut?',
      actionLabel: 'Go to $pageName',
      confidence: confidence.clamp(0.0, 1.0),
      metadata: {
        'targetPage': toPage,
        'occurrences': best['count'],
      },
      action: () async {
        if (!context.mounted) return;
        // Use the imperative Navigator API so the suggestion works with
        // both vanilla MaterialApp and routers that bridge it (GoRouter
        // inserts a Navigator under the hood and respects pushNamed).
        Navigator.of(context).pushNamed(toPage);
      },
    );
  }

  // ─── Check: zone promotion ───────────────────────────────────────────────

  Future<MorphSuggestion?> _checkZonePromotion(BuildContext context) async {
    final allStats = await db.getAllZoneStats();
    if (allStats.length < 2) return null;

    // Pick the zone with the highest click count (≥ 20 clicks to qualify).
    String? topZone;
    int topClicks = -1;
    int totalClicks = 0;
    for (final entry in allStats.entries) {
      final clicks = (entry.value['totalClicks'] as int?) ?? 0;
      totalClicks += clicks;
      if (clicks >= 20 && clicks > topClicks) {
        topClicks = clicks;
        topZone = entry.key;
      }
    }
    if (topZone == null) return null;

    final id = 'zone_promote_$topZone';
    if (!await historyStore.canShow(id)) return null;

    final share = totalClicks == 0 ? 0.0 : topClicks / totalClicks;
    final confidence = share.clamp(0.0, 1.0);
    if (confidence < 0.40) return null;

    final zoneName = _formatRoute(topZone);
    return MorphSuggestion(
      id: id,
      type: SuggestionType.zonePromotion,
      title: 'Your favorite section',
      description:
          '$zoneName is what you use most. Move it to the top of the page?',
      actionLabel: 'Move to top',
      confidence: confidence,
      metadata: {
        'zoneId': topZone,
        'clicks': topClicks,
      },
      action: () async {
        final confirmed = await _confirmAction(
          context,
          title: 'Move $zoneName to top?',
          description: 'The page layout will be reorganized for you.',
        );
        if (!confirmed) return;
        zoneReorder.apply({topZone!: 1});
        if (!context.mounted) return;
        _showUndoNotice(
          context,
          message: '$zoneName moved to top',
          onUndo: zoneReorder.reset,
        );
      },
    );
  }

  // ─── Check: dark mode auto ───────────────────────────────────────────────

  Future<MorphSuggestion?> _checkDarkModeAuto(BuildContext context) async {
    if (onDarkModeRequested == null) return null; // dev didn't wire a target
    if (!context.mounted) return null;

    final hour = DateTime.now().hour;
    final isDarkHour = hour >= 21 || hour <= 6;
    if (!isDarkHour) return null;

    final sessionsThisHour = await db.getSessionsByHour(hour);
    if (sessionsThisHour < 3) return null;

    // Already in dark mode? Don't suggest the obvious.
    if (MediaQuery.platformBrightnessOf(context) == Brightness.dark) {
      return null;
    }

    const id = 'dark_mode_auto';
    if (!await historyStore.canShow(id)) return null;

    return MorphSuggestion(
      id: id,
      type: SuggestionType.darkModeAuto,
      title: 'Night mode',
      description:
          'You often use the app at night. Enable dark mode for a more '
          'comfortable experience.',
      actionLabel: 'Enable dark mode',
      confidence: 0.85,
      metadata: {'hour': hour, 'sessionsThisHour': sessionsThisHour},
      action: () async {
        if (!context.mounted) return;
        onDarkModeRequested!(context);
      },
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Two-step confirmation for actions that visibly mutate the layout
  /// (zone reorder, etc.). Returns false on dialog dismiss / negative tap.
  Future<bool> _confirmAction(
    BuildContext context, {
    required String title,
    required String description,
  }) async {
    if (!context.mounted) return false;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            // ignore: deprecated_member_use
            color: cs.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              // ignore: deprecated_member_use
              foregroundColor: cs.onSurfaceVariant,
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Floating snackbar with an "Undo" affordance. The 6-second duration
  /// matches the rule from the spec — long enough to react, short enough
  /// not to obscure content.
  void _showUndoNotice(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
  }) {
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: cs.onSurface),
        ),
        backgroundColor: cs.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            // ignore: deprecated_member_use
            color: cs.outline.withOpacity(0.2),
          ),
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          textColor: cs.primary,
          onPressed: onUndo,
        ),
      ),
    );
  }

  /// Pretty-prints a route or zone id for display in suggestion copy:
  ///   • '/home/profile' → 'Home Profile'
  ///   • 'tab_search'    → 'Search'
  String _formatRoute(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[/_-]'), ' ')
        .replaceAll('tab', '')
        .replaceAll('nav', '')
        .trim();
    if (cleaned.isEmpty) return raw;
    return cleaned
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
