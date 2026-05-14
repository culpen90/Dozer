#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/build/DerivedData}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$ROOT/Releases}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Dozer.app"
ZIP_PATH="$ARCHIVE_DIR/Dozer-arm64.zip"

cd "$ROOT"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild requires a full Xcode installation. Select it with xcode-select before building." >&2
  exit 69
fi

if [[ ! -d Dozer.xcodeproj ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Dozer.xcodeproj is missing and xcodegen is not installed." >&2
    exit 69
  fi
  xcodegen
fi

if [[ ! -d Carthage/Build/LaunchAtLogin.xcframework ]]; then
  if ! command -v carthage >/dev/null 2>&1; then
    echo "Carthage XCFrameworks are missing and carthage is not installed." >&2
    exit 69
  fi
  carthage bootstrap --cache-builds --platform macOS --use-xcframeworks
fi

xcodebuild \
  -project Dozer.xcodeproj \
  -scheme Dozer \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  build

test -x "$APP_PATH/Contents/MacOS/Dozer"
if ! lipo -verify_arch arm64 "$APP_PATH/Contents/MacOS/Dozer"; then
  echo "Built app is not arm64: $APP_PATH" >&2
  exit 70
fi

mkdir -p "$ARCHIVE_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --noextattr --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Built: $APP_PATH"
echo "Archive: $ZIP_PATH"
