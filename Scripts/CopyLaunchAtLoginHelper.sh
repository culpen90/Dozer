#!/bin/sh

set -eu

helper_checksum="0a3d09438fb595802d554ce0a7c4ba8e1d2d91d5170362adc965da82e70d74cb"
helper_checksum_runtime="98ef556b490e02f4084a11d8a07c33a880177a9816b355885a11f58c95876d62"

version_lte() {
    [ "$1" = "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" ]
}

if version_lte "10.14.4" "${MACOSX_DEPLOYMENT_TARGET}"; then
    helper_name="LaunchAtLoginHelper"
    expected_checksum="$helper_checksum"
else
    helper_name="LaunchAtLoginHelper-with-runtime"
    expected_checksum="$helper_checksum_runtime"
fi

package_resources_path="${BUILT_PRODUCTS_DIR}/LaunchAtLogin_LaunchAtLogin.bundle/Contents/Resources"
helper_archive="${package_resources_path}/${helper_name}.zip"
contents_path="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}"
login_items_path="${contents_path}/Library/LoginItems"
login_helper_path="${login_items_path}/LaunchAtLoginHelper.app"
helper_entitlements="${package_resources_path}/LaunchAtLogin.entitlements"

actual_checksum="$(shasum -a 256 "$helper_archive" | awk '{print $1}')"
if [ "$actual_checksum" != "$expected_checksum" ]; then
    echo "error: LaunchAtLoginHelper checksum does not match the pinned package"
    exit 1
fi

rm -rf "$login_helper_path"
mkdir -p "$login_items_path"
/usr/bin/ditto -x -k "$helper_archive" "$login_items_path"

/usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier ${PRODUCT_BUNDLE_IDENTIFIER}-LaunchAtLoginHelper" \
    "$login_helper_path/Contents/Info.plist"

signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
if [ -z "$signing_identity" ]; then
    signing_identity="-"
fi

if [ -f "$helper_entitlements" ]; then
    /usr/bin/codesign --force \
        --entitlements "$helper_entitlements" \
        --options runtime \
        --sign "$signing_identity" \
        "$login_helper_path"
else
    /usr/bin/codesign --force \
        --options runtime \
        --sign "$signing_identity" \
        "$login_helper_path"
fi

/usr/bin/codesign --verify --strict --verbose=2 "$login_helper_path"
