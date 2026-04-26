import 'package:flutter_test/flutter_test.dart';
import 'package:morphui/morphui.dart';

void main() {
  group('DeviceCapabilities.isLikelyOLED', () {
    test('explicit true override always wins', () {
      // The whole point of the override: a dev who knows their target
      // device class should get exactly what they asked for.
      expect(DeviceCapabilities.isLikelyOLED(override: true), isTrue);
    });

    test('explicit false override always wins', () {
      // Useful for the iPhone SE line — physically LCD even though the
      // platform heuristic says "iPhone = OLED".
      expect(DeviceCapabilities.isLikelyOLED(override: false), isFalse);
    });

    test('null override falls through to platform heuristic', () {
      // The actual answer depends on the test runner platform, but the
      // contract is "deterministic per platform" — calling twice in a
      // row must give the same answer.
      final first = DeviceCapabilities.isLikelyOLED();
      final second = DeviceCapabilities.isLikelyOLED();
      expect(first, equals(second));
    });
  });
}
