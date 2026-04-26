# 🦎 chameleon_flutter

Automatic UI adaptation for Flutter. Dark mode, accessibility, and behavioral
layout adaptation — zero configuration. The Flutter sibling of
[`@cabraule/chameleon-ui`](https://www.npmjs.com/package/@cabraule/chameleon-ui).

## What it does

- **System-aware theme** — reads `prefersDark`, `highContrast`, `textScaleFactor`,
  and the device locale, and keeps the app in sync when they change.
- **Behavioral reorder** — tracks which sections users actually tap / dwell on,
  and reorders your screens + bottom nav to match (one-line opt-in via
  `ChameleonReorderableColumn` / `ChameleonReorderableNav`).
- **Local-first** — behavior data lives in Hive on-device. Nothing is
  transmitted unless you explicitly use `ThemeAdapter.generateTheme()` to fetch
  an AI-generated palette from the backend.
- **Safe mode** — detect everything, mutate nothing. Perfect for tests and
  gradual rollouts.

## Install

```yaml
dependencies:
  chameleon_flutter: ^0.1.0
```

## Three lines

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChameleonProvider(
    licenseKey: 'cha-pro-xxx',
    child: MyApp(),
  ));
}
```

That's it. Read the state from any widget:

```dart
final dark = context.isChameleonDark;
final zoneOrder = context.zoneOrder;
final db = context.chameleonDB;
```

## Track sections

Wrap the parts of your UI that you want Chameleon to observe and potentially
reorder. Ids must be stable across rebuilds.

```dart
Scaffold(
  body: ChameleonReorderableColumn(
    zones: [
      ChameleonZone(id: 'search',   priority: 1, child: SearchSection()),
      ChameleonZone(id: 'feed',     priority: 2, child: FeedSection()),
      ChameleonZone(id: 'trending', priority: 3, child: TrendingSection()),
    ],
  ),
  bottomNavigationBar: ChameleonReorderableNav(
    items: [
      ChameleonNavItem(id: 'home',    icon: Icon(Icons.home),    label: 'Home',    priority: 1),
      ChameleonNavItem(id: 'search',  icon: Icon(Icons.search),  label: 'Search',  priority: 2),
      ChameleonNavItem(id: 'profile', icon: Icon(Icons.person),  label: 'Profile', priority: 3),
    ],
    currentIndex: _current,
    onTap: (i) => setState(() => _current = i),
  ),
);
```

`ChameleonReorderableNav` is transparent: you keep passing the ORIGINAL index
via `currentIndex` / `onTap`; the widget maps to the reordered set internally.

## Safe mode

When you want everything detected but nothing applied:

```dart
ChameleonProvider(
  licenseKey: '',
  safeMode: true,
  child: const MyApp(),
);
```

Reads `context.chameleon.theme`, `context.isHighContrast`, … still work. No
session is opened, no scorer runs, no reorder ever fires.

## Config

```dart
ChameleonProvider(
  licenseKey: 'cha-pro-xxx',
  config: const ChameleonConfig(
    analysisInterval: Duration(minutes: 5),
    minInteractions: 20,     // before reorder
    minZoomsForFontScale: 3, // before text-scale kicks in
    apiBaseUrl: 'https://api.chameleon-ui.dev',
  ),
  child: const MyApp(),
);
```

## What Chameleon sees

Each tap inside a `ChameleonZone` logs `{zoneId, type, timestamp}` — no
widget tree, no user data, no text content. Time-spent is measured via
`visibility_detector`. Everything is stored in Hive and auto-expires after 30
days.

See [`lib/src/behavior/behavior_db.dart`](lib/src/behavior/behavior_db.dart)
for the exact shape of what's persisted.

## Platform notes

- **iOS**: Hive on iOS requires no special setup.
- **Android**: make sure `WidgetsFlutterBinding.ensureInitialized()` is called
  in `main()` before `runApp(...)`.
- **High contrast**: both platforms surface the flag via
  `MediaQuery.highContrast` — Chameleon reads it automatically.
- **Text scale**: on iOS the system slider is reflected in
  `MediaQuery.textScaleFactor`; we treat any scale ≥ 1.2× as a zoom event.

## Testing

```bash
flutter test
```

The bundled tests cover: scorer math, BehaviorDB filtering + aggregation,
`ChameleonProvider` bootstrap in safe mode.

## License

MIT
