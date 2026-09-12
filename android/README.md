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
./gradlew :wear:test            # Wear UI/session tests (Robolectric, watch-sized)
./gradlew :wear:assembleDebug   # Wear APK (needs Android SDK)
```

Open the `android/` folder in Android Studio, select the **wear** run configuration, and choose a Wear OS emulator or a physical watch (Pixel Watch, Galaxy Watch on Wear OS 4+).

### Wear emulator (command line)

1. Install a Wear OS 4+ system image, for example `system-images;android-34;android-wear;x86_64`.
2. Create and start a round Wear AVD (KVM required on Linux):

```bash
avdmanager create avd -n wear_round -k "system-images;android-34;android-wear;x86_64" -d "wearos_small_round"
emulator -avd wear_round -gpu swiftshader_indirect -no-snapshot
```

3. Install and launch:

```bash
./gradlew :wear:installDebug
adb shell am start -n com.codebrewery.wristrally.wear/.MainActivity
```

Start Match asks for activity / body-sensor permission so Health Services can own a tennis exercise. Scoring still continues if the emulator (or watch) cannot start a workout. On a physical Galaxy Watch, use Wi-Fi ADB — the charger has no data pin. See the setup notes in the repo README for pairing.

### Galaxy Watch 4

Wear OS 4+ is required. Enable Developer options → ADB debugging → Debug over Wi-Fi, put the watch on the same LAN as the computer, then `adb connect WATCH_IP:5555`.

If Start Match still dies, pull the last Java crash (debug builds):

```bash
adb logcat -s WristRally:D AndroidRuntime:E DEBUG:I
adb exec-out run-as com.codebrewery.wristrally.wear cat files/last-crash.txt
```

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
