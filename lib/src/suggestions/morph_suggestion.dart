import 'package:flutter/foundation.dart';

/// All suggestion categories Morph can produce. The engine fills the
/// ones it has data for; new categories can be added without breaking
/// existing consumers (the card widget renders a fallback icon).
enum SuggestionType {
  /// "You usually go to /search after /home — want a shortcut?"
  navigationShortcut,

  /// "Move this nav tab to position 1?"
  navReorder,

  /// "You read carefully — enable reading mode?"  (requires MorphingEngine)
  readingMode,

  /// "You often use the app at night — enable dark mode?"
  darkModeAuto,

  /// "Your favorite section is X — move it to top?"
  zonePromotion,

  /// "You scan content quickly — switch to compact view?" (requires MorphingEngine)
  contentDensity,

  /// "You were at 67% last time — resume?" (requires scroll position storage)
  resumePosition,
}

/// What the user did with a suggestion. Persisted in [SuggestionHistoryStore]
/// to drive the cooldown rules.
enum SuggestionResponse {
  /// User tapped the action button → execute and never show again.
  accepted,

  /// User tapped "Not now" → cooldown 7 days. After 3 refusals, never again.
  refused,

  /// User dismissed via the close icon → cooldown 3 days.
  ignored,
}

/// A single, fully-formed suggestion ready to render in the
/// [MorphSuggestionCard]. Built by [SuggestionEngine] — devs don't
/// instantiate these directly.
///
/// The [_action] is opaque to the dev: it's a closure the engine assembles
/// (e.g. `Navigator.pushNamed`, `zoneReorder.apply`, dev-provided callback).
@immutable
class MorphSuggestion {
  /// Stable identifier, used as the key in [SuggestionHistoryStore]. Must
  /// be deterministic so the same scenario always produces the same id
  /// (otherwise the cooldown rules can't track it).
  final String id;

  final SuggestionType type;
  final String title;
  final String description;
  final String actionLabel;
  final String dismissLabel;

  /// 0..1 — confidence the engine has in this suggestion, used to pick the
  /// best candidate when several are eligible at the same tick.
  final double confidence;

  /// Free-form metadata captured when the suggestion was built (target
  /// page, zone id, etc.). Available to the action closure via the engine
  /// that built it.
  final Map<String, dynamic> metadata;

  /// What runs when the user taps the action button. Set by the engine.
  /// Wrapped by [execute] so the caller doesn't need to null-check.
  final Future<void> Function()? _action;

  const MorphSuggestion({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.dismissLabel = 'Not now',
    required this.confidence,
    this.metadata = const {},
    Future<void> Function()? action,
  }) : _action = action;

  /// Runs the engine-supplied action (no-op when no action was set, e.g.
  /// for tests).
  Future<void> execute() async {
    await _action?.call();
  }
}
