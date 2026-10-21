#!/bin/bash
set -euo pipefail

repository_root=$(cd "$(/usr/bin/dirname "$0")/.." && pwd)
build_dir="$repository_root/build"
executable="$build_dir/DozerRuntimeChecks"
log_path="$build_dir/runtime-checks.log"

require_stopped_dozer() {
    if /usr/bin/pgrep -x Dozer >/dev/null; then
        echo 'Quit Dozer before running integration checks so its global shortcut does not conflict.' >&2
        exit 1
    fi
}

require_stopped_dozer
/bin/mkdir -p "$build_dir"
native_arch=$(/usr/bin/uname -m)
sdk_path=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
sources=()
while IFS= read -r -d '' source; do
    sources+=("$source")
done < <(/usr/bin/find "$repository_root/Dozer" "$repository_root/DozerCore" \
    -name '*.swift' ! -path "$repository_root/Dozer/Other/main.swift" \
    ! -path "$repository_root/Dozer/Other/Generated/*" -print0)

echo 'Building native macOS runtime checks…'
/usr/bin/xcrun swiftc -swift-version 5 -module-name DozerRuntimeChecks \
    -target "$native_arch-apple-macosx13.0" -sdk "$sdk_path" \
    "${sources[@]}" "$repository_root/Tests/RuntimeChecks/main.swift" \
    -framework AppKit -framework Carbon -framework ServiceManagement \
    -o "$executable"
/usr/bin/codesign --force --sign - --timestamp=none "$executable"

require_stopped_dozer
echo "Running checks in this desktop session; log: $log_path"
"$executable" 2>&1 | /usr/bin/tee "$log_path"
