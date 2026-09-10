# Wrist Rally — Wear OS + Android phone

Standalone Wear OS scoring app with an optional Android phone companion for history, notes, and deletion.

Scoring behaviour matches `shared/Scoring/ScoringEngine.swift`. The Kotlin engine lives in `android/domain/` and is covered by JUnit ports of the Swift unit tests.

## Prerequisites

- JDK 17+ (21 tested)
- Android SDK with **Wear OS 4** / API 30+ (Pixel Watch image) and a **phone** image (API 26+)
- Android Studio or command-line SDK tools
- Google Play services on both emulators/devices, signed in with the same Google account, to exercise Data Layer sync

## Project layout

```
android/
├── domain/          Kotlin scoring engine, match service, JSON store
├── sync/            Data Layer coordinator (used by Wear + phone)
├── wear/            Wear OS Compose UI
├── phone/           Android phone companion (history / notes)
├── gradle/wrapper/
└── README.md        This file
```

## Build & test

From `android/`:

```bash
./gradlew :domain:test          # scoring + persistence unit tests (no Android SDK)
./gradlew :sync:test            # Data Layer coordinator tests (fake transport)
./gradlew :wear:assembleDebug   # Wear APK (needs Android SDK)
./gradlew :phone:assembleDebug  # Phone APK (needs Android SDK)
```

Open the `android/` folder in Android Studio.

- **wear** run configuration → Wear OS emulator or Pixel Watch / Galaxy Watch on Wear OS 4+
- **phone** run configuration → phone emulator or device

Typical watch flow: **Start Match** → warm-up (optional) → who’s serving → swipe Overview / Score / Actions → record points with **Us** / **Them**. Tap the same button again within 3s to cancel.

Scoring never needs a phone. When the phone app is installed with the same application id (`com.codebrewery.wristrally`) and signing cert, the watch pushes the active match and archive over the Data Layer. Notes stay on the phone. Deleting a match on the phone tombstones it on the watch.

**Breaking install:** the Wear applicationId used to be `com.codebrewery.wristrally.wear`. Uninstall the old Wear APK before installing this build.

### Manual sync check

1. Pair a phone emulator and a Wear emulator (Play images, same Google account).
2. Install `:phone` on the phone and `:wear` on the watch.
3. Start and score a match on the watch — it should appear under Active Match, then History, on the phone.
4. Add a note on the phone; it must survive further scoring on the watch.
5. Delete the match on the phone; it must disappear from the watch archive after the next sync (or immediately if the watch is reachable).

## Scoring parity

When changing scoring rules, update:

1. `shared/Scoring/ScoringEngine.swift` and `tests/Unit/`
2. `garmin/source/ScoringEngine.mc`
3. `android/domain/.../ScoringEngine.kt` and `android/domain/src/test/`

## Not in this ship

- Wear tiles / complications
- On-phone scoring
- Cloud sync

See `docs/DECISIONS.md`.
