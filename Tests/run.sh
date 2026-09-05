#!/bin/sh
# Copyright 2026 The DirStat Authors.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dix-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
cd "$PROJECT_DIR"

xcrun clang -fno-objc-arc -fblocks -isysroot "$(xcrun --show-sdk-path)" \
    -I Sources -I Sources/CocoaTech-Depreciated -include 'Sources/DirStat_Prefix.pch' \
    -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-error=int-conversion \
    -framework Cocoa -framework Carbon \
    Tests/RegressionTests.m Tests/UICompatibilityTests.m Tests/PreferenceResetTests.m \
    Sources/OmniCompatibility.m Sources/PrefsPanelController.m Sources/OAToolbarWindowControllerEx.m \
    Sources/DIXTableView.m Sources/DIXOutlineView.m Sources/AppsForItem.m \
    Sources/FSItem.m Sources/NSURL-Extensions.m Sources/CocoaTech-Depreciated/NTFilePasteboardSource.m \
    -o "$TEST_DIR/RegressionTests"

"$TEST_DIR/RegressionTests"

xcrun clang -fno-objc-arc -fblocks -isysroot "$(xcrun --show-sdk-path)" \
    -I Sources -include 'Sources/DirStat_Prefix.pch' \
    -Wno-deprecated-declarations -Wno-nullability-completeness \
    -framework Cocoa -framework Carbon \
    Tests/WindowLifecycleTests.m Sources/SelectionListController.m Sources/GenericArrayController.m \
    Sources/FSItemIndex.m Sources/Timing.c Sources/OmniCompatibility.m \
    -o "$TEST_DIR/WindowLifecycleTests"

"$TEST_DIR/WindowLifecycleTests"
