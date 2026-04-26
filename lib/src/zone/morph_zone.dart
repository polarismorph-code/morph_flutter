import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models/zone_model.dart';
import '../provider/morph_provider.dart';

/// Wraps a section of the UI so Morph can track clicks + time-spent
/// and reorder it based on learned behavior.
///
/// Optional — auto-detection covers semantic landmarks. But wrapping gives
/// the scorer an explicit id, priority and type — far better tie-breaking.
class MorphZone extends StatefulWidget {
  final String id;
  final int priority;
  final Widget child;
  final MorphZoneType type;

  /// Visibility threshold (0..1) before the zone counts as "seen".
  /// 0.5 by default — matches the web SDK's IntersectionObserver setup.
  final double visibilityThreshold;

  const MorphZone({
    required this.id,
    required this.child,
    this.priority = 0,
    this.type = MorphZoneType.section,
    this.visibilityThreshold = 0.5,
    super.key,
  });

  @override
  State<MorphZone> createState() => _MorphZoneState();
}

class _MorphZoneState extends State<MorphZone> {
  DateTime? _visibleSince;
  MorphInheritedWidget? _cached;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cached = MorphInheritedWidget.maybeOf(context);
    _cached?.registerZonePriority(widget.id, widget.priority);
  }

  @override
  void dispose() {
    // Flush any in-flight time measurement before we lose the element.
    _flushTime();
    _cached?.unregisterZonePriority(widget.id);
    super.dispose();
  }

  void _flushTime() {
    final since = _visibleSince;
    if (since == null || _cached == null) return;
    final elapsed = DateTime.now().difference(since).inMilliseconds;
    if (elapsed >= 500) {
      _cached!.db.trackTimeSpent(widget.id, elapsed);
    }
    _visibleSince = null;
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('cml-zone-${widget.id}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        if (info.visibleFraction >= widget.visibilityThreshold) {
          _visibleSince ??= DateTime.now();
        } else {
          _flushTime();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final w = MorphInheritedWidget.maybeOf(context);
          w?.db.trackClick(widget.id, widget.type.name);
        },
        child: widget.child,
      ),
    );
  }
}
