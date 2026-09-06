# DirStat

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

## Notarized DMG

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
and Developer ID signing, creates a compressed DMG containing `DirStat.app` and
an Applications shortcut, signs the DMG, submits it to Apple, and waits for
acceptance. It then staples the ticket and verifies the signature, staple, and
Gatekeeper assessment before saving `build/Notarized/DirStat-<version>.dmg`.

Set `DIX_BUILD_DIR` and `NOTARY_TIMEOUT` in `.env` to change the output directory
and wait limit. Relative build paths resolve from the project directory.
Each attempt retains its build files, submission response, and any available
Apple log under `build/Notarized/run.*`. A failed attempt leaves an existing
release DMG untouched. A timeout does not cancel Apple's processing; the saved
submission ID can be used with `xcrun notarytool info`, `wait`, or `log` to check
the existing submission. Review the log for warnings and test installation from
the final DMG before publishing a release.

## Tests

```sh
./Tests/run.sh
```

Run in a logged-in macOS session with the pasteboard service available. Tests
use temporary fixtures and a private pasteboard.

To check the DMG release workflow without signing credentials or network calls:

```sh
python3 Tests/BuildDMGTests.py
```

## License

DirStat and its source code are released under the GNU General Public License
(GPL).
