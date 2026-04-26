import 'package:flutter/material.dart';

import '../provider/morph_provider.dart';
import 'morph_zone.dart';

/// A `Column` of [MorphZone]s that rearranges itself based on the
/// scorer's latest decisions. Children keep their widget state across
/// reorders because each is built with a stable `Key(zoneId)`.
class MorphReorderableColumn extends StatelessWidget {
  final List<MorphZone> zones;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  /// Animate layout shifts when the order changes. When false, zones snap
  /// to their new positions — cheaper and avoids a brief layout dance.
  final bool animateLayoutChanges;

  const MorphReorderableColumn({
    required this.zones,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.min,
    this.animateLayoutChanges = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final w = MorphInheritedWidget.maybeOf(context);
    final orderMap = w?.state.zoneOrder ?? const {};

    final sorted = [...zones]..sort((a, b) {
        final oa = orderMap[a.id] ?? a.priority;
        final ob = orderMap[b.id] ?? b.priority;
        return oa.compareTo(ob);
      });

    final children = sorted
        .map<Widget>((z) => KeyedSubtree(key: ValueKey('cml-col-${z.id}'), child: z))
        .toList();

    final column = Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: children,
    );

    if (!animateLayoutChanges) return column;
    // Smooth size changes when elements jump between positions.
    return AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: column,
    );
  }
}

/// A single item fed to [MorphReorderableNav].
class MorphNavItem {
  final String id;
  final int priority;
  final Widget icon;
  final String label;

  const MorphNavItem({
    required this.id,
    required this.icon,
    required this.label,
    this.priority = 0,
  });
}

/// Bottom navigation that reorders its items based on the scorer. The app
/// keeps passing the ORIGINAL index via [currentIndex] / [onTap]; this
/// widget handles the mapping to the reordered set transparently, so the
/// rest of your routing logic doesn't need to know a reorder happened.
class MorphReorderableNav extends StatelessWidget {
  final List<MorphNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Extra `BottomNavigationBar` props passed through.
  final Color? backgroundColor;
  final BottomNavigationBarType? type;
  final Color? selectedItemColor;
  final Color? unselectedItemColor;

  const MorphReorderableNav({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.backgroundColor,
    this.type,
    this.selectedItemColor,
    this.unselectedItemColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    assert(items.length >= 2, 'BottomNavigationBar needs at least 2 items');
    assert(currentIndex >= 0 && currentIndex < items.length);

    final w = MorphInheritedWidget.maybeOf(context);
    final orderMap = w?.state.zoneOrder ?? const {};

    final sorted = [...items]..sort((a, b) {
        final oa = orderMap[a.id] ?? a.priority;
        final ob = orderMap[b.id] ?? b.priority;
        return oa.compareTo(ob);
      });

    final currentId = items[currentIndex].id;
    final newIndex = sorted.indexWhere((i) => i.id == currentId).clamp(0, sorted.length - 1);

    return BottomNavigationBar(
      currentIndex: newIndex,
      backgroundColor: backgroundColor,
      type: type,
      selectedItemColor: selectedItemColor,
      unselectedItemColor: unselectedItemColor,
      onTap: (i) {
        final tapped = sorted[i];
        final originalIndex = items.indexWhere((it) => it.id == tapped.id);
        if (originalIndex >= 0) onTap(originalIndex);
        // Track nav taps as clicks on the zone id.
        w?.db.trackClick(tapped.id, 'navigation');
      },
      items: [
        for (final it in sorted)
          BottomNavigationBarItem(icon: it.icon, label: it.label),
      ],
    );
  }
}
