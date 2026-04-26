import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Raw system-level accessibility + appearance state read from MediaQuery.
/// This is the snapshot the [ThemeAdapter] consumes to produce an adapted
/// ThemeData — see [MorphTheme] for the higher-level wrapper that also
/// carries the AI-generated palette and locale.
@immutable
class MorphSystemSettings {
  final Brightness brightness;
  final bool highContrast;
  final double textScaleFactor;
  final bool boldText;
  final bool disableAnimations;
  final bool invertColors;

  const MorphSystemSettings({
    this.brightness = Brightness.light,
    this.highContrast = false,
    this.textScaleFactor = 1.0,
    this.boldText = false,
    this.disableAnimations = false,
    this.invertColors = false,
  });

  @override
  String toString() =>
      'MorphSystemSettings('
      'brightness: $brightness, '
      'highContrast: $highContrast, '
      'textScaleFactor: $textScaleFactor, '
      'boldText: $boldText, '
      'disableAnimations: $disableAnimations, '
      'invertColors: $invertColors)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MorphSystemSettings &&
          brightness == other.brightness &&
          highContrast == other.highContrast &&
          textScaleFactor == other.textScaleFactor &&
          boldText == other.boldText &&
          disableAnimations == other.disableAnimations &&
          invertColors == other.invertColors;

  @override
  int get hashCode => Object.hash(
        brightness,
        highContrast,
        textScaleFactor,
        boldText,
        disableAnimations,
        invertColors,
      );
}
