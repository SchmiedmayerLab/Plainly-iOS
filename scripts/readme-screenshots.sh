#!/bin/zsh
#
# This source file is part of the Plainly iOS open-source project
#
# SPDX-FileCopyrightText: 2026 Stanford University
#
# SPDX-License-Identifier: MIT
#
# Regenerates the README screenshots.
#
# Runs the README screenshot walk on an iPhone and shoots the simulator through RocketSim at every picture the
# walk takes, in light and dark appearance, into docs/screenshots/<Name>.png and <Name>~dark.png: device bezel,
# transparent background, full resolution. The chat pictures talk to the Firebase emulators, which the script
# starts around the walk with a fixed summary as the model's answer. The App Store pictures come from
# `fastlane screenshots`.
#
# Requirements: Xcode with an iOS simulator runtime, RocketSim (https://www.rocketsim.app) running with its
# command line tool installed, pngquant (`brew install pngquant`) to keep the pictures small, and Node for the
# Firebase emulators.
#
# Usage:
#   scripts/readme-screenshots.sh [--device "iPhone 17 Pro"]
set -euo pipefail
SCRIPT=${0:A}
ROOT=${SCRIPT:h:h}
ROCKETSIM=/Applications/RocketSim.app/Contents/Helpers/rocketsim
DEVICE_TYPE="iPhone 17 Pro"
SIMULATOR_NAME="README Screenshots"
DERIVED_DATA="$ROOT/.derivedData/readme-screenshots"
OUTPUT="$ROOT/docs/screenshots"

while (( $# > 0 )); do
  case $1 in
    --device) DEVICE_TYPE=$2; shift 2;;
    -h|--help) sed -n '9,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) print -u2 "unknown option: $1"; exit 1;;
  esac
done

log() { print -u2 -- "[$(date +%H:%M:%S)] $*"; }
fail() { log "error: $*"; exit 1; }

[[ -x $ROCKETSIM ]] || fail "RocketSim is not installed; its CLI is expected at $ROCKETSIM."
$ROCKETSIM status >/dev/null 2>&1 || fail "RocketSim.app is not running; open it before regenerating screenshots."
command -v pngquant >/dev/null || fail "pngquant is not installed (brew install pngquant)."

device_state() {
  xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for device in devices:
        if device['udid'] == '$1':
            print(device['state']); sys.exit()
"
}

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])[-1]["identifier"])')
UDID=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for device in devices:
        if device['name'] == '$SIMULATOR_NAME' and device['isAvailable']:
            print(device['udid']); sys.exit()
")
# Reused across runs: RocketSim only shoots simulators it knew when it launched, so a fresh device needs a
# RocketSim relaunch once, and never an erase, after which it answers with empty pictures.
if [[ -z $UDID ]]; then
  UDID=$(xcrun simctl create "$SIMULATOR_NAME" "$DEVICE_TYPE" "$RUNTIME")
  log "created $SIMULATOR_NAME; relaunching RocketSim so it knows the device"
  osascript -e 'quit app "RocketSim"' >/dev/null 2>&1 || true
  sleep 3
  open -a RocketSim
  until $ROCKETSIM status >/dev/null 2>&1; do sleep 1; done
fi

if [[ -z ${PLAINLY_README_SCREENSHOTS_EMULATED:-} ]]; then
log "building"
xcodebuild build-for-testing -project "$ROOT/Plainly.xcodeproj" -scheme Plainly \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation -skipMacroValidation -quiet || fail "build failed"
fi

shoot() {
  local file=$1 attempt capture=$(mktemp)
  for attempt in 1 2 3; do
    $ROCKETSIM screenshot --udid "$UDID" --bezel device --background transparent > "$capture" 2>/dev/null
    if [[ -s $capture ]]; then
      mv "$capture" "$file"
      pngquant --quality 85-100 --speed 1 --strip --force --output "$file" -- "$file"
      return 0
    fi
    sleep 2
  done
  rm -f "$capture"
  return 1
}

# Kills a walk whose log has not grown for five minutes; the test runner has stalled, and the run reports it.
watchdog() {
  local pid=$1 file=$2 size=-1 current
  while kill -0 "$pid" 2>/dev/null; do
    sleep 30
    current=$(stat -f %z "$file" 2>/dev/null || echo 0)
    if [[ $current -eq $size ]]; then
      log "no output for five minutes; stopping the stalled walk"
      pkill -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
      return
    fi
    size=$current
    sleep 270
  done
}

