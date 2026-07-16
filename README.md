# Padel Score

Apple Watch–first padel scoring app with an iPhone companion for match history.

V1 is fully on-device. No backend, authentication, CloudKit, or statistics.

## Requirements

- macOS with **Xcode 15+** (Xcode 26 tested)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the project if needed
- For on-device installs: an **Apple Developer** account signed into Xcode, an iPhone, and a paired Apple Watch

## Open the project

```bash
cd /path/to/padel-app
xcodegen generate   # only needed if PadelScore.xcodeproj is missing or project.yml changed
open PadelScore.xcodeproj
```

In Xcode you should see schemes:

- **PadelScore** — iPhone app (embeds the Watch app)
- **PadelScoreWatch** — Watch app alone
- **PadelScoreTests** — hostless unit tests (preferred for CI / `⌘U` without Watch runtime)

## Build

### From Xcode

1. Select the **PadelScore** scheme (embeds the Watch app).
2. Choose an iPhone simulator or your device.
3. Product → Build (`⌘B`).

If Xcode asks to install a watchOS simulator runtime, accept the download (required once for the embedded Watch target).

### From the command line

```bash
# List simulator names/IDs for your Xcode version
xcrun simctl list devices available

# iPhone + embedded Watch (replace IDs/names as needed)
xcodebuild -scheme PadelScore \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

# Watch app alone
xcodebuild -scheme PadelScoreWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  build

# Device SDK compile check (no signing)
xcodebuild -target PadelScoreWatch -sdk watchos -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Run tests

Unit tests cover the scoring engine (including golden point and undo) and persistence/restore.

Prefer the **PadelScoreTests** scheme — it runs hostless and does not require the Watch app/runtime.

### From Xcode

1. Select the **PadelScoreTests** scheme.
2. Product → Test (`⌘U`).

### From the command line

```bash
xcodebuild -scheme PadelScoreTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## Run the iPhone app (Simulator)

1. Open `PadelScore.xcodeproj`.
2. Scheme: **PadelScore**.
3. Destination: an iPhone simulator.
4. Run (`⌘R`).

The phone app shows history and any active match synced from the Watch. It does **not** score matches in V1.

## Run the Watch app (Simulator)

1. Scheme: **PadelScoreWatch**, or run **PadelScore** with a paired Watch simulator.
2. Destination: an Apple Watch simulator.
3. Run (`⌘R`).

Typical flow: **Start Match** → swipe between Score / Overview / Actions → record points with **Serving** / **Receiving**. Tap the same button again within 5s to cancel.

To pair a Watch simulator with an iPhone simulator: in Xcode, Window → Devices and Simulators, or start both and use File → Open Simulator; create a Watch/Phone pair under the Watch simulator Hardware menu if needed.

## Install on your iPhone

1. Connect the iPhone with USB (or use wireless debugging once paired).
2. In Xcode → Settings → Accounts, sign in with your Apple ID.
3. Select the **PadelScore** target → Signing & Capabilities.
4. Choose your Team and ensure automatic signing is on. Change the bundle ID if Xcode complains about uniqueness (e.g. `com.yourname.padelscore`).
5. Select your physical iPhone as the run destination.
6. Run (`⌘R`). Trust the developer certificate on the phone if prompted (Settings → General → VPN & Device Management).

## Install on your paired Apple Watch

1. Pair and unlock the Watch with the Watch app on the iPhone (same Apple ID / developer team as above).
2. Prefer installing via the **PadelScore** iPhone scheme so the Watch app is embedded and installed automatically.
3. On the Watch, open **Padel Score** from the app list.
4. If it does not appear: on iPhone open Watch app → My Watch → scroll to **Padel Score** → enable **Show App on Apple Watch**, or run the **PadelScoreWatch** scheme with the physical Watch selected as destination.
5. Keep the Watch unlocked and nearby during the first install.

Scoring works offline on the Watch alone. When the phone is reachable, WatchConnectivity pushes the active match and history to the iPhone companion.

## CI

Separate GitHub Actions workflows (path-filtered so each platform only builds when relevant):

| Workflow | Path | What it checks |
|----------|------|----------------|
| [Apple](.github/workflows/apple.yml) | `watch/`, `iPhone/`, `shared/`, `tests/` | Unit tests, Watch + iPhone compile (unsigned) |
| [Garmin](.github/workflows/garmin.yml) | `garmin/` | Connect IQ compile for touchscreen devices + Monkey C tests |

Neither workflow requires secrets for compile checks. For a stable Garmin signing key in CI, set `GARMIN_DEVELOPER_KEY_BASE64` (see [`garmin/README.md`](garmin/README.md)).

## Project layout

```text
spec/           Product, architecture, implementation, infrastructure specs
shared/         Scoring engine, models, persistence, services, sync
watch/          Watch SwiftUI app
iPhone/         iPhone companion SwiftUI app
garmin/         Garmin Connect IQ watch app (Monkey C)
tests/Unit/     Scoring + persistence unit tests
docs/           Decision log
.github/        CI workflows (Apple + Garmin)
project.yml     XcodeGen manifest
PadelScore.xcodeproj
```

## V1 features

- Start / score / finish / end early / discard match on Watch
- Game, set, and match scoring with the house golden-point rule
- 5-second undo on the score screen; undo also on Actions
- Local persistence and restore after restart
- iPhone match history and detail (read-only)

See [docs/DECISIONS.md](docs/DECISIONS.md) for engineering choices and [spec/](spec/) for authoritative requirements.
