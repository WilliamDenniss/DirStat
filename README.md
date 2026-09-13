# DirStat for Mac

A macOS disk usage analyzer written in Objective-C and Cocoa. It displays file
and folder sizes in a treemap, with colors indicating file types.

## Build

Requires Xcode 26 or later, selected as the default for command-line builds.

Open `DirStat.xcodeproj`, select the `DirStat` scheme, and Build or Run.

For a universal Apple Silicon / Intel release build:

```sh
./BuildRelease.sh
```

Both Xcode and the script sign the app ad hoc for local use.
No Apple developer account is required.

Output: `build/Release/DirStat.app`. Set `DIX_BUILD_DIR` to change the
build directory used by the script.

## Notarized DMG and ZIP

Requires Apple Developer Program membership, a **Developer ID Application**
certificate with its private key installed in an unlocked keychain, and network
access to Apple's signing and notarization services.

```sh
cp .env.example .env
```

Fill in `.env` with the exact signing certificate name, Apple team ID, Apple ID,
and an [app-specific password](https://account.apple.com/). The script reads all
identities from this file. `.env` uses shell syntax, is loaded from the project
directory regardless of the working directory, and is ignored by Git.

```sh
./BuildDMG.sh
```

The script builds a universal Apple Silicon / Intel app with hardened runtime
and Developer ID signing. It submits a temporary app ZIP to Apple, waits for
acceptance, and staples the resulting ticket to the app. Because notarization
tickets cannot be stapled directly to ZIP files, as described in
[Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
the script then creates and verifies a fresh ZIP containing the stapled app.
It packages the same app in a compressed DMG, signs and notarizes the DMG, and
verifies both artifacts before saving
`build/Notarized/DirStat-<version>.{dmg,zip}`.

Install the optional packaging tool for the custom Finder background and
drag-to-Applications layout:

```sh
brew install create-dmg
```

When `create-dmg` is on `PATH`, the script uses
`Packaging/DMG/background.png` and saves the app and Applications shortcut
positions in the DMG. Styling requires a logged-in macOS session and permission
for the terminal running the script to control Finder. If `create-dmg` is
missing, the script prints a warning and the install command, then builds the
plain DMG with `hdiutil`. A failure from an installed `create-dmg` stops the
release. Both packaging paths use the same signing and notarization checks.

Set `DIX_BUILD_DIR` and `NOTARY_TIMEOUT` in `.env` to change the output directory
and wait limit. Relative build paths resolve from the project directory.
Each attempt retains its build files, submission responses, and any available
Apple logs under `build/Notarized/run.*`. A failed attempt leaves existing
release artifacts untouched. A timeout does not cancel Apple's processing; the
saved submission ID can be used with `xcrun notarytool info`, `wait`, or `log`
to check the existing submission. Review both logs and test installation from
the final DMG and ZIP before publishing a release.

## Tests

```sh
./Tests/run.sh
```

Run in a logged-in macOS session with the pasteboard service available. Tests
use temporary fixtures and a private pasteboard.

To check the release workflow without signing credentials or network calls:

```sh
python3 Tests/BuildDMGTests.py
```

## Credits

DirStat for Mac is a fork of Disk Inventory X by Tjark Derlien.

Original Disk Inventory X credits:

- Tjark Derlien — engineering, German translation, and documentation
- Daniel Girod — testing
- Florian de la Motte Rouge — testing
- Antoine Desir — French translation
- Oscar Ferrer — Spanish translation

## License

The source code for DirStat for Mac is released under the GNU General Public
License (GPL).

The DirStat for Mac logo and app icon artwork is not licensed under the GPL and
is subject to separate terms; see [BRANDING.md](BRANDING.md).