capture() {
  local appearance=$1 suffix=""
  [[ $appearance == dark ]] && suffix="~dark"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  until [[ $(device_state "$UDID") == Shutdown ]]; do sleep 1; done
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  # RocketSim shoots the window Simulator.app shows for the device.
  open -a Simulator --args -CurrentDeviceUDID "$UDID"
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ''
  log "capturing $appearance"
  local test_log=$(mktemp) test_status=$(mktemp)
  (TEST_RUNNER_PLAINLY_README_SCREENSHOTS=1 TEST_RUNNER_PLAINLY_MOCK_CHAT_RESPONSE="$PLAINLY_MOCK_CHAT_RESPONSE" \
    xcodebuild test-without-building -project "$ROOT/Plainly.xcodeproj" -scheme Plainly \
    -only-testing:PlainlyUITests/ReadmeScreenshotTests \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED_DATA" \
    -parallel-testing-enabled NO > "$test_log" 2>&1; echo $? > "$test_status") &
  local test_pid=$!
  watchdog "$test_pid" "$test_log" &
  local watchdog_pid=$!
  # The reader follows the log; once the walk has ended it gets a moment for the last lines and is released.
  tail -n +1 -f "$test_log" 2>/dev/null | while read -r line; do
    case "$line" in
      *"CAPTURE "*)
        name=${line##*CAPTURE }; name=${name%% *}
        sleep 1
        shoot "$OUTPUT/$name$suffix.png" && log "$name$suffix.png" || { log "RocketSim returned nothing for $name$suffix"; touch "$test_log.missed"; };;
      *" error: "*|*"Failing tests:"*|*"failed ("*) log "$line";;
    esac
  done &
  local reader_pid=$!
  wait "$test_pid" 2>/dev/null || true
  kill "$watchdog_pid" 2>/dev/null || true
  sleep 8
  pkill -f "tail -n \+1 -f $test_log" 2>/dev/null || true
  wait "$reader_pid" 2>/dev/null || true
  local status=$(cat "$test_status" 2>/dev/null || echo 1)
  [[ -e "$test_log.missed" ]] && status=1
  rm -f "$test_log" "$test_log.missed" "$test_status"
  xcrun simctl status_bar "$UDID" clear
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  # A walk that failed or a picture that was not taken leaves the set incomplete or stale; what was taken is kept,
  # the run is not called done.
  [[ $status -eq 0 ]] || fail "the $appearance walk is incomplete; see the lines above"
}

mkdir -p "$OUTPUT"
export PLAINLY_MOCK_CHAT_RESPONSE="Here is a summary of your recent health records. Your last visit noted seasonal allergies, and your lab results, including cholesterol and blood sugar, are within the normal range. You have two active prescriptions: a daily antihistamine and a vitamin D supplement. Would you like me to explain any of these in more detail?"
# The chat pictures need the Firebase emulators; the script hands itself to emulators:exec once, then captures.
if [[ -z ${PLAINLY_README_SCREENSHOTS_EMULATED:-} ]]; then
  firebase_root="$ROOT/Plainly-Firebase"
  [[ -e $firebase_root/.git ]] || git -C "$ROOT" submodule update --init Plainly-Firebase
  npm --prefix "$firebase_root/functions" ci >/dev/null
  npm --prefix "$firebase_root/functions" run build >/dev/null
  [[ -f $firebase_root/functions/.secret.local ]] || cp "$firebase_root/functions/.secret.local.example" "$firebase_root/functions/.secret.local"
  export FIREBASE_CLI_DISABLE_UPDATE_CHECK=true PLAINLY_README_SCREENSHOTS_EMULATED=1
  log "starting the Firebase emulators"
  cd "$firebase_root"
  # The pinned CLI through npx, as run-firebase-e2e.sh does; a Homebrew firebase on the PATH may die at launch.
  exec npx --yes firebase-tools@15.25.1 emulators:exec --project demo-plainly --only auth,functions,firestore,storage "$SCRIPT --device $(printf '%q' "$DEVICE_TYPE")"
fi
capture light
capture dark
log "done: $(ls "$OUTPUT" | wc -l | tr -d ' ') pictures in docs/screenshots"
