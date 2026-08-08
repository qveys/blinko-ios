#!/usr/bin/env bash
# Build the Blinko iOS app for the simulator.
# Used by CI and reproducible locally: ./scripts/ci-build.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ci-common.sh"

require_xcodebuild

DEST="$(resolve_destination)"
log "Building scheme '${SCHEME}' (${CONFIGURATION})"
log "Destination: ${DEST}"

run_xcodebuild build \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "${DEST}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

log "Build succeeded."
