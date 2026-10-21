#!/bin/bash
# A disposable native window for testing the installed Dozer app without moving user windows.
# Usage: Scripts/RunWindowFixture.sh [--build-only | --large-minimum]
# Read build/window-fixture-frame.json for authoritative AppKit and Accessibility geometry.
# Close the fixture window or press Command-Q to quit; no permissions or network are used.
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != '--build-only' && "$1" != '--large-minimum' ) ]]; then
    echo 'Usage: Scripts/RunWindowFixture.sh [--build-only | --large-minimum]' >&2
    exit 1
fi
if /usr/bin/pgrep -x DozerWindowFixture >/dev/null; then
    echo 'Close Dozer Window Fixture before rebuilding it.' >&2
    exit 1
fi

repository_root=$(cd "$(/usr/bin/dirname "$0")/.." && pwd)
fixture_app="$repository_root/build/DozerWindowFixture.app"
frame_log="$repository_root/build/window-fixture-frame.json"
native_arch=$(/usr/bin/uname -m)
sdk_path=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
/bin/mkdir -p "$fixture_app/Contents/MacOS"

/usr/bin/xcrun swiftc -swift-version 5 -target "$native_arch-apple-macosx13.0" -sdk "$sdk_path" \
    "$repository_root/Tests/WindowFixture/main.swift" -framework AppKit \
    -o "$fixture_app/Contents/MacOS/DozerWindowFixture"
/bin/cat > "$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.Dozer.WindowFixture</string>
<key>CFBundleExecutable</key><string>DozerWindowFixture</string>
<key>CFBundleName</key><string>Dozer Window Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - --timestamp=none "$fixture_app"
/usr/bin/codesign --verify --strict "$fixture_app"
echo "Fixture app: $fixture_app"
echo "Frame log: $frame_log"
if [[ "${1:-}" != '--build-only' ]]; then
    /usr/bin/open "$fixture_app" --args --frame-log "$frame_log" "${1:-}"
fi
