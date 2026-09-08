# Wrist Rally — Wear OS

Standalone Wear OS scoring app, ported from the Apple Watch app.

Scoring behaviour matches `shared/Scoring/ScoringEngine.swift`. The Kotlin engine lives in `android/domain/` and is covered by JUnit ports of the Swift unit tests.

## Prerequisites

- JDK 17+ (21 tested)
- Android SDK with **Wear OS 4** / API 30+ and a Wear emulator image (Pixel Watch)
- Android Studio or command-line SDK tools

## Project layout

```
android/
├── domain/          Kotlin scoring engine, match service, JSON store
├── wear/            Wear OS Compose UI
├── gradle/wrapper/
└── README.md        This file
```

## Build & test

From `android/`:

```bash
./gradlew :domain:test          # scoring + persistence unit tests (no Android SDK)
./gradlew :wear:assembleDebug   # Wear APK (needs Android SDK)
```

Open the `android/` folder in Android Studio, select the **wear** run configuration, and choose a Wear OS emulator or a physical watch (Pixel Watch, Galaxy Watch on Wear OS 4+).

Typical flow: **Start Match** → warm-up (optional) → who’s serving → swipe Overview / Score / Actions → record points with **Us** / **Them**. Tap the same button again within 3s to cancel.

The app is **standalone**. Scoring never needs a phone.

## Scoring parity

When changing scoring rules, update:

1. `shared/Scoring/ScoringEngine.swift` and `tests/Unit/`
2. `garmin/source/ScoringEngine.mc`
3. `android/domain/.../ScoringEngine.kt` and `android/domain/src/test/`

## Not in this first ship

- Android phone companion (history / notes / Live Activities analog)
- Wear tiles / complications
- Data Layer sync to a phone

See `docs/DECISIONS.md`.
