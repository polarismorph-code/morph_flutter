# Changelog

## 0.1.2

### Plan gating — never leak Morph branding to end users *(behavioural change)*

- **`PlanGate` no longer auto-renders a Morph-branded upsell card** when the resolved plan is insufficient. The default fallback is now `SizedBox.shrink()` — gated features silently disappear instead. End users of integrating apps no longer see "Upgrade to Morph Pro" prompts when YOUR Morph subscription lapses; YOU receive renewal emails instead.
- Internal `_UpgradeCard` is now exposed as the public `MorphUpsellCard` widget. Pass it explicitly via `PlanGate.fallback` only on YOUR admin / dev surfaces — never on end-user screens.
- `context.requireMorphPro()` / `context.requireMorphAgency()` no longer auto-show a dialog. The new contract is `onAllowed` (sufficient plan) and `onDenied` (insufficient — wire to your own UI, or to `showDialog(builder: (_) => MorphUpgradeDialog(...))` on YOUR admin surface).
- The `onUpgrade` parameter on `requireMorphPro/Agency` is replaced by `onDenied`. Existing call sites still compile — `onUpgrade` was never required — but devs that relied on the auto-dialog need to pass `onDenied: () => showDialog(...)` explicitly.

### Interruption recovery — production-ready

- **Pause bucketing.** Pauses are now classified into `quick` (30s–2min), `real` (2min–10min) and `abandonment` (>10min) buckets via `InterruptionBucket`. The recovery card adapts its title, tone, and confidence per bucket — abandonment recoveries surface with more cautious copy.
- **Robust persistence.** The active context is now written to Hive on every `declareContext` call (debounced 1s) instead of only on `paused`. An app crash between context declaration and lifecycle pause no longer loses the snapshot.
- **Recovery strategies.** Each snapshot can declare a `RecoveryStrategy.auto` (silent restore, no card — for safe values), `RecoveryStrategy.confirm` (default, card before restore — for stakes-sensitive flows), or `RecoveryStrategy.silent` (analytics-only).
- **Multi-step workflow chains.** Snapshots can declare a `workflowId` + `workflowStep` + `workflowTotalSteps`. On resume the engine fetches the entire chain and exposes it via `InterruptionRecovery.pendingChain`, so a host app can restore "step 1 → step 4" of a KYC instead of just the last step.
- **Per-context TTL.** `RecoverySnapshot` now has a `ttl` field; expired snapshots are silently dropped on resume. Sensible defaults baked in via `kRecoveryDefaultTtl` — checkout 30 min, transfer 2 min, KYC 24 h, generic 1 h. Devs can override per call.
- **Local learning.** New `recordOutcome(bucket, RecoveryOutcome.accepted | rejected | ignored)` API tracks per-bucket acceptance. After 5 samples in a bucket, the engine suppresses suggestions there if the rejection rate exceeds 70% — the SDK respects users who consistently dismiss recoveries. Stays on-device, never transmitted.

### GPS context — production-ready

- Hysteresis on the speed→mode transitions. Walking→cycling kicks in at 7 km/h, but cycling→walking only at 5 km/h. A user steady at 7 km/h no longer flickers the UI between the two modes on every fix.
- New tunnel-mode behaviour. Updates with `accuracy > 50m` no longer immediately drop the user back to `unknown` — the adapter keeps emitting the last good context for 30 seconds. Going through a tunnel or under a bridge holds the previous mode instead of popping the UI back to a default.
- Accelerometer-aware fallback. `GpsContextAdapter.start()` now subscribes to the accelerometer and detects sustained train-like vibration. When GPS reports `stationary` but the accelerometer shows ≥5 seconds of high-variance motion, the emitted context is upgraded to `vehicle` — useful in metros and trains where GPS loses lock for minutes at a time.
- The accuracy-gate (drop fixes with >50m error) was already shipped in earlier versions but is now explicitly documented in the README.

### Fatigue detection — production-ready

