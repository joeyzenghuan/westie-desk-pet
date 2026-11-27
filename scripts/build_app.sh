#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="WestieDeskPet"
BUNDLE_ID="com.joeyzenghuan.westie-desk-pet"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building ${APP_NAME} (release)..."
cd "${ROOT_DIR}"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copy Sprites directly into Contents/Resources/Sprites (100% portable & codesign-clean!)
cp -R "${ROOT_DIR}/Sources/WestieDeskPet/Resources/Sprites" "${RESOURCES_DIR}/Sprites"

# Also keep SwiftPM resource bundle inside Contents/Resources/
for bundle in "${BIN_DIR}"/*.bundle; do
    if [[ -d "${bundle}" ]]; then
        cp -R "${bundle}" "${RESOURCES_DIR}/"
    fi
done

# Build macOS .icns from Sources/WestieDeskPet/Resources/AppIcon.png if available
ICON_PNG="${ROOT_DIR}/Sources/WestieDeskPet/Resources/AppIcon.png"
if [[ -f "${ICON_PNG}" ]]; then
    ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "${ICONSET_DIR}"
    for sz in 16 32 128 256 512; do
        sips -z "${sz}" "${sz}" "${ICON_PNG}" --out "${ICONSET_DIR}/icon_${sz}x${sz}.png" >/dev/null
        sz2=$((sz * 2))
        sips -z "${sz2}" "${sz2}" "${ICON_PNG}" --out "${ICONSET_DIR}/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "$(dirname "${ICONSET_DIR}")"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Westie Desk Pet</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>10</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc codesign so macOS Gatekeeper / local launch runs cleanly
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo "==> Packaged macOS app bundle at: ${APP_BUNDLE}"
echo "    Launch with: open \"${APP_BUNDLE}\""
