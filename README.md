# DirStat

A macOS disk usage analyzer written in Objective-C and Cocoa. It displays file
and folder sizes in a treemap, with colors indicating file types.

## Build

Requires Xcode 26 or later, selected as the default for command-line builds.

```sh
./BuildRelease.sh
```

Builds the included TreeMapView framework and a universal Apple Silicon / Intel
app, signed ad hoc for local use. No Apple developer account is required.

Output: `build/Release/DirStat.app`. Set `DIX_BUILD_DIR` to change the
build directory. For builds in Xcode, run the script first to build TreeMapView.
If using a custom build directory, set `DIX_FRAMEWORK_DIR` to the directory
containing `TreeMapView.framework`.

## Tests

```sh
./Tests/run.sh
```

Run in a logged-in macOS session with the pasteboard service available. Tests
use temporary fixtures and a private pasteboard.

## License

DirStat and its source code are released under the GNU General Public License
(GPL).