- New continuous score stream — `FatigueDetector.scoreStream` emits a 0..100 value so UIs can interpolate smoothly instead of snapping between three buckets. The legacy bucketed `stream` is kept for backward compatibility.
- New `FatigueAdaptiveForm(adaptation: FatigueAdaptation.smooth)` (default) — field scale interpolates continuously from 1.00 to 1.30, banner fades in past score 40. Pass `FatigueAdaptation.stepped` to keep the old three-step behaviour.
- Per-user baseline. After 3 completed sessions the detector grades the user against their own typical accuracy + typing speed instead of universal thresholds. A 8% miss rate is "fatigued" for a 2%-baseline user, "normal" for an 8%-baseline user — universal thresholds got both wrong.
- Auto-reset after 5 minutes paused. The next resume rolls the buffers so a user who put the phone down and came back doesn't carry the previous session's fatigue.
- Cold-start guard. The first 30 seconds of the day's first session are excluded from scoring — stiff fingers in the morning aren't fatigue.
- Post-resume retry suppression. For 30 seconds after returning from background, error counters don't accumulate — coming back after a notification doesn't penalise the user.
- New typed error API: `recordTapError`, `recordTypingError`, `recordNavigationError`. Each carries its own weight in the score (5%, 5%, 15%). The legacy `recordRetry` is now `@Deprecated` but still works.
- `FatigueDetector.startSession()` and `resetFatigue()` are now `Future<void>` (they reload the persisted baseline). Existing `void`-returning call sites should wrap with `unawaited(...)` — handled internally for `MorphProvider` / `FatigueAdaptiveForm`.

### Battery — production-ready

- `BatteryAdapter` now records every foreground session (start/end level, duration, was-charging flag). Aggregated stats are exposed via `BatteryAdapter.getSessionStats(lookback: ...)` so devs can credibly answer "how much battery does my app burn per minute?".
- Charge-start events are timestamped per session and fed to a new `ChargePatternPredictor`. When the user is approaching their typical charge window (3+ events at the same hour over the last 7 days, day-of-week-weighted) and the device isn't already plugged in, the adapter pre-shifts to `BatteryMode.medium` to extend the runway.
- New `BatteryAwareTheme(adaptiveMode: BatteryAdaptiveMode.suggestion)` mode — instead of imposing the dimmed scaffold the moment battery drops, the theme stays untouched until the user accepts the "Battery saver mode" suggestion. The default remains `imposed` for backward compatibility.
- New `BatteryAwareTheme(isOLED: bool?)` override + automatic detection via `DeviceCapabilities.isLikelyOLED`. Pure-black scaffolds only apply when the screen is actually OLED — LCD devices fall back to dim grey, since pure black saves no power on LCD.
- Charging-aware behaviour (level rule short-circuits to `normal` when plugged in) is now explicitly documented in the README — was already shipped, just invisible.

### Grip detection — persistence + customisation

- `GripDetector` now reads the previously detected hand from `BehaviorDB` on `start()` and uses it as a prior. The UI lands on the right alignment immediately on the second session, and a matching live signal locks in after 5 samples instead of 10. A signal that contradicts the prior still goes through the full 10-sample window — switching hands mid-session works as before.
- `GripDetector` constructor now takes an optional `persistPreference` flag (default `true`). Set it to `false` for ephemeral detection without storage.
- `GripDetector.start()` is now `Future<void>` so it can `await` the prior read. Existing `unawaited(start())` callers keep working.
- `GripAdaptiveLayout` now exposes `transitionDuration` (default 300ms) and `transitionCurve` (default `easeOutCubic`) so devs can tune the feel of the side-switch animation.

### Tooling + dependencies

- Added a minimal `example/` so pana scores the package as having a runnable demo.
- Bumped `battery_plus` (4.x → 7.x), `sensors_plus` (4.x → 7.x), `package_info_plus` (>=4 <10 → ^10) to the latest majors.
- Fixed dartdoc HTML interpretation warning on `Map<zoneId, orderIndex>`.

## 0.1.1

- Renamed package from `morph_flutter` to `morphui` to align with `morphui.dev`.
- License switched to Apache 2.0.
- Internal API base URL is now resolved at compile time — clients no longer pass any URL; SDK maintainers can override via `--dart-define=CHAMELEON_API_BASE_URL=...`.

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
