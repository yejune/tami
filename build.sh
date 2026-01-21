#!/bin/bash

# Tami Build Script
# Xcode build with proper framework packaging

set -e

APP_NAME="Tami"
BUILD_DIR="build"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

XCODE_BUILD_DIR="${DERIVED_DATA}/Build/Products/${CONFIGURATION}"

echo "🔨 Building ${APP_NAME}..."

# Xcode 빌드
echo "📦 Building with Xcode..."
xcodebuild -scheme Tami -destination 'platform=macOS' -configuration "${CONFIGURATION}" -derivedDataPath "${DERIVED_DATA}" build

# 빌드 디렉토리 생성
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"

# 바이너리 복사
echo "📋 Copying binary..."
cp "${XCODE_BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# 프레임워크 복사
echo "📦 Copying frameworks..."
if [ -d "${XCODE_BUILD_DIR}/Highlighter_Highlighter.bundle" ]; then
    cp -r "${XCODE_BUILD_DIR}/Highlighter_Highlighter.bundle" "${FRAMEWORKS_DIR}/"
    # Also copy to Resources for bundle loading
    cp -r "${XCODE_BUILD_DIR}/Highlighter_Highlighter.bundle" "${RESOURCES_DIR}/"
fi

# Swift 라이브러리 복사
echo "📦 Copying Swift libraries..."
SWIFT_LIBS="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx"
if [ -d "${SWIFT_LIBS}" ]; then
    mkdir -p "${CONTENTS_DIR}/lib"
    cp "${SWIFT_LIBS}/libswiftCompatibilitySpan.dylib" "${CONTENTS_DIR}/lib/" 2>/dev/null || true
fi

# Info.plist 생성
echo "📋 Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Tami</string>
    <key>CFBundleIconFile</key>
    <string></string>
    <key>CFBundleIdentifier</key>
    <string>com.example.Tami</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Tami</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs to control Terminal to open folders.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025. All rights reserved.</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# PkgInfo 생성
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# rpath 설정
echo "🔧 Setting rpath..."
chmod +w "${MACOS_DIR}/${APP_NAME}"
install_name_tool -add_rpath "@executable_path/../lib" "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true

echo "✅ Build complete!"
echo "📍 App location: ${APP_BUNDLE}"
echo ""
echo "실행하려면:"
echo "  open ${APP_BUNDLE}"
