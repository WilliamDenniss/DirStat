#!/bin/sh
# Copyright 2026 The DirStat Authors.
# Modified 2026-09-04.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR=${DIX_BUILD_DIR:-"$SCRIPT_DIR/build"}
mkdir -p "$BUILD_DIR"
BUILD_DIR=$(CDPATH= cd -- "$BUILD_DIR" && pwd)

xcodebuild \
    -project "$SCRIPT_DIR/Sources/TreeMapView/TreeMapView.xcodeproj" \
    -scheme TreeMapView \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData/TreeMapView" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/TreeMap" \
    MACOSX_DEPLOYMENT_TARGET=10.13 \
    ALWAYS_SEARCH_USER_PATHS=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    build

xcodebuild \
    -project "$SCRIPT_DIR/Disk Inventory X.xcodeproj" \
    -scheme 'Disk Inventory X' \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData/DiskInventoryX" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
    DIX_FRAMEWORK_DIR="$BUILD_DIR/TreeMap" \
    ALWAYS_SEARCH_USER_PATHS=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    build

APP="$BUILD_DIR/Release/Disk Inventory X.app"
# Sign nested code first; this is a local ad-hoc build, with no developer account.
codesign --force --sign - "$APP/Contents/Frameworks/TreeMapView.framework"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "Built $APP"
