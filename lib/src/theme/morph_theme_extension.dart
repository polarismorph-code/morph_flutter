import 'package:flutter/material.dart';

/// Carries "extra" semantic colors that Material's built-in ColorScheme
/// doesn't name — success, warning, text tiers, KYC-style tier accents.
///
/// The dev declares this as a [ThemeExtension] on their ThemeData; Morph
/// reads from it both to fill [MorphRawColors] slots and to round-trip
/// the generated palette back into the theme.
@immutable
class MorphThemeExtension
    extends ThemeExtension<MorphThemeExtension> {
  final Color? success;
  final Color? warning;
  final Color? textTertiary;
  final Color? textInverted;
  final Color? surfaceSecondary;
  final Color? bronze;
  final Color? silver;
  final Color? gold;

  const MorphThemeExtension({
    this.success,
    this.warning,
    this.textTertiary,
    this.textInverted,
    this.surfaceSecondary,
    this.bronze,
    this.silver,
    this.gold,
  });

  @override
  MorphThemeExtension copyWith({
    Color? success,
    Color? warning,
    Color? textTertiary,
    Color? textInverted,
    Color? surfaceSecondary,
    Color? bronze,
    Color? silver,
    Color? gold,
  }) {
    return MorphThemeExtension(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverted: textInverted ?? this.textInverted,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      bronze: bronze ?? this.bronze,
      silver: silver ?? this.silver,
      gold: gold ?? this.gold,
    );
  }

  @override
  MorphThemeExtension lerp(
    ThemeExtension<MorphThemeExtension>? other,
    double t,
  ) {
    if (other is! MorphThemeExtension) return this;
    return MorphThemeExtension(
      success: Color.lerp(success, other.success, t),
      warning: Color.lerp(warning, other.warning, t),
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t),
      textInverted: Color.lerp(textInverted, other.textInverted, t),
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t),
      bronze: Color.lerp(bronze, other.bronze, t),
      silver: Color.lerp(silver, other.silver, t),
      gold: Color.lerp(gold, other.gold, t),
    );
  }
}

/// `context.morphExt` — null when the dev hasn't attached the extension.
extension MorphThemeExtensionContext on BuildContext {
  MorphThemeExtension? get morphExt =>
      Theme.of(this).extension<MorphThemeExtension>();
}
