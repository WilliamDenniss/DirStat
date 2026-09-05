#!/bin/sh
# Copyright 2026 The DirStat Authors.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dix-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
cd "$PROJECT_DIR"

xcrun clang -fno-objc-arc -fblocks -isysroot "$(xcrun --show-sdk-path)" \
    -I . -I CocoaTech-Depreciated -include 'Disk Inventory X_Prefix.pch' \
    -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-error=int-conversion \
    -framework Cocoa -framework Carbon \
    Tests/RegressionTests.m Tests/UICompatibilityTests.m Tests/PreferenceResetTests.m \
    OmniCompatibility.m PrefsPanelController.m OAToolbarWindowControllerEx.m \
    DIXTableView.m DIXOutlineView.m AppsForItem.m \
    FSItem.m NSURL-Extensions.m CocoaTech-Depreciated/NTFilePasteboardSource.m \
    -o "$TEST_DIR/RegressionTests"

"$TEST_DIR/RegressionTests"

xcrun clang -fno-objc-arc -fblocks -isysroot "$(xcrun --show-sdk-path)" \
    -I . -include 'Disk Inventory X_Prefix.pch' \
    -Wno-deprecated-declarations -Wno-nullability-completeness \
    -framework Cocoa -framework Carbon \
    Tests/WindowLifecycleTests.m SelectionListController.m GenericArrayController.m \
    FSItemIndex.m Timing.c OmniCompatibility.m \
    -o "$TEST_DIR/WindowLifecycleTests"

"$TEST_DIR/WindowLifecycleTests"
