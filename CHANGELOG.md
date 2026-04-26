# Changelog

## 0.1.0

Initial public release.

### Added
- `MorphProvider` — root widget that bootstraps theme detection, behavior storage, and zone scoring.
- `MorphZone` / `ReorderableColumn` — wrappers that track interactions and reorder children based on usage.
- AI-adapted color schemes via the Morph SaaS (`/api/flutter/theme/generate`) — automatic dark/light/high-contrast palettes generated from the host app's base `ThemeData`.
- Behavior storage backed by Hive — visibility, taps, sequences, zoom events.
- `BuildContext` extensions: `context.morph`, `context.morphTheme`, `context.morphPalette`, `context.zoneOrder`.
- Origin-binding via `appId` payload — backend rejects calls from packages not declared in the license's `allowed_packages`.
- `MorphAnalyticsConfig` — opt-in behavior reporting with configurable upload interval and minimum-interaction floor.
- `MorphFeatures.fintech()` preset — interruption recovery, battery-aware UI, fatigue detection, GPS context (gated by license tier).
