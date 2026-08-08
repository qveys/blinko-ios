#!/usr/bin/env bash
# Shared configuration and helpers for Blinko iOS build/test scripts.
# Sourced by ci-build.sh and ci-test.sh; not meant to be run directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/BlinkoApp/BlinkoApp.xcodeproj"
SCHEME="${SCHEME:-BlinkoApp}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-${REPO_ROOT}/build/DerivedData}"
RESULTS_DIR="${RESULTS_DIR:-${REPO_ROOT}/build/ci}"

# Minimum iOS runtime the app supports (IPHONEOS_DEPLOYMENT_TARGET).
MIN_IOS_MAJOR=17

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
err() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; }

require_xcodebuild() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    err "xcodebuild not found. These scripts require macOS with Xcode installed."
    err "On CI, use a 'macos-*' runner. Locally, install Xcode from the App Store."
    exit 1
  fi
}

# Pick a booted-capable iOS simulator that actually exists on this machine.
#
# We deliberately do NOT hardcode a device name like "iPhone 15". GitHub bumps
# the Xcode/runtime set on macOS runner images regularly, and a hardcoded name
# turns a green pipeline red for reasons that have nothing to do with the code.
# Instead we query simctl and take the newest available iOS runtime, preferring
# an iPhone. Falls back to a generic destination so the failure mode is a clear
# xcodebuild error rather than a confusing "device not found".
resolve_destination() {
  if [[ -n "${DESTINATION:-}" ]]; then
    printf '%s' "${DESTINATION}"
    return 0
  fi

  local udid
  udid="$(
    xcrun simctl list devices available --json 2>/dev/null |
      python3 -c '
import json, re, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

best = None  # (ios_version_tuple, is_iphone, name, udid)
for runtime, devices in data.get("devices", {}).items():
    m = re.search(r"iOS[-.](\d+)[-.](\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    if version[0] < '"${MIN_IOS_MAJOR}"':
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        name = device.get("name", "")
        candidate = (version, name.startswith("iPhone"), name, device.get("udid", ""))
        if best is None or candidate[:2] > best[:2]:
            best = candidate

if best and best[3]:
    print(best[3])
'
  )" || true

  if [[ -n "${udid}" ]]; then
    printf 'platform=iOS Simulator,id=%s' "${udid}"
  else
    log "No concrete iOS ${MIN_IOS_MAJOR}+ simulator found; falling back to a generic destination." >&2
    printf 'generic/platform=iOS Simulator'
  fi
}

# Route xcodebuild output through xcpretty when available, but never let a
# missing formatter (or its exit status) mask a real build failure.
run_xcodebuild() {
  mkdir -p "${RESULTS_DIR}"
  local logfile="${RESULTS_DIR}/${1:?log name required}.log"
  shift

  set -o pipefail
  if command -v xcpretty >/dev/null 2>&1; then
    xcodebuild "$@" 2>&1 | tee "${logfile}" | xcpretty
  else
    xcodebuild "$@" 2>&1 | tee "${logfile}"
  fi
}
