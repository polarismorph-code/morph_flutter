import 'package:flutter/material.dart';

import '../morph_suggestion.dart';
import '../suggestion_history.dart';

/// Themed card that surfaces a single [MorphSuggestion] at the bottom
/// of the app. EVERY color, radius and text style is derived from the
/// host's [Theme] / [ColorScheme] — Morph never injects its own
/// branding. The card looks like the dev's app.
///
/// Layout: icon + title with a confidence bar + close (X) button on the
/// right, description below, two buttons at the bottom (dismiss left,
/// action right). Slide-up + fade animation on mount.
class MorphSuggestionCard extends StatefulWidget {
  final MorphSuggestion suggestion;
  final SuggestionHistoryStore historyStore;

  /// Called when the card animates out (after accept/refuse/ignore) so the
  /// overlay can dismount it.
  final VoidCallback onDone;

  const MorphSuggestionCard({
    required this.suggestion,
    required this.historyStore,
    required this.onDone,
    super.key,
  });

  @override
  State<MorphSuggestionCard> createState() =>
      _MorphSuggestionCardState();
}

class _MorphSuggestionCardState extends State<MorphSuggestionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDone();
  }

  Future<void> _onAccepted() async {
    setState(() => _isLoading = true);
    await widget.historyStore
        .record(widget.suggestion.id, SuggestionResponse.accepted);
    await widget.suggestion.execute();
    if (!mounted) return;
    setState(() => _isLoading = false);
    await _dismiss();
  }

  Future<void> _onRefused() async {
    await widget.historyStore
        .record(widget.suggestion.id, SuggestionResponse.refused);
    await _dismiss();
  }

  Future<void> _onIgnored() async {
    await widget.historyStore
        .record(widget.suggestion.id, SuggestionResponse.ignored);
    await _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  // ignore: deprecated_member_use
                  color: cs.outline.withOpacity(0.25),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    // ignore: deprecated_member_use
                    color: cs.shadow.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    suggestion: widget.suggestion,
                    onClose: _onIgnored,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      widget.suggestion.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        // ignore: deprecated_member_use
                        color: cs.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: _isLoading ? null : _onRefused,
                            style: TextButton.styleFrom(
                              // ignore: deprecated_member_use
                              foregroundColor: cs.onSurfaceVariant,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: Text(
                              widget.suggestion.dismissLabel,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _onAccepted,
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onPrimary,
                                    ),
                                  )
                                : Text(
                                    widget.suggestion.actionLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final MorphSuggestion suggestion;
  final VoidCallback onClose;

  const _Header({required this.suggestion, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = (suggestion.confidence * 100).clamp(0, 100).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: cs.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                _icon(suggestion.type),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: suggestion.confidence,
                          // ignore: deprecated_member_use
                          backgroundColor: cs.surfaceVariant,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(cs.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$pct% match',
                      style: theme.textTheme.bodySmall?.copyWith(
                        // ignore: deprecated_member_use
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              // ignore: deprecated_member_use
              color: cs.onSurfaceVariant.withOpacity(0.6),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

String _icon(SuggestionType type) {
  switch (type) {
    case SuggestionType.navigationShortcut:
      return '🧭';
    case SuggestionType.navReorder:
      return '↕️';
    case SuggestionType.readingMode:
      return '📖';
    case SuggestionType.darkModeAuto:
      return '🌙';
    case SuggestionType.zonePromotion:
      return '⬆️';
    case SuggestionType.contentDensity:
      return '⚡';
    case SuggestionType.resumePosition:
      return '▶️';
  }
}
