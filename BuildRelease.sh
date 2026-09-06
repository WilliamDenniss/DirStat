#!/bin/sh
# Copyright 2026 The DirStat Authors.
# Modified 2026-09-05.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR=${DIX_BUILD_DIR:-"$SCRIPT_DIR/build"}
mkdir -p "$BUILD_DIR"
BUILD_DIR=$(CDPATH= cd -- "$BUILD_DIR" && pwd)

xcodebuild \
    -project "$SCRIPT_DIR/DirStat.xcodeproj" \
    -scheme 'DirStat' \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData/DirStat" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
    ONLY_ACTIVE_ARCH=NO \
    build

APP="$BUILD_DIR/Release/DirStat.app"
codesign --verify --strict "$APP"

echo "Built $APP"
