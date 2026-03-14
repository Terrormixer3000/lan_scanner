#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-LAN Scanner.app}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
EXECUTABLE_PATH=".build/${BUILD_CONFIG}/LanScanner"
APP_EXECUTABLE="${APP_DIR}/Contents/MacOS/LanScanner"
INFO_PLIST_PATH="Sources/LanScanner/Info.plist"
ICON_PATH="Sources/LanScanner/AppIcon.icns"
ASSET_CATALOG_PATH="Sources/LanScanner/Assets.xcassets"
FRAMEWORKS_RPATH="@executable_path/../Frameworks"

if [ ! -x "${EXECUTABLE_PATH}" ]; then
  echo "error: missing executable at ${EXECUTABLE_PATH}. Run 'swift build -c ${BUILD_CONFIG}' first." >&2
  exit 1
fi

if [ ! -f "${INFO_PLIST_PATH}" ]; then
  echo "error: missing Info.plist at ${INFO_PLIST_PATH}." >&2
  exit 1
fi

if [ ! -f "${ICON_PATH}" ]; then
  echo "error: missing app icon at ${ICON_PATH}." >&2
  exit 1
fi

SPARKLE_PATH="$(find .build -path "*/${BUILD_CONFIG}/Sparkle.framework" -type d | head -1)"
if [ -z "${SPARKLE_PATH}" ]; then
  echo "error: missing Sparkle.framework in .build. Re-run 'swift build -c ${BUILD_CONFIG}'." >&2
  exit 1
fi

mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/Frameworks"

cp "${EXECUTABLE_PATH}" "${APP_EXECUTABLE}"
cp "${INFO_PLIST_PATH}" "${APP_DIR}/Contents/Info.plist"
cp "${ICON_PATH}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
ditto "${SPARKLE_PATH}" "${APP_DIR}/Contents/Frameworks/Sparkle.framework"

if command -v actool >/dev/null 2>&1; then
  actool "${ASSET_CATALOG_PATH}" \
    --compile "${APP_DIR}/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /tmp/actool-partial.plist
fi

if ! otool -l "${APP_EXECUTABLE}" | grep -Fq "${FRAMEWORKS_RPATH}"; then
  install_name_tool -add_rpath "${FRAMEWORKS_RPATH}" "${APP_EXECUTABLE}"
fi

if [ -n "${APP_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" \
    "${APP_DIR}/Contents/Info.plist"
fi

if [ -n "${APP_BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_BUILD_NUMBER}" \
    "${APP_DIR}/Contents/Info.plist"
fi
