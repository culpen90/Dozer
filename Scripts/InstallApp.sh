#!/bin/bash
set -euo pipefail

source_app=${1:?Usage: InstallApp.sh /path/to/Dozer.app [destination]}
destination=${2:-/Applications/Dozer.app}
if [[ ! -d "$source_app" ]]; then
    echo "Built app not found: $source_app" >&2
    exit 1
fi
if /usr/bin/pgrep -x Dozer >/dev/null; then
    echo 'Quit Dozer before replacing it, then run make install again.' >&2
    exit 1
fi
if [[ -e "$destination" && ! -d "$destination/Contents" ]]; then
    echo "Refusing to replace a destination that is not an app: $destination" >&2
    exit 1
fi

parent_dir=$(/usr/bin/dirname "$destination")
/bin/mkdir -p "$parent_dir"
staging_dir=$(/usr/bin/mktemp -d "$parent_dir/.Dozer-install.XXXXXX")
trap '/bin/rm -rf "$staging_dir"' EXIT
/usr/bin/ditto "$source_app" "$staging_dir/Dozer.app"
/usr/bin/codesign --verify --strict "$staging_dir/Dozer.app"

if [[ -e "$destination" ]]; then
    backup_root="$HOME/Library/Application Support/Dozer/Backups"
    /bin/mkdir -p "$backup_root"
    backup_name="Dozer-$(/bin/date +%Y%m%d-%H%M%S)-$$.app"
    /usr/bin/ditto "$destination" "$backup_root/$backup_name"
    /bin/rm -rf "$destination"
    echo "Previous app backed up to $backup_root/$backup_name"
fi
/bin/mv "$staging_dir/Dozer.app" "$destination"
echo "Installed $destination"
