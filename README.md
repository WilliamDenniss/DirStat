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

## Tests

```sh
./Tests/run.sh
```

Run in a logged-in macOS session with the pasteboard service available. Tests
use temporary fixtures and a private pasteboard.

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
