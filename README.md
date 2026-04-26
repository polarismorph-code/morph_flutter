<div align="center">

<img src="https://morphui.dev/icon.png" alt="Morph" width="64" height="64" />

# morph — Flutter SDK

**Intelligent UI SDK for Flutter**

Your app has one interface. Your users are not one person.

[![pub.dev](https://img.shields.io/pub/v/morphui?color=4F46E5&label=pub.dev)](https://pub.dev/packages/morphui)
[![license](https://img.shields.io/badge/license-Apache%202.0-06B6D4)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.10%2B-4F46E5)](https://flutter.dev/)
[![iOS](https://img.shields.io/badge/iOS-12%2B-7C3AED)](https://developer.apple.com/)
[![Android](https://img.shields.io/badge/Android-6%2B-06B6D4)](https://developer.android.com/)

[Website](https://morphui.dev) · [Documentation](https://www.morphui.dev/docs/flutter) · [Dashboard](https://app.morphui.dev/dashboard) · [Pricing](https://morphui.dev/#pricing)

</div>

---

## What is Morph?

Morph is an intelligent UI SDK that makes your Flutter app **personal for every user — automatically.**

No darkTheme to write. No AppColors to duplicate. No accessibility backlog.
One widget. That's it.

```dart
MorphProvider(
  licenseKey: 'morph-free-demo',
  child: MyApp(),
)
```

Works without a license key — native detection is always free.
Add a key for AI-powered adaptation. [Get your key →](https://app.morphui.dev/dashboard)

> **Also available for React.** [See React SDK →](https://github.com/morphuiapp/morphui)

---

## Three layers of intelligence

### V1 — Context Intelligence

Morph reads the room the moment your app loads.

- 🌙 Dark at night. Light in the morning.
- ♿ High contrast when the system asks.
- 🎨 Color-blind safe palette when needed.
- ⚡ Reduced motion. Bold text. Language. All detected.

Reads directly from the device OS — `platformBrightness`, `highContrast`, `textScaleFactor`, `boldText`, `disableAnimations`. No config needed.

**System preference always wins.** Time-based logic is a smart fallback — never an override.

### V1 — Design Intelligence

IA reads your actual design — not just your colors.

Not a color inverter. Morph reads your `ThemeData` or your `AppColors` file — whatever you already have — and generates the opposite theme from your exact palette.

The result: a complete `ColorScheme` with 4 surface depth levels, WCAG AA verified on every element. It looks hand-crafted. Because the reasoning behind it was.

### V2 — Behavioral Intelligence *(Pro)*

Your interface learns this person.

Morph observes taps, navigation patterns, session context, zoom events. All local. All private. All in Hive. Nothing leaves the device.

- After 20 interactions → zones this person always uses rise
- After 3 sessions → layout density adapts
- After 5 sessions → the interface morphs around this user's behavior

Always with their permission. Always reversible. Always with an Undo button.

---

## Install

```yaml
# pubspec.yaml
dependencies:
  morphui: ^0.1.0
```

```bash
flutter pub add morphui
```

---

## Quick start

```dart
void main() {
  runApp(
    MorphProvider(
      licenseKey: 'morph-free-demo',
      child: MyApp(),
    ),
  );
}
```

---

## Pass your existing colors

Morph works with whatever color structure you already have.
No restructuring. No renaming. No extra files.

### With AppColors file

```dart
MorphProvider(
  licenseKey: 'morph-free-demo',
  colors: MorphColors(
    background:    AppColors.background,
    surface:       AppColors.surface,
    primary:       AppColors.primary,
    text:          AppColors.text,
    textSecondary: AppColors.textSecondary,
    border:        AppColors.border,
    error:         AppColors.error,
    success:       AppColors.success,
    warning:       AppColors.warning,
  ),
  child: MyApp(),
)
```

### With ThemeData

```dart
MorphProvider(
  licenseKey: 'morph-free-demo',
  baseTheme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F46E5),
    ),
  ),
  child: MyApp(),
)
```

### With both — CAS 3 (mixed)

```dart
MorphProvider(
  licenseKey: 'morph-free-demo',
  baseTheme: AppTheme.lightTheme,
  colors: MorphColors(
    success: AppColors.success,
    warning: AppColors.warning,
  ),
  child: MyApp(),
)
```

---

## How adaptation works

| App theme | Time of day | System preference | Action |
|-----------|-------------|-------------------|--------|
| Light | Day | None | ✅ Stay light |
| Light | Night | None | 🌙 Generate dark |
| Dark | Day | None | ☀️ Generate light |
| Dark | Night | None | ✅ Stay dark |
| Any | Any | Dark (system) | 🌙 Always dark |
| Any | Any | Light (system) | ☀️ Always light |

Morph detects your app brightness automatically from your colors.
You never declare whether your app is light or dark — Morph figures it out.

---

## Read the state anywhere

```dart
// From any widget in the tree
final theme   = context.morphTheme    // ThemeMode
final plan    = context.morphPlan     // MorphPlan
final settings = context.morphSettings // MorphSystemSettings

// System settings
final brightness = settings.brightness     // Brightness
final highContrast = settings.highContrast // bool
final textScale = settings.textScaleFactor // double
final boldText = settings.boldText         // bool
final reducedMotion = settings.disableAnimations // bool
```

---

## You always stay in control

### `safeMode` — detect without touching anything

```dart
MorphProvider(
  safeMode: true,
  child: MyApp(),
)
```

Morph detects everything, applies nothing.
All values still readable via `context.morphSettings`.

---

## V2 — Behavioral Intelligence *(Pro)*

### MorphZone

```dart
ChameleonReorderableColumn(
  zones: [
    MorphZone(
      id: 'search',
      priority: 1,
      child: SearchSection(),
    ),
    MorphZone(
      id: 'feed',
      priority: 2,
      child: FeedSection(),
    ),
    MorphZone(
      id: 'trending',
      priority: 3,
      child: TrendingSection(),
    ),
  ],
)
```

After enough sessions, Morph reorders zones based on what this user actually uses.
Always with their permission. Always with an Undo button.

### Navigation tracking

```dart
MaterialApp(
  navigatorObservers: [
    context.morphNavObserver,
  ],
  home: const HomePage(),
)
```

Morph tracks navigation patterns cross-pages and suggests shortcuts automatically.

[Full V2 documentation →](https://www.morphui.dev/docs/flutter/v2)

---

## V2 — Mobile-specific features *(Pro)*

### Interruption Recovery

User gets a call mid-session. They come back. Morph remembers.

```dart
MorphProvider(
  licenseKey: 'morph-pro-xxx',
  features: MorphFeatures(
    interruptionRecovery: true,
  ),
  onResumePosition: (page, depth) {
    // Scroll to saved position
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent
        * depth / 100,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  },
  child: MyApp(),
)
```

Declare the context so Morph builds the right recovery message:

```dart
// In your page
context.morphSetContext(
  page: '/checkout',
  context: 'checkout',
  metadata: { 'total': cart.total },
)
```

### Grip Detection

Detects left or right hand from the accelerometer.
Primary actions reposition toward the thumb automatically.
No permission required.

```dart
MorphProvider(
  features: MorphFeatures(gripDetection: true),
  child: MyApp(),
)
```

```dart
// In your page — primary action follows the thumb
GripAdaptiveLayout(
  child: ProductContent(),
  primaryAction: AddToCartButton(),
)
```

### Battery-Aware UI

Low battery? Morph reduces animations, simplifies the interface,
and on OLED screens goes darker. Your app lasts longer. Your user stays.

**Charging-aware by default.** When the device is plugged in, Morph
keeps the UI in `normal` mode regardless of battery level — a phone
charging at 12% behaves like one at 95%. No surprise downgrades while
the user is at their desk.

```dart
MorphProvider(
  features: MorphFeatures(batteryAwareUI: true),
  child: MyApp(),
)
```

```dart
// Adapt your UI per battery level
BatteryAwareWidget(
  normal:   FullDashboard(),
  medium:   SimplifiedDashboard(),
  low:      EssentialDashboard(),
  critical: CriticalDashboard(),
)
```

### Circadian Rhythm UI

The interface evolves with the time of day — not just dark/light.

```dart
MorphProvider(
  features: MorphFeatures(circadianRhythm: true),
  child: MyApp(),
)
```

---

## V2 — Agency features

### Fatigue Detection

Tap accuracy drops. Typing slows. Morph detects fatigue and
simplifies the interface to what matters right now.

```dart
MorphProvider(
  features: MorphFeatures(
    fatigueCognitiveDetection: true,
  ),
  child: MyApp(),
)
```

```dart
// Form adapts automatically
FatigueAdaptiveForm(
  normalFields:      allFormFields,
  simplifiedFields:  essentialFieldsOnly,
  submitButton:      SubmitButton(),
)
```

### GPS Context UI

Walking → bigger text. In a vehicle → essential only.
Stationary → full interface. Uses your existing GPS feed.
Zero extra permissions.

**Robust to bad fixes.** Updates with `accuracy > 50m` are dropped —
indoor / urban-canyon noise won't flip the UI to "stationary" while the
user is actually mid-trip.

**Tunnel-tolerant.** When the signal degrades for up to 30 seconds the
adapter holds the last known context — going through a tunnel or under
a bridge no longer drops the user back to "unknown".

**Hysteresis on transitions.** Mode changes use asymmetric thresholds
(e.g. walking→cycling at 7 km/h but cycling→walking only at 5 km/h),
so a steady speed at the boundary doesn't oscillate the UI.

**Accelerometer-aware.** When GPS reports `stationary` but the
accelerometer shows sustained train-like vibration, the adapter
upgrades to `vehicle` — useful in metros and trains where the GPS
loses lock for minutes at a time.

```dart
MorphProvider(
  features: MorphFeatures(gpsContext: true),
  child: MyApp(),
)

// In your location service — pass speed to Morph
context.morphGpsAdapter.onLocationUpdate(
  speedKmh: position.speed * 3.6,
  accuracy: position.accuracy,
)
```

---

## Enable features by plan

```dart
MorphProvider(
  licenseKey: 'morph-pro-xxx',

  // React preset — ecommerce
  features: MorphFeatures.ecommerce(),

  // React preset — fintech / field apps
  features: MorphFeatures.fintech(),

  // Or configure manually
  features: MorphFeatures(
    interruptionRecovery:      true,  // Pro
    gripDetection:             true,  // Pro
    batteryAwareUI:            true,  // Pro
    circadianRhythm:           true,  // Pro
    fatigueCognitiveDetection: false, // Agency
    gpsContext:                false, // Agency
  ),

  child: MyApp(),
)
```

---

## Suggestions system

Morph observes behavior locally and surfaces suggestions to the user
at the right moment — never during a scroll, never during typing.

Each suggestion has two buttons:

```
[Not now]        [Action]
```

- **Not now** → never ask again for 7 days
- **Action** → execute immediately with an Undo notice
- Refused 3 times → never shown again

Suggestions are generated locally — no network call needed.

Examples:
- "You always go to Search after Home. Want a shortcut?"
- "You read content carefully. Enable reading mode?"
- "Your battery is low. Switch to essential view?"
- "You often use the app at night. Enable dark mode automatically?"

---

## Analytics — send anonymized data *(Agency, opt-in)*

All behavioral data stays on device by default.
Enable anonymous reporting only with explicit user consent.

```dart
MorphProvider(
  licenseKey: 'morph-agency-xxx',
  analytics: MorphAnalyticsConfig(
    enabled: true,
    userConsent: _userHasConsented,
    onConsentRequired: () => showConsentDialog(),
    retentionDays: 30, // max 30 — enforced
  ),
  child: MyApp(),
)
```

**What is sent — anonymized aggregates only:**
- Zone scores (0.0 to 1.0) — not individual clicks
- Confirmed navigation sequences
- Scroll behavior summary
- App hash (non-reversible)
- Month only — not exact date

**Never sent:** clicks, timestamps, user identity,
device fingerprint, app content, location data.

---

## Platform support

| Platform | Status |
|----------|--------|
| iOS 12+ | ✅ |
| Android 6+ | ✅ |
| ThemeData | ✅ |
| AppColors files | ✅ |
| Material 3 | ✅ |
| Cupertino style | ✅ |
| Provider | ✅ |
| Riverpod | ✅ |
| Bloc / Cubit | ✅ |
| GetX | ✅ |
| Flutter Web | 🔜 |

---

## Pricing

| | Free | Pro | Agency |
|---|---|---|---|
| **Price** | $0 | $19/mo | $49/mo |
| **API calls/day** | 50 | 2,000 | Unlimited |
| **License keys** | 1 | 5 | Unlimited |
| **Dark mode + Accessibility** | ✅ | ✅ | ✅ |
| **AI theme generation** | ✅ | ✅ | ✅ |
| **Interruption recovery (basic)** | ✅ | ✅ | ✅ |
| **Behavioral intelligence V2** | — | ✅ | ✅ |
| **Grip detection** | — | ✅ | ✅ |
| **Battery-aware UI** | — | ✅ | ✅ |
| **Circadian rhythm** | — | ✅ | ✅ |
| **Fatigue detection** | — | — | ✅ |
| **GPS context UI** | — | — | ✅ |
| **Analytics dashboard** | — | — | ✅ |
| **AI recommendations** | — | — | ✅ |

One license key works on both React and Flutter. No extra cost.

[Get your license key →](https://morphui.dev/#pricing)

---

## Troubleshooting

**Dark theme not matching brand**
Pass your `AppColors` via `MorphColors()`. Morph reads your exact palette
and generates the opposite theme from it — never a generic dark.

**Theme not updating when system changes**
Make sure your `MaterialApp` is inside `MorphProvider` — not the other way around.

**Grip detection not working**
Check that `sensors_plus` is in your `pubspec.yaml` and that
`MorphFeatures(gripDetection: true)` is set.

**Analytics not sending**
Both `enabled: true` AND `userConsent: true` are required.
One alone is not enough.

---

## Roadmap

### ✅ Live now
- Automatic dark / light theme from ThemeData or AppColors
- WCAG AA — guaranteed, not hoped for
- System preferences — all of them
- AI-powered theme generation
- iOS and Android

### ✅ V2 — Behavioral Intelligence
- Zone tracking and reordering
- Navigation pattern detection
- Interruption Recovery
- Grip Detection
- Battery-aware UI
- Circadian Rhythm UI
- Suggestions system with permission
- Fatigue Detection (Agency)
- GPS Context UI (Agency)
- Analytics dashboard (Agency)
- AI-powered recommendations (Agency, opt-in)

### 🔜 V3
- Flutter Web support
- Cross-platform insights with React SDK

---

<div align="center">

[morphui.dev](https://morphui.dev) · [Docs](https://www.morphui.dev/docs/flutter) · [Dashboard](https://app.morphui.dev/dashboard) · [pub.dev](https://pub.dev/packages/morphui) · [React SDK](https://github.com/morphuiapp/morphui)

Every user deserves an interface made for them.

Apache License 2.0

</div>