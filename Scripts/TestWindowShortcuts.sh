#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(/usr/bin/dirname "$0")/.." && pwd)
build_dir="$repository_root/build"
executable="$build_dir/DozerWindowShortcutChecks"
log_path="$build_dir/window-shortcut-checks.log"

require_stopped_dozer() {
    if /usr/bin/pgrep -x Dozer >/dev/null; then
        echo 'Quit Dozer before running window shortcut checks so its global shortcuts do not conflict.' >&2
        exit 1
    fi
}

require_stopped_dozer
/bin/mkdir -p "$build_dir"
native_arch=$(/usr/bin/uname -m)
sdk_path=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)

echo 'Building native window shortcut checks from production sources…'
/usr/bin/xcrun swiftc -swift-version 5 -module-name DozerWindowShortcutChecks \
    -target "$native_arch-apple-macosx13.0" -sdk "$sdk_path" \
    "$repository_root/Dozer/HotKeyManager.swift" \
    "$repository_root/Dozer/WindowManagement/WindowShortcutManager.swift" \
    "$repository_root/Dozer/WindowManagement/WindowShortcutRecorder.swift" \
    "$repository_root/Dozer/WindowManagement/WindowManager.swift" \
    "$repository_root/Dozer/WindowManagement/WindowDragManager.swift" \
    "$repository_root/Dozer/WindowManagement/RectangleWindowAdjustment.swift" \
    "$repository_root/DozerCore/WindowLayout.swift" \
    "$repository_root/Tests/WindowShortcutChecks/main.swift" \
    -framework AppKit -framework Carbon -framework ApplicationServices \
    -o "$executable"
/usr/bin/codesign --force --sign - --timestamp=none "$executable"

require_stopped_dozer
echo "Running isolated Carbon shortcut checks; log: $log_path"
"$executable" 2>&1 | /usr/bin/tee "$log_path"
