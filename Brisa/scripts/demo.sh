#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "1. Controlled integration: all moved files stay inside a temporary fixture."
BRISA_DEMO_SNAPSHOT="$(bash scripts/prepare-build.sh)"
trap 'python3 scripts/cleanup-build.py "$BRISA_DEMO_SNAPSHOT"' EXIT
swift test --package-path "$BRISA_DEMO_SNAPSHOT" --build-system native --filter OperationTests
echo "2. Build and open the actual native app."
bash scripts/package.sh
open dist/Brisa.app
echo "3. Read real app status. No scan or cleanup is requested by this script."
./dist/brisa status --json
echo "Continue in the welcome screen, then choose Analyze to inspect your allowed roots."
echo "Select and review files only when you intend to request cleanup."
