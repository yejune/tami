#!/bin/bash

# Tami Build Script
# macOS AppKit 앱 빌드 스크립트

set -e

APP_NAME="Tami"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 소스 파일들
SOURCES=(
    "Tami/main.swift"
    "Tami/AppDelegate.swift"
    "Tami/MainWindowController.swift"
    "Tami/MainSplitViewController.swift"
    "Tami/TerminalTabViewController.swift"
    "Tami/SidebarViewController.swift"
    "Tami/TerminalViewController.swift"
    "Tami/FavoritesManager.swift"
)

# SwiftTerm 소스 추가 (macOS 기본 bash 호환)
SWIFTTERM_SOURCES=()
while IFS= read -r -d '' file; do
    SWIFTTERM_SOURCES+=("$file")
done < <(find "SwiftTerm/Sources/SwiftTerm" -name "*.swift" -print0)

echo "🔨 Building ${APP_NAME}..."

# 빌드 디렉토리 생성
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Swift 컴파일
echo "📦 Compiling Swift sources..."
swiftc \
    -o "${MACOS_DIR}/${APP_NAME}" \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework AppKit \
    -framework SwiftUI \
    -framework CoreText \
    "${SOURCES[@]}" \
    "${SWIFTTERM_SOURCES[@]}"

# Info.plist 복사
echo "📋 Copying Info.plist..."
cp "Tami/Info.plist" "${CONTENTS_DIR}/Info.plist"

# PkgInfo 생성
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "✅ Build complete!"
echo "📍 App location: ${APP_BUNDLE}"
echo ""
echo "실행하려면:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "또는:"
echo "  ./${MACOS_DIR}/${APP_NAME}"
