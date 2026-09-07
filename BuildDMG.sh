#!/bin/sh
# Copyright 2026 The DirStat Authors.
# Modified 2026-09-06.

# Never trace credentials, including when invoked with sh -x.
set +x
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ -f "$ENV_FILE" ] || fail "Copy .env.example to $ENV_FILE and fill in your credentials."

# Identities must come from this file, not the caller's environment.
unset CODE_SIGN_IDENTITY APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD
# .env is a trusted shell file; quote values as shown in .env.example.
# shellcheck source=.env.example
. "$ENV_FILE"

[ -n "${CODE_SIGN_IDENTITY:-}" ] || fail 'Set CODE_SIGN_IDENTITY in .env.'
[ -n "${APPLE_TEAM_ID:-}" ] || fail 'Set APPLE_TEAM_ID in .env.'
[ -n "${APPLE_ID:-}" ] || fail 'Set APPLE_ID in .env.'
[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] || fail 'Set APPLE_APP_SPECIFIC_PASSWORD in .env.'

case "$APPLE_TEAM_ID" in
    *[!A-Z0-9]*|'') fail 'APPLE_TEAM_ID must be your 10-character Apple team ID.' ;;
esac
[ "${#APPLE_TEAM_ID}" -eq 10 ] || fail 'APPLE_TEAM_ID must be your 10-character Apple team ID.'
case "$CODE_SIGN_IDENTITY" in
    "Developer ID Application: "*" ($APPLE_TEAM_ID)") ;;
    *) fail 'CODE_SIGN_IDENTITY must be the full Developer ID Application certificate name for APPLE_TEAM_ID.' ;;
esac
case "$APPLE_ID:$APPLE_APP_SPECIFIC_PASSWORD" in
    *YOUR_*|*your-apple-id@example.com*|*:xxxx-xxxx-xxxx-xxxx)
        fail 'Replace the Apple ID and app-specific password placeholders in .env.' ;;
esac

for tool in xcodebuild xcrun security codesign ditto hdiutil plutil spctl; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool is missing: $tool"
done
USE_CREATE_DMG=0
if command -v create-dmg >/dev/null 2>&1; then
    USE_CREATE_DMG=1
    DMG_BACKGROUND="$SCRIPT_DIR/Packaging/DMG/background.png"
    [ -f "$DMG_BACKGROUND" ] || fail "DMG background is missing: $DMG_BACKGROUND"
else
    printf 'Warning: create-dmg is not installed; building the plain DMG.\nInstall it for the custom background and Finder layout: brew install create-dmg\n' >&2
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null

IDENTITIES=$(security find-identity -v -p codesigning)
case "$IDENTITIES" in
    *"\"$CODE_SIGN_IDENTITY\""*) ;;
    *) fail 'The configured signing identity is unavailable. Install its certificate and private key in an unlocked keychain.' ;;
esac

BUILD_DIR=${DIX_BUILD_DIR:-"$SCRIPT_DIR/build"}
case "$BUILD_DIR" in
    /*) ;;
    *) BUILD_DIR="$SCRIPT_DIR/$BUILD_DIR" ;;
esac
mkdir -p "$BUILD_DIR/Notarized"
OUTPUT_DIR=$(CDPATH= cd -- "$BUILD_DIR/Notarized" && pwd)
# Keep each attempt separate so failures preserve both diagnostics and any
# previously notarized release. Only the final successful DMG is promoted.
RUN_DIR=$(mktemp -d "$OUTPUT_DIR/run.XXXXXX")
trap 'result=$?; if [ "$result" -ne 0 ]; then printf "Build files and diagnostics: %s\n" "$RUN_DIR" >&2; fi' 0

printf 'Building universal DirStat release...\n'
xcodebuild \
    -project "$SCRIPT_DIR/DirStat.xcodeproj" \
    -scheme DirStat \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$RUN_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$RUN_DIR/Release" \
    ONLY_ACTIVE_ARCH=NO \
    'ARCHS=arm64 x86_64' \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    build

APP="$RUN_DIR/Release/DirStat.app"
codesign --verify --deep --strict --verbose=2 "$APP"
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "$APP/Contents/Info.plist")
case "$VERSION" in
    ''|*[!A-Za-z0-9._-]*) fail 'The app version contains characters unsuitable for a DMG filename.' ;;
esac

printf 'Creating and signing DMG...\n'
DMG_ROOT="$RUN_DIR/DMGRoot"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/DirStat.app"
DMG="$RUN_DIR/DirStat-$VERSION.dmg"
if [ "$USE_CREATE_DMG" -eq 1 ]; then
    # The 2x background is 768 x 512 points; allow 28 points for the title bar.
    # create-dmg creates the Applications shortcut and saves the Finder layout.
    create-dmg \
        --volname DirStat \
        --background "$DMG_BACKGROUND" \
        --window-pos 200 120 \
        --window-size 768 540 \
        --icon-size 128 \
        --text-size 14 \
        --icon DirStat.app 199 270 \
        --hide-extension DirStat.app \
        --app-drop-link 568 270 \
        --filesystem HFS+ \
        --format UDZO \
        "$DMG" "$DMG_ROOT"
else
    ln -s /Applications "$DMG_ROOT/Applications"
    hdiutil create -volname DirStat -srcfolder "$DMG_ROOT" -fs HFS+ -format UDZO "$DMG"
fi
codesign --sign "$CODE_SIGN_IDENTITY" --timestamp \
    --identifier "$BUNDLE_ID.dmg" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
hdiutil verify "$DMG"

notarize() {
    xcrun notarytool "$@" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD"
}

printf 'Submitting DMG to Apple for notarization...\n'
SUBMISSION="$RUN_DIR/notary-submission.json"
SUBMIT_EXIT=0
notarize submit "$DMG" --wait --timeout "${NOTARY_TIMEOUT:-30m}" \
    --output-format json > "$SUBMISSION" || SUBMIT_EXIT=$?
if ! SUBMISSION_ID=$(plutil -extract id raw -o - "$SUBMISSION" 2>/dev/null); then
    SUBMISSION_ID=
fi
if ! STATUS=$(plutil -extract status raw -o - "$SUBMISSION" 2>/dev/null); then
    STATUS=
fi

if [ -n "$SUBMISSION_ID" ]; then
    printf 'Notarization submission: %s (%s)\n' "$SUBMISSION_ID" "${STATUS:-unknown status}"
    # Save Apple's warnings even on acceptance, and errors on rejection.
    if ! notarize log "$SUBMISSION_ID" "$RUN_DIR/notary-log.json"; then
        printf 'Notarization log is not available yet; submission details: %s\n' "$SUBMISSION" >&2
    fi
fi
if [ "$SUBMIT_EXIT" -ne 0 ] || [ "$STATUS" != Accepted ]; then
    fail "Notarization did not complete successfully (${STATUS:-no status}). See $SUBMISSION and any notary-log.json."
fi

printf 'Stapling and verifying notarization...\n'
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

FINAL_DMG="$OUTPUT_DIR/DirStat-$VERSION.dmg"
mv -f "$DMG" "$FINAL_DMG"
printf 'Notarized DMG: %s\nNotarization logs: %s\n' "$FINAL_DMG" "$RUN_DIR"
