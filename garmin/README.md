# Wrist Rally — Garmin Connect IQ

Watch app port of Wrist Rally for Garmin Connect IQ (touchscreen and button-only watches).

## Prerequisites

1. [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/) — install SDK 4.1+ (9.x recommended)
2. [Monkey C extension](https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c) for VS Code / Cursor
3. A simulator profile (e.g. **Venu 3** or **Instinct 2**)

## Project layout

```
garmin/
├── manifest.xml          # App metadata + supported devices
├── monkey.jungle         # Build configuration
├── source/
│   ├── Models.mc         # Domain types (Side, MatchState, GameScore, …)
│   ├── ScoringEngine.mc  # Pure scoring state machine (ported from Swift)
│   ├── MatchService.mc   # Match lifecycle + persistence + FIT coordination
│   ├── FitActivityManager.mc  # ActivityRecording / FitContributor session
│   ├── MatchStore.mc     # Application.Storage persistence
│   ├── WristRallyApp.mc  # App entry point
│   └── *View.mc          # Watch UI screens
└── resources/
    ├── strings/
    ├── fitcontributions/
    └── drawables/
```

## Build & run

1. Open the `garmin/` folder in VS Code / Cursor
2. Run **Monkey C: Verify Installation** from the command palette
3. Select simulator device: **Monkey C: Set Products by Product Category** → pick Venu 3
4. **Monkey C: Run** (or **Build for Device** to produce a `.prg`)

### Command line (once SDK is on PATH)

```bash
cd garmin
# Generate a key once if you don't have one:
# openssl genrsa -out developer_key.pem 4096
# openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
monkeyc -f monkey.jungle -o bin/WristRally.prg -y /path/to/developer_key.der -d venu3
```

Install on a physical watch: copy `bin/WristRally.prg` to `GARMIN/Apps/` on the device via USB.

## CI

GitHub Actions workflow: [`.github/workflows/garmin.yml`](../.github/workflows/garmin.yml).

- Compiles for Venu 3 / 3S, Forerunner 965 / 265, vívoactive 5, Instinct 2, and Forerunner 255
- Runs Monkey C unit tests via `matco/connectiq-tester`
- Uses an ephemeral developer key unless `GARMIN_DEVELOPER_KEY_BASE64` is set in repo secrets

```bash
# Optional stable key for CI (base64 of developer_key.der):
base64 -i developer_key.der | pbcopy
```

## Features (V1)

- Start match, select server
- Large left/right score buttons with quick-undo (tap same side twice within 3s; yellow bar on the button)
- Button-only scoring: Up = Us, Down = Them; same button again within 3s undoes. Highlight + Select on every other screen
- Swipe pager: Overview → Score → Actions (Back / Menu on button-only watches)
- Star / silver / golden / regular deuce, tie-break, serve rotation at set boundaries (parity with Apple Watch)
- New serve and End match at changeover; deuce format can be changed mid-match
- Finish / end early / discard (with confirmation)
- Match history, match length, ask-serve, and Us/Them settings
- Local persistence via `Application.Storage`
- FIT activity recording for each match (tennis / padel sport type) with score written into the FIT via FitContributor

## Scoring parity

The Monkey C `ScoringEngine` is a direct port of `shared/Scoring/ScoringEngine.swift`. When changing scoring rules, update both implementations and run the Swift unit tests in `tests/Unit/ScoringEngineTests.swift`.

## FIT / activity recording

Start Match always tries to open an `ActivityRecording` session (`FitActivityManager.mc`). Warm-up is included. Completed and ended-early matches are saved; discarded matches discard the FIT. Score summary fields sync on each point.

**Permissions:** `Fit`, `FitContributor`, `PersistedContent` (no GPS / `Positioning`).

**Connect visibility:** Custom FitContributor fields show in Garmin Connect when the app is installed from the Connect IQ Store (including beta). Sideloaded builds still write the fields into the FIT file; verify with the activity list / FitCSVTool.

**App exit:** `onStop` saves an in-progress session so wrist-off cannot orphan a recording. Reopening an in-progress match starts a continuation session (may produce multiple Connect activities for one match).

## Supported devices

Primary (full touch): Venu 3/3S, Venu 2/2 Plus/2S, Venu Sq 2, Forerunner 965/265/165, vívoactive 5

Secondary (touch + buttons): Fenix 7 series, Epix 2 series

Button-only: Instinct 2 / 2S / 2X, Instinct Crossover, Instinct 3 Solar, Forerunner 255 / 255S / 255 Music

## Not yet ported

- Phone companion sync (WatchConnectivity → would need Connect IQ Mobile SDK)
- Complications / glance widget
- Live Activities

## App store submission

Generate a developer key via the SDK Manager, update `manifest.xml` with your own application UUID, and follow [Garmin's submission guide](https://developer.garmin.com/connect-iq/submit-an-app/).

### Simulator / device verification notes

1. Start match → warm-up → points → complete → confirm an activity appears in the device activity list.
2. Discard a match → no activity saved.
3. Force FIT start failure (another activity recording) → Confirmation Yes continues scoring without FIT; No cancels and discards.
4. Leave the app mid-match → activity saved on exit; reopen continues scoring with a new session.
5. Store/beta install required to see Match score / Sets fields in Garmin Connect UI.