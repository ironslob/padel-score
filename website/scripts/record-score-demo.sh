#!/usr/bin/env bash
# Record Wrist Rally on the Watch simulator and encode website/assets/score-demo.{mp4,gif,jpg}.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UDID="${WATCH_UDID:-0576DFA2-8B2F-4517-81C0-C3BFB9F80508}"
RAW="/tmp/wristrally-score-demo-raw.mp4"
ASSETS="$ROOT/website/assets"
# Seconds of XCTest launch / clock face to drop. Inspect the raw file if this drifts.
TRIM_START="${TRIM_START:-13.2}"

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

rm -f "$RAW"
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$RAW" &
REC_PID=$!
cleanup() { kill -INT "$REC_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

xcodebuild \
  -project "$ROOT/WristRally.xcodeproj" \
  -scheme WristRallyWatchUITests \
  -destination "platform=watchOS Simulator,id=$UDID" \
  -derivedDataPath /tmp/wristrally-dd \
  -only-testing:WristRallyWatchUITests/MarketingDemoTests/testScoreDemo \
  test-without-building

kill -INT "$REC_PID"
wait "$REC_PID" || true
trap - EXIT

ffmpeg -y -ss "$TRIM_START" -i "$RAW" -an -vf "setpts=PTS-STARTPTS" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart -crf 20 "$ASSETS/score-demo.mp4"
ffmpeg -y -i "$ASSETS/score-demo.mp4" -ss 00:00:04 -frames:v 1 -update 1 -q:v 3 "$ASSETS/score-demo.jpg"
ffmpeg -y -i "$ASSETS/score-demo.mp4" \
  -vf "fps=10,scale=312:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=96[p];[s1][p]paletteuse=dither=bayer" \
  "$ASSETS/score-demo.gif"

echo "Wrote $ASSETS/score-demo.mp4, score-demo.gif, score-demo.jpg"
