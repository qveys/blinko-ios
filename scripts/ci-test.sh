#!/usr/bin/env bash
# Run the Blinko iOS unit tests on a simulator.
# Used by CI and reproducible locally: ./scripts/ci-test.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ci-common.sh"

require_xcodebuild

DEST="$(resolve_destination)"
RESULT_BUNDLE="${RESULTS_DIR}/TestResults.xcresult"

# xcodebuild refuses to write to an existing result bundle path.
rm -rf "${RESULT_BUNDLE}"
mkdir -p "${RESULTS_DIR}"

log "Testing scheme '${SCHEME}' (${CONFIGURATION})"
log "Destination: ${DEST}"

run_xcodebuild test test \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "${DEST}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -resultBundlePath "${RESULT_BUNDLE}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

log "Tests passed. Result bundle: ${RESULT_BUNDLE}"
