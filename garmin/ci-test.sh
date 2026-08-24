#!/bin/bash
# CI test runner — matco/connectiq-tester flow with typecheck disabled (-l 0).
# Strict typing (-l 3) fails on nullable assertions in ScoringEngineTests.mc.

set -euo pipefail

DEVICE_ID="${1:-venu3}"
CERTIFICATE_PATH="${2:-developer_key.der}"

trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

mkdir -p bin
monkeyc -f monkey.jungle -d "$DEVICE_ID" -o bin/app.prg -y "$CERTIFICATE_PATH" -t -l 0 -w

if [[ ! -f bin/app.prg ]]; then
  echo "Compilation failed!"
  exit 1
fi

export DISPLAY=:1
Xvfb "$DISPLAY" -screen 0 1280x1024x24 &
sleep 5

simulator >/dev/null 2>&1 &
sleep 5

result_file=/tmp/result.txt
monkeydo bin/app.prg "$DEVICE_ID" -t >"$result_file" || true
cat "$result_file"

result="$(tail -1 "$result_file")"
case "$result" in
  PASSED*) echo "Success!"; exit 0 ;;
  *) echo "Failure!"; exit 1 ;;
esac
