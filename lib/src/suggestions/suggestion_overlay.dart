import 'dart:async';

import 'package:flutter/material.dart';

import 'morph_suggestion.dart';
import 'suggestion_engine.dart';
import 'suggestion_history.dart';
import 'widgets/suggestion_card.dart';

/// Place this **inside** your `MaterialApp.builder` so the suggestion card
/// has access to MaterialApp's `MediaQuery`, `Directionality` and Material
/// theming. It listens for scrolls / text input / keyboard above its
/// subtree and only surfaces a card when the user is genuinely idle.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => MorphSuggestionOverlay(
///     child: child ?? const SizedBox.shrink(),
///   ),
///   // ...
/// );
/// ```
///
/// Suggestion cadence: a first check 30 s after mount, then every 3 min
/// while the overlay is alive. Only one card on screen at a time. The
/// engine + history come from the ambient [MorphInheritedWidget] so
/// the dev never wires those.
class MorphSuggestionOverlay extends StatefulWidget {
  final Widget child;

  /// Optional — pass these in for tests or to override the ones the
  /// provider attaches at boot. Production code leaves them null.
  final SuggestionEngine? engine;
  final SuggestionHistoryStore? historyStore;

  /// First check delay (default 30 s). Visible for tests.
  final Duration firstCheckDelay;

  /// Period between subsequent checks (default 3 min).
  final Duration checkInterval;

  const MorphSuggestionOverlay({
    required this.child,
    this.engine,
    this.historyStore,
    this.firstCheckDelay = const Duration(seconds: 30),
    this.checkInterval = const Duration(minutes: 3),
    super.key,
  });

  @override
  State<MorphSuggestionOverlay> createState() =>
      _MorphSuggestionOverlayState();
}

class _MorphSuggestionOverlayState
    extends State<MorphSuggestionOverlay> {
  MorphSuggestion? _current;
  bool _userIsScrolling = false;
  Timer? _checkTimer;
  Timer? _firstCheckTimer;
  Timer? _scrollIdleTimer;

  // Resolved at build-time from the inherited widget when not overridden.
  SuggestionEngine? _engine;
  SuggestionHistoryStore? _historyStore;

  @override
  void initState() {
    super.initState();
    _firstCheckTimer = Timer(widget.firstCheckDelay, _check);
    _checkTimer = Timer.periodic(widget.checkInterval, (_) => _check());
  }

  @override
  void dispose() {
    _firstCheckTimer?.cancel();
    _checkTimer?.cancel();
    _scrollIdleTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (!mounted) return;
    if (_userIsScrolling) return;
    if (_current != null) return;

    // If a TextField anywhere above us has focus, the user is typing and
    // we MUST stay out of the way. Spec rule #3.
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && focused.hasFocus && focused.context != null) {
      // Heuristic: any focus implies likely text entry. False positive on
      // focused buttons is acceptable — we'll re-check soon.
      return;
    }

    final engine = _engine ?? widget.engine;
    if (engine == null) return; // provider hasn't attached yet
    final next = await engine.getNextSuggestion(context);
    if (!mounted || next == null) return;
    setState(() => _current = next);
  }

  void _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _userIsScrolling = true;
      _scrollIdleTimer?.cancel();
    } else if (n is ScrollEndNotification) {
      _scrollIdleTimer?.cancel();
      // Wait 2 seconds after scroll end before considering the user idle
      // again (spec rule #2).
      _scrollIdleTimer = Timer(const Duration(seconds: 2), () {
        _userIsScrolling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-resolve from the inherited widget. Late-bound so the overlay
    // works whether the dev passes them explicitly or relies on the
    // provider's attachment.
    final inherited =
        context.dependOnInheritedWidgetOfExactType<_SuggestionScope>();
    _engine = widget.engine ?? inherited?.engine;
    _historyStore = widget.historyStore ?? inherited?.historyStore;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _onScrollNotification(n);
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          if (_current != null && _historyStore != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  MediaQuery.of(context).padding.bottom +
                  8,
              child: MorphSuggestionCard(
                key: ValueKey(_current!.id),
                suggestion: _current!,
                historyStore: _historyStore!,
                onDone: () {
                  if (mounted) setState(() => _current = null);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Internal inherited carrier so [MorphProvider] can publish the
/// engine and history store down the tree without forcing every dev to
/// pass them through their MaterialApp manually.
///
/// The provider wraps its child with this scope before the user's
/// MaterialApp; the overlay (placed inside MaterialApp.builder) reads
/// from it via [MorphSuggestionOverlay].
class MorphSuggestionScope extends StatelessWidget {
  final SuggestionEngine engine;
  final SuggestionHistoryStore historyStore;
  final Widget child;

  const MorphSuggestionScope({
    required this.engine,
    required this.historyStore,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return _SuggestionScope(
      engine: engine,
      historyStore: historyStore,
      child: child,
    );
  }
}

class _SuggestionScope extends InheritedWidget {
  final SuggestionEngine engine;
  final SuggestionHistoryStore historyStore;

  const _SuggestionScope({
    required this.engine,
    required this.historyStore,
    required super.child,
  });

  @override
  bool updateShouldNotify(_SuggestionScope old) =>
      engine != old.engine || historyStore != old.historyStore;
}
