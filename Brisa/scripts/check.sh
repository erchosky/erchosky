#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-results
set -o pipefail
BRISA_SNAPSHOT="$(bash scripts/prepare-build.sh)"
trap 'python3 scripts/cleanup-build.py "$BRISA_SNAPSHOT"' EXIT
swift test --package-path "$BRISA_SNAPSHOT" --build-system native -j 6 2>&1 | tee test-results/swift-test.log
swift build --package-path "$BRISA_SNAPSHOT" --build-system native -c release 2>&1 | tee test-results/release-build.log
BIN_DIR="$(swift build --package-path "$BRISA_SNAPSHOT" --build-system native -c release --show-bin-path)"
python3 scripts/smoke.py "$BIN_DIR"
