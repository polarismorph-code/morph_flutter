import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Best-effort hardware capability detection.
///
/// Flutter and the underlying OSes (iOS, Android) do not expose a
/// public API for "is this screen OLED?" — Apple has never published
/// it, and Android's signals are inconsistent across vendors. So we
/// take a pragmatic stance:
///
///   1. If the dev passes an explicit override (`isOLED: true/false`
///      on `BatteryAwareTheme`), trust them. They know their target
///      device better than any heuristic could.
///   2. Otherwise consult [_likelyOLEDByPlatform], a heuristic that
///      defaults to `true` on iOS (every iPhone since X is OLED, and
///      newer iPads are following) and `false` on Android (LCD is still
///      shipping in mid-range).
///   3. Web / desktop / tests: returns `false` — unknown surface, never
///      apply OLED-only optimisations.
///
/// The heuristic is deliberately conservative for Android: a false
/// positive (treating an LCD as OLED) wastes nothing — the dark scaffold
/// renders identically — but a false negative just skips an optimisation
/// the device could have benefited from. Given the user can override,
/// this trade-off is fine.
class DeviceCapabilities {
  /// Override-aware OLED check. Pass [override] from the dev's widget
  /// (typically `BatteryAwareTheme.isOLED`); the heuristic only runs
  /// when [override] is null.
  static bool isLikelyOLED({bool? override}) {
    if (override != null) return override;
    return _likelyOLEDByPlatform();
  }

  static bool _likelyOLEDByPlatform() {
    if (kIsWeb) return false;
    try {
      // iOS: iPhone X (2017) onwards is OLED. The iPhone SE line is the
      // only modern LCD device, and it's a small share of installs in
      // 2025+. We bias toward true and let devs override for the SE.
      if (Platform.isIOS) return true;
      // Android: LCD remains common (Pixel A-series, mid-range Samsung).
      // Returning false is the safe default — devs targeting flagship-
      // only audiences should pass `isOLED: true` on the widget.
      if (Platform.isAndroid) return false;
    } catch (_) {
      // Platform.isX throws on unsupported platforms (web, some
      // embedded targets) — be defensive.
    }
    return false;
  }
}
