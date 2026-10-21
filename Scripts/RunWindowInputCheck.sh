#!/bin/bash
# Native input must be explicitly authorized; target must be the disposable fixture.
# Example: Scripts/RunWindowInputCheck.sh --pid 12345 --action drag-left --allow-native-input
set -euo pipefail
repository_root=$(cd "$(/usr/bin/dirname "$0")/.." && pwd)
helper_path="$repository_root/build/DozerWindowInputChecks"
if [[ " $* " != *' --allow-native-input '* ]]; then
    echo 'Refusing native input without --allow-native-input.' >&2
    exit 1
fi
/bin/mkdir -p "$repository_root/build"
native_arch=$(/usr/bin/uname -m)
sdk_path=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
/usr/bin/xcrun swiftc -swift-version 5 -target "$native_arch-apple-macosx13.0" -sdk "$sdk_path" \
    "$repository_root/Tests/WindowInputChecks/main.swift" -framework AppKit -framework ApplicationServices \
    -o "$helper_path"
/usr/bin/codesign --force --sign - --timestamp=none "$helper_path"
"$helper_path" "$@"
