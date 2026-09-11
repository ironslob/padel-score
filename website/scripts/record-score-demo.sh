#!/usr/bin/env bash
# Record Wrist Rally on the Watch simulator and encode website/assets/score-demo.{mp4,gif,jpg}.
#
# simctl recordVideo keeps the undo-ring frames (up to ~15 fps). Static holds
# are VFR, so we convert to 20 fps CFR without mpdecimate — that would collapse
# the ring into a handful of stills. The UI test writes t0/t1 timestamps so we
# can trim away launch / Health prompts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UDID="${WATCH_UDID:-0576DFA2-8B2F-4517-81C0-C3BFB9F80508}"
RAW="${WR_DEMO_RAW:-/tmp/wristrally-score-demo-raw.mp4}"
ASSETS="$ROOT/website/assets"
REC_LOG="/tmp/wr-demo-rec.log"
REC_START="/tmp/wr-demo-rec-start"

cd "$ROOT"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryLevel 100 2>/dev/null || true

xcodegen generate
xcodebuild \
  -project "$ROOT/WristRally.xcodeproj" \
  -scheme WristRallyWatchUITests \
  -destination "platform=watchOS Simulator,id=$UDID" \
  -derivedDataPath /tmp/wristrally-dd \
  build-for-testing

# Drop leftover matches so the clip always opens at 0–0.
xcrun simctl uninstall "$UDID" com.codebrewery.wristrally.watchkitapp >/dev/null 2>&1 || true

rm -f "$RAW" "$REC_LOG" "$REC_START" /tmp/wr-demo-t0 /tmp/wr-demo-t1
xcrun simctl io "$UDID" recordVideo --codec=h264 --display=1 --mask=black --force "$RAW" >"$REC_LOG" 2>&1 &
REC_PID=$!
cleanup() { kill -INT "$REC_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 80); do
  if grep -q "Recording started" "$REC_LOG" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if ! grep -q "Recording started" "$REC_LOG" 2>/dev/null; then
  echo "simctl recordVideo did not start." >&2
  cat "$REC_LOG" >&2 || true
  exit 1
fi
python3 -c "import time; open('$REC_START','w').write(str(time.time()))"

xcodebuild \
  -project "$ROOT/WristRally.xcodeproj" \
  -scheme WristRallyWatchUITests \
  -destination "platform=watchOS Simulator,id=$UDID" \
  -derivedDataPath /tmp/wristrally-dd \
  -only-testing:WristRallyWatchUITests/MarketingDemoTests/testScoreDemo \
  test-without-building

kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
trap - EXIT

if [[ ! -f /tmp/wr-demo-t0 || ! -f /tmp/wr-demo-t1 || ! -f "$REC_START" ]]; then
  echo "Missing trim timestamps from the UI test." >&2
  exit 1
fi

read -r TRIM_START TRIM_DURATION < <(python3 - "$REC_START" <<'PY'
from pathlib import Path
import sys
rec = float(Path(sys.argv[1]).read_text())
t0 = float(Path("/tmp/wr-demo-t0").read_text())
t1 = float(Path("/tmp/wr-demo-t1").read_text())
ss = max(0.0, t0 - rec - 0.05)
dur = max(1.0, t1 - t0 + 0.1)
print(f"{ss:.3f} {dur:.3f}")
PY
)

ffmpeg -y -i "$RAW" -ss "$TRIM_START" -t "$TRIM_DURATION" -an \
  -vf "fps=20,scale=416:-1:flags=lanczos" \
  -r 20 -fps_mode cfr -c:v libx264 -pix_fmt yuv420p -movflags +faststart -crf 18 \
  "$ASSETS/score-demo.mp4"
ffmpeg -y -i "$ASSETS/score-demo.mp4" -frames:v 1 -update 1 -q:v 3 "$ASSETS/score-demo.jpg"
ffmpeg -y -i "$ASSETS/score-demo.mp4" \
  -vf "fps=20,scale=312:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128:stats_mode=full[p];[s1][p]paletteuse=dither=none" \
  "$ASSETS/score-demo.gif"

echo "Wrote $ASSETS/score-demo.mp4, score-demo.gif, score-demo.jpg (trim ${TRIM_START}s + ${TRIM_DURATION}s)"
