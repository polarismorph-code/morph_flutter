import 'package:flutter/widgets.dart';

import '../behavior/behavior_db.dart';

/// Drop-in [NavigatorObserver] that feeds Morph's behavior store with
/// every route transition. Plug it into any router that accepts a
/// [NavigatorObserver]:
///
/// ```dart
/// // GoRouter
/// GoRouter(
///   observers: [MorphNavigatorObserver.instance],
///   routes: [...],
/// )
///
/// // Vanilla MaterialApp
/// MaterialApp(
///   navigatorObservers: [MorphNavigatorObserver.instance],
///   routes: {...},
/// )
/// ```
///
/// The observer is a singleton — [MorphProvider] auto-attaches its
/// internal [BehaviorDB] at boot, so the dev never has to wire that part
/// manually. Routes without a `name` (or with an empty one) are ignored —
/// nothing useful to report on anonymous routes.
///
/// Each transition records:
///   • `trackSequence(from, to)` — the `from → to` pair for sequence mining
///   • `trackClick(to, 'navigation')` — counts the destination as a visit
///   • `trackTimeSpent(from, ms)` — accumulates dwell time on the previous
///     page when the user navigates away
///
/// The observer also keeps an in-memory [sessionHistory] (the route names
/// visited in order, this session) — read it from
/// [AnalyticsReporter._buildPayload] to compute average navigation depth.
class MorphNavigatorObserver extends NavigatorObserver {
  /// Process-wide singleton. [MorphProvider] calls [attach] on it
  /// during bootstrap and [detach] on dispose. Apps can pass this same
  /// instance to multiple routers (e.g. nested navigators) without issue.
  static final MorphNavigatorObserver instance =
      MorphNavigatorObserver();

  /// Public so tests can build their own instance with a stubbed [BehaviorDB].
  MorphNavigatorObserver();

  BehaviorDB? _db;

  /// Ordered list of route names visited this session — front of the list
  /// is the entry route, back is the current route. Reset on [detach] (i.e.
  /// app dispose). Read by [AnalyticsReporter] for navigation-depth metrics.
  final List<String> sessionHistory = <String>[];

  /// Name of the route the user is currently on, or null when the
  /// observer has never seen a transition (boot before first push). Same
  /// as `sessionHistory.last` when populated; provided as a getter so
  /// callers can read it without bothering with bounds checks.
  String? get currentRoute =>
      sessionHistory.isEmpty ? null : sessionHistory.last;

  /// Cap on [sessionHistory] — past this we drop the oldest entry. Stops
  /// long-running sessions from growing unbounded in memory.
  static const int _historyMax = 200;

  // Tracks (currentRouteName, enteredAtMs) so we can record dwell time on
  // the previous page when the user navigates away.
  String? _currentRoute;
  int? _currentRouteEnteredAtMs;

  /// Wired by [MorphProvider] once the local store is initialized.
  /// Safe to call multiple times — subsequent attaches replace the ref
  /// (handy for hot reload scenarios).
  void attach(BehaviorDB db) {
    _db = db;
  }

  /// Called by [MorphProvider] on dispose so the observer doesn't keep
  /// a dangling reference to a closed Hive store.
  void detach() {
    _db = null;
    sessionHistory.clear();
    _currentRoute = null;
    _currentRouteEnteredAtMs = null;
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _track(previousRoute, route);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    // A pop returns the user to [previousRoute] — that's the new
    // destination from a behavior standpoint.
    _track(route, previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(oldRoute, newRoute);
  }

  void _track(Route? fromRoute, Route? toRoute) {
    final db = _db;
    final fromName = _name(fromRoute);
    final toName = _name(toRoute);
    if (toName == null) return; // anonymous destination → ignore

    // Close out the previous page's dwell time before swapping current.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (db != null && _currentRoute != null && _currentRouteEnteredAtMs != null) {
      final dwellMs = now - _currentRouteEnteredAtMs!;
      if (dwellMs >= 500) {
        db.trackTimeSpent(_currentRoute!, dwellMs);
      }
    }
    _currentRoute = toName;
    _currentRouteEnteredAtMs = now;

    // History — append; trim FIFO to respect [_historyMax].
    sessionHistory.add(toName);
    if (sessionHistory.length > _historyMax) {
      sessionHistory.removeAt(0);
    }

    if (db == null) return; // observer plugged but provider not booted yet

    if (fromName != null && fromName != toName) {
      db.trackSequence(fromName, toName);
    }
    // Even on the very first push (no previous route), count the visit so
    // the scorer learns the entry point's weight.
    db.trackClick(toName, 'navigation');

    assert(() {
      debugPrint(
        '🦎 Morph nav: '
        '${fromName ?? '∅'} → $toName',
      );
      return true;
    }());
  }

  String? _name(Route? route) {
    final n = route?.settings.name;
    if (n == null || n.isEmpty) return null;
    return n;
  }
}
