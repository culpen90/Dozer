#!/bin/bash
set -euo pipefail
repository_root=$(cd "$(/usr/bin/dirname "$0")/.." && pwd)
build_dir="$repository_root/build"
/bin/mkdir -p "$build_dir"
sdk_path=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
native_arch=$(/usr/bin/uname -m)
/usr/bin/xcrun swiftc -swift-version 5 -target "$native_arch-apple-macosx13.0" -sdk "$sdk_path" \
    "$repository_root/Dozer/WindowManagement/RectangleWindowAdjustment.swift" \
    "$repository_root/Tests/WindowAdjustmentChecks/main.swift" \
    -framework AppKit -framework ApplicationServices -o "$build_dir/DozerWindowAdjustmentChecks"
/usr/bin/codesign --force --sign - --timestamp=none "$build_dir/DozerWindowAdjustmentChecks"
"$build_dir/DozerWindowAdjustmentChecks" 2>&1 | /usr/bin/tee "$build_dir/window-adjustment-checks.log"
