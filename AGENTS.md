# Repository Guidelines

## Project Structure & Module Organization

This is a macOS Swift Package. The executable lives in
`Sources/AirDropAutoAccept/main.swift` and combines AppKit with the Accessibility
API to inspect Finder and system notification UI. `Package.swift` declares the
macOS 13 target. `Info.plist` contains app-bundle metadata and background-only
behavior. `Assets/` contains the checked-in `.icns` icon and its iconset source.
`build.sh` creates the distributable app bundle; generated `.build/` contents
and ZIP files are ignored.

## Build, Test, and Development Commands

Run from this directory:

```sh
./build.sh
swift build -c debug
plutil -lint Info.plist
../../outputs/AirDropAutoAccept.app/Contents/MacOS/AirDropAutoAccept --status
```

`build.sh` compiles arm64 and x86_64 release binaries, combines them into a
Universal Binary, copies the plist and icon, and writes the app under
`../../outputs/`. There is currently no XCTest target or automated test suite.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift naming: `UpperCamelCase` for
types and `lowerCamelCase` for methods and properties. Keep Accessibility tree
traversal bounded, preserve the sender filter, and retain action throttling when
changing detection logic. No formatter or linter is configured.

## Testing Guidelines

For behavior changes, grant Accessibility permission, send files from
`Pixel 10 Pro Fold`, and verify acceptance plus the resulting files in
`~/Downloads`. Test multiple file types when changing matching or menu logic.

## Commit & Pull Request Guidelines

No Git history is available in the initial checkout, so existing conventions
cannot be confirmed. Use short imperative subjects such as
`fix: detect Downloads menu item`. PRs should describe macOS version, permission
setup, sender/file types tested, and include relevant logs or screenshots.

## Safety & Harness Maintenance

This utility controls system UI only for the configured sender and requires
Accessibility permission. Do not broaden matching or press arbitrary controls
without a focused manual test. Update this guide when a repeatable failure mode
or a new required verification command is discovered.
