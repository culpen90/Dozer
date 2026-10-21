#!/bin/bash
set -euo pipefail

app_path=${1:?Usage: SignApp.sh /path/to/Dozer.app}
# Local ad-hoc signing requires no Apple Developer account. This is not notarization.
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
