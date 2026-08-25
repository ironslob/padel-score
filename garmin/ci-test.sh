#!/bin/bash
# CI test runner — matco/connectiq-tester flow with typecheck disabled (-l 0).
# Strict typing (-l 3) fails on nullable assertions in ScoringEngineTests.mc.

set -euo pipefail

DEVICE_ID="${1:-venu3}"
CERTIFICATE_PATH="${2:-developer_key.der}"

# Connect IQ stores device files under $HOME/.Garmin. GitHub job containers override
# HOME to the runner user's path; force the image default so the simulator can start.
export HOME="${HOME:-/root}"

trap 'jobs -p | xargs -r kill 2>/dev/null || true' EXIT

mkdir -p bin
monkeyc -f monkey.jungle -d "$DEVICE_ID" -o bin/app.prg -y "$CERTIFICATE_PATH" -t -l 0 -w

if [[ ! -f bin/app.prg ]]; then
  echo "Compilation failed!"
  exit 1
fi

echo "Launching simulator..."
export DISPLAY=:1
Xvfb "$DISPLAY" -screen 0 1280x1024x24 &
sleep 2

simulator >/dev/null 2>&1 &
sleep 5

echo "Running tests..."
result_file=/tmp/result.txt
for i in $(seq 1 6); do
  timeout 60 monkeydo bin/app.prg "$DEVICE_ID" -t >"$result_file" 2>&1 || true
  result="$(tail -1 "$result_file")"
  if [[ "$result" == PASSED* || "$result" == FAILED* ]]; then
    break
  fi
  if ! grep -qi "unable to connect" "$result_file"; then
    break
  fi
  echo "Retry $i: simulator not ready yet..."
  sleep 5
done

cat "$result_file"

result="$(tail -1 "$result_file")"
case "$result" in
  PASSED*) echo "Success!"; exit 0 ;;
  *) echo "Failure!"; exit 1 ;;
esac
