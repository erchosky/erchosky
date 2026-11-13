#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Freeze compiler inputs outside the live workspace. Some desktop file services
# round subsecond timestamps while reading files; Swift treats that as an edit.
BRISA_TEMP_BASE="${TMPDIR:-/tmp}"
BRISA_SNAPSHOT="$(mktemp -d "${BRISA_TEMP_BASE%/}/BrisaBuild.XXXXXX")"
printf '%s\n' 'Brisa disposable build snapshot v1' > "$BRISA_SNAPSHOT/.brisa-build"
trap 'python3 scripts/cleanup-build.py "$BRISA_SNAPSHOT"' ERR
ditto Sources "$BRISA_SNAPSHOT/Sources"
ditto Tests "$BRISA_SNAPSHOT/Tests"
ditto packaging "$BRISA_SNAPSHOT/packaging"
cp Package.swift "$BRISA_SNAPSHOT/Package.swift"
python3 - "$PWD" "$BRISA_SNAPSHOT" <<'PY'
from pathlib import Path
import hashlib, json, sys
source, snapshot = map(Path, sys.argv[1:])
def manifest(root):
    files = [root / 'Package.swift']
    for folder in ['Sources', 'Tests', 'packaging']:
        files.extend(p for p in (root / folder).rglob('*') if p.is_file() and p.name != '.DS_Store')
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
frozen = manifest(snapshot)
if frozen != manifest(source):
    raise SystemExit('Build inputs changed while copying; retry after the editor finishes saving.')
(snapshot / '.brisa-source-manifest.json').write_text(json.dumps(frozen, sort_keys=True, indent=2) + '\n')
PY
printf '%s\n' "$BRISA_SNAPSHOT"
