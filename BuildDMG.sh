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
# previously notarized release. Only the final successful artifacts are promoted.
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
    ''|*[!A-Za-z0-9._-]*) fail 'The app version contains characters unsuitable for a release filename.' ;;
esac

notarize() {
    xcrun notarytool "$@" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD"
}

submit_for_notarization() {
    NOTARY_ITEM=$1
    NOTARY_LABEL=$2
    NOTARY_BASENAME=$3
    NOTARY_SUBMISSION="$RUN_DIR/notary-$NOTARY_BASENAME-submission.json"
    NOTARY_LOG="$RUN_DIR/notary-$NOTARY_BASENAME-log.json"
    NOTARY_SUBMIT_EXIT=0

    printf 'Submitting %s to Apple for notarization...\n' "$NOTARY_LABEL"
    notarize submit "$NOTARY_ITEM" --wait --timeout "${NOTARY_TIMEOUT:-30m}" \
        --output-format json > "$NOTARY_SUBMISSION" || NOTARY_SUBMIT_EXIT=$?
    if ! NOTARY_SUBMISSION_ID=$(plutil -extract id raw -o - "$NOTARY_SUBMISSION" 2>/dev/null); then
        NOTARY_SUBMISSION_ID=
    fi
    if ! NOTARY_STATUS=$(plutil -extract status raw -o - "$NOTARY_SUBMISSION" 2>/dev/null); then
        NOTARY_STATUS=
    fi

    if [ -n "$NOTARY_SUBMISSION_ID" ]; then
        printf '%s notarization submission: %s (%s)\n' \
            "$NOTARY_LABEL" "$NOTARY_SUBMISSION_ID" "${NOTARY_STATUS:-unknown status}"
        # Save Apple's warnings even on acceptance, and errors on rejection.
        if ! notarize log "$NOTARY_SUBMISSION_ID" "$NOTARY_LOG"; then
            printf '%s notarization log is not available yet; submission details: %s\n' \
                "$NOTARY_LABEL" "$NOTARY_SUBMISSION" >&2
        fi
    fi
    if [ "$NOTARY_SUBMIT_EXIT" -ne 0 ] || [ "$NOTARY_STATUS" != Accepted ]; then
        fail "$NOTARY_LABEL notarization did not complete successfully (${NOTARY_STATUS:-no status}). See $NOTARY_SUBMISSION and any $NOTARY_LOG."
    fi
}

# ZIP files cannot carry a stapled ticket. Submit a temporary ZIP, staple the
# resulting ticket to the app, then package the stapled app in the release ZIP.
printf 'Creating app archive for notarization...\n'
APP_NOTARY_ZIP="$RUN_DIR/DirStat-$VERSION-notary-submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_NOTARY_ZIP"
submit_for_notarization "$APP_NOTARY_ZIP" 'app archive' app

printf 'Stapling and verifying app notarization...\n'
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"

printf 'Creating distributable ZIP...\n'
ZIP="$RUN_DIR/DirStat-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ZIP_VERIFY_ROOT="$RUN_DIR/ZIPVerify"
mkdir -p "$ZIP_VERIFY_ROOT"
ditto -x -k "$ZIP" "$ZIP_VERIFY_ROOT"
ZIP_APP="$ZIP_VERIFY_ROOT/DirStat.app"
codesign --verify --deep --strict --verbose=2 "$ZIP_APP"
xcrun stapler validate "$ZIP_APP"
spctl --assess --type execute --verbose=2 "$ZIP_APP"

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

submit_for_notarization "$DMG" DMG dmg

printf 'Stapling and verifying DMG notarization...\n'
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

FINAL_DMG="$OUTPUT_DIR/DirStat-$VERSION.dmg"
FINAL_ZIP="$OUTPUT_DIR/DirStat-$VERSION.zip"
mv -f "$DMG" "$FINAL_DMG"
mv -f "$ZIP" "$FINAL_ZIP"
printf 'Notarized DMG: %s\nNotarized ZIP: %s\nNotarization logs: %s\n' \
    "$FINAL_DMG" "$FINAL_ZIP" "$RUN_DIR"
