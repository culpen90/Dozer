# Contributing to Dozer

Report problems and propose changes in this repository’s issues. A useful bug report includes the app version, macOS version, Mac architecture, display arrangement, whether a display has a notch, and steps to reproduce the behavior.

## Getting started

Use macOS 13 or later, a current compatible Xcode installation, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Select the Xcode installation with `xcode-select` and accept its license before building.

```sh
brew install xcodegen
make test
make build
open build/Build/Products/Debug/Dozer.app
```

The build generates `Dozer.xcodeproj` from `project.yml`. Use `make project` to regenerate it after changing sources or project settings, then open that project in Xcode if desired. Generated projects and build products are ignored by Git. Do not add Carthage frameworks or generated asset wrappers; the application uses system frameworks and the asset catalog directly.

`DozerCore/` contains the same state and window geometry logic compiled into both the app and a SwiftPM library. Put deterministic tests in `Tests/DozerTests/` with `@testable import DozerCore`. `make test` runs these tests without opening a menu bar application. Keep AppKit and GUI behavior in the application target.

Use `make test-runtime` in an active macOS desktop session for production-source integration checks. Quit Dozer first so its registered shortcut does not conflict with the test process. The checks create and remove their own menu items, briefly exercise overflow hiding, and restore visibility before exiting. They never drag or remove another app’s item. Read `build/runtime-checks.log` for the summary and relevant geometry.

Use `make test-window-shortcuts` with Dozer and other window managers quit for real Carbon registration checks. It compiles the production shortcut/recorder sources, uses an isolated preference suite, and never moves an application window or asks for Accessibility. Results are in `build/window-shortcut-checks.log`.

For live placement tests, build/install Dozer and explicitly enable its Accessibility permission. Run `Scripts/RunWindowFixture.sh` to open a disposable native window rather than moving personal windows. Its current AppKit/Accessibility frame and screen geometry are recorded in `build/window-fixture-frame.json`. Use Dozer shortcuts, layout buttons, drag snapping, Option bypass, and restore; close the fixture when finished. `--build-only` compiles the fixture without launching it; `--large-minimum` launches it with a 1000 × 700 minimum size for constrained placement checks.

The optional `Scripts/RunWindowInputCheck.sh` helper posts native events only after the operator explicitly opts in with `--allow-native-input`. Pass the running fixture's `--pid` and one `--action`: `shortcut-left`, `drag-left`, or `option-drag-left`. It checks the exact fixture executable and window, requires existing event-posting access, activates the fixture, and aborts on focus loss. Keep physical input idle during a check. Read its preview diagnostics and independently verify the frame log; event posting alone is not a passing placement check.

## Runtime validation

Use a separate test menu bar item when checking hiding, and restore its original layout afterward. Check ordinary hide/reveal, the optional extra group, shortcut recording and conflicts, no-icon recovery, auto-hide, and reopening the app from Finder. For window actions, verify actual frames, gaps, restore history, drag cancellation, and permission loss. Check wake, display changes, and full-screen Spaces when those affect the change. Record the environments actually tested; a passing state test does not establish visual layout on every display.

`make release` builds a universal Apple Silicon/Intel app. `make install` installs the Release app in `/Applications`, backs up an existing app, and refuses to replace a running copy. Both Debug and Release builds are locally ad-hoc signed; these commands do not notarize or publish the app.

## Pull requests

Explain the concrete problem, resulting behavior, relevant tradeoffs, and validation performed. Link applicable issues and update `CHANGELOG.md` for user-visible changes. Keep changes focused and preserve the Mozilla Public License notices and Rectangle MIT attribution under `ThirdParty/Rectangle/`. Update the bundled notices whenever upstream provenance changes.
