import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// Static entry points for Morph that don't need a [BuildContext].
///
/// For contextual access (theme, zones, behavior), use [MorphProvider]
/// and the `context.morph*` extensions.
class Morph {
  Morph._();

  /// The device's primary locale, as reported by the OS.
  ///
  /// Drop-in replacement for a hard-coded fallback with
  /// [easy_localization](https://pub.dev/packages/easy_localization):
  ///
  /// ```dart
  /// EasyLocalization(
  ///   supportedLocales: const [Locale('fr'), Locale('en')],
  ///   path: 'assets/translations',
  ///   fallbackLocale: Morph.systemLocale,
  ///   child: MyApp(),
  /// );
  /// ```
  ///
  /// If the OS locale's language isn't in your `supportedLocales`,
  /// easy_localization keeps running on this value (with a warning) — use
  /// [pickSupportedLocale] to clamp to your list.
  static Locale get systemLocale => PlatformDispatcher.instance.locale;

  /// Picks the best locale from [supported] for the current device.
  ///
  /// Walks the OS's preferred locales (ordered by user preference) and
  /// returns the first one whose `languageCode` matches an entry in
  /// [supported]. Falls back to [fallback], or `supported.first` if none
  /// is given.
  ///
  /// ```dart
  /// fallbackLocale: Morph.pickSupportedLocale(
  ///   const [Locale('fr'), Locale('en')],
  /// ),
  /// ```
  static Locale pickSupportedLocale(
    List<Locale> supported, {
    Locale? fallback,
  }) {
    assert(supported.isNotEmpty, 'supported must contain at least one locale');
    for (final device in PlatformDispatcher.instance.locales) {
      for (final s in supported) {
        if (s.languageCode == device.languageCode) return s;
      }
    }
    return fallback ?? supported.first;
  }
}
