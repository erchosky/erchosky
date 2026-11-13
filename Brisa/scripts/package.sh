#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
BRISA_SNAPSHOT="$(bash scripts/prepare-build.sh)"
trap 'python3 scripts/cleanup-build.py "$BRISA_SNAPSHOT"' EXIT
swift build --package-path "$BRISA_SNAPSHOT" --build-system native -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$BRISA_SNAPSHOT" --build-system native -c "$CONFIGURATION" --show-bin-path)"
APP="$BRISA_SNAPSHOT/Brisa.app"
mkdir -p dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BrisaApp" "$APP/Contents/MacOS/Brisa"
cp "$BIN_DIR/brisa" dist/brisa
cp "$BIN_DIR/brisa-mcp" dist/brisa-mcp
if [[ -d "$BIN_DIR/Brisa_BrisaApp.bundle" ]]; then
  ditto --norsrc --noextattr "$BIN_DIR/Brisa_BrisaApp.bundle" "$APP/Contents/Resources/Brisa_BrisaApp.bundle"
fi
if [[ -d "$BIN_DIR/Brisa_BrisaCore.bundle" ]]; then
  ditto --norsrc --noextattr "$BIN_DIR/Brisa_BrisaCore.bundle" "$APP/Contents/Resources/Brisa_BrisaCore.bundle"
fi
if [[ -f "$BRISA_SNAPSHOT/Sources/BrisaCore/Resources/brisa-catalog.json" ]]; then
  cp "$BRISA_SNAPSHOT/Sources/BrisaCore/Resources/brisa-catalog.json" "$APP/Contents/Resources/brisa-catalog.json"
fi
cp "$BRISA_SNAPSHOT/packaging/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$BRISA_SNAPSHOT/packaging/Brisa.icns" ]]; then cp "$BRISA_SNAPSHOT/packaging/Brisa.icns" "$APP/Contents/Resources/Brisa.icns"; fi
# Ad-hoc signing is for local execution only. Supply your own identity for distribution.
IDENTITY="${BRISA_SIGN_IDENTITY:--}"
# Remove Finder/resource-fork metadata from our own generated artifact before signing.
xattr -cr "$APP"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$BRISA_SNAPSHOT/Brisa.zip"
cp -X "$BRISA_SNAPSHOT/Brisa.zip" dist/Brisa.zip
# FileProvider folders may reattach forbidden FinderInfo even after xattr removal.
# Keep the runnable bundle outside that folder; dist contains a convenience link
# and a self-contained clean ZIP for delivery.
BRISA_LOCAL_DIR="${BRISA_LOCAL_DIR:-$HOME/Library/Caches/dev.brisa.build}"
mkdir -p "$BRISA_LOCAL_DIR"
BRISA_LOCAL_STAGE="$BRISA_LOCAL_DIR/.Brisa-new-$$.app"
ditto --norsrc --noextattr "$APP" "$BRISA_LOCAL_STAGE"
codesign --verify --deep --strict "$BRISA_LOCAL_STAGE"
if [[ -e "$BRISA_LOCAL_DIR/Brisa.app" ]]; then mv "$BRISA_LOCAL_DIR/Brisa.app" "$BRISA_SNAPSHOT/previous-local.app"; fi
mv "$BRISA_LOCAL_STAGE" "$BRISA_LOCAL_DIR/Brisa.app"
if [[ -L dist/Brisa.app ]]; then unlink dist/Brisa.app
elif [[ -e dist/Brisa.app ]]; then mv dist/Brisa.app "$BRISA_SNAPSHOT/previous-workspace.app"; fi
ln -s "$BRISA_LOCAL_DIR/Brisa.app" dist/Brisa.app
codesign --verify --deep --strict "$BRISA_LOCAL_DIR/Brisa.app"
echo "Built: $BRISA_LOCAL_DIR/Brisa.app"
echo "Convenience link: $(pwd)/dist/Brisa.app"
echo "Clean signed archive: $(pwd)/dist/Brisa.zip"
echo "CLI: $(pwd)/dist/brisa"
if [[ "$IDENTITY" == "-" ]]; then echo "Local ad-hoc signature. Not notarized; not a distributable Developer ID release."; fi
