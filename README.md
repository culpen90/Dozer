<p align="center">
  <img width="160" height="160" src="Stuff/AppIcon.png" alt="Dozer app icon">
</p>

# Dozer

Hide menu bar icons until you need them. This revival of [Mortennn/Dozer](https://github.com/Mortennn/Dozer) uses native AppKit, a system keyboard shortcut, and macOS login items, with no third-party runtime dependencies.

Requires **macOS 13 or later**. Release builds contain native **Apple Silicon and Intel** executables.

## Build and install

Install Xcode, select it with `xcode-select`, accept its license, and install [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
make test
make install
open /Applications/Dozer.app
```

`make build` creates a Debug app under `build/Build/Products/Debug/`. `make release` creates a universal Release app under `build/Build/Products/Release/`. `make install` builds Release and installs `/Applications/Dozer.app`; quit a running copy first. An existing installed app is backed up under `~/Library/Application Support/Dozer/Backups/` before replacement. Preferences stay in the original `com.mortennn.Dozer` domain.

These commands use **local ad-hoc signing** and need no paid Apple Developer account. The resulting app is not notarized for distribution. The Xcode project is generated from `project.yml`; no Carthage, CocoaPods, SwiftGen, or old helper-app downloads are needed.

## Arrange your menu bar

1. Launch Dozer. A **chevron control** and **divider dot** appear in the menu bar.
2. Hold **Command (⌘)** and drag the divider dot to the right of the icons you want to hide. Keep the chevron to the right of the divider so it remains accessible.
3. Click the chevron or divider dot to hide or reveal the group to the divider’s left.
4. Right-click either control to open Settings. Reopening Dozer from Finder also reveals its controls.

Fresh installs register **Control–Option–D (⌃⌥D)** to toggle the hidden group. Change or clear it in Settings. Existing shortcuts are retained when they can be registered; a conflicting shortcut produces an error and leaves the menu control available.

Settings include a keyboard shortcut, hiding at launch, auto-hide with a configurable delay, icon sizing, and launch at login. Launch at login is opt-in and uses the actual system login-item status. A keyboard shortcut must be registered before enabling the option to hide both controls.

Enable the optional second, smaller divider dot for an additional hidden group. Place it to the left of the main divider. Option-click the chevron or main divider to reveal this group; ordinary reveal keeps it hidden.

## How hiding works

Dozer expands a divider status item to move the icons on its left out of the visible menu bar. It does not modify other apps or terminate their menu bar items. It requires no screen-recording or Accessibility permission for normal hiding and keyboard shortcuts.

macOS controls menu bar layout. A display notch, a long application menu, a crowded menu bar, or multiple displays can limit the icons that fit when revealed. Move fewer icons into a group or enable the setting that temporarily shows Dozer's shorter application menu to free space. Some system items cannot be moved. Dozer does not provide a separate overflow panel for icons that do not fit.

The upstream Sparkle updater has been removed so this revived app cannot silently replace itself with the old upstream build. Build updates from this repository.

## Development

```sh
make project   # Regenerate Dozer.xcodeproj
make build     # Build and locally sign Debug
make release   # Build and locally sign universal Release
make test      # Run Foundation-only state tests, without launching the GUI
make test-runtime # Run live menu bar and shortcut integration checks (quit Dozer first)
make install   # Install Release with an existing-app backup
make run       # Build and launch Debug
```

Core state tests use Swift Package Manager. The app uses the same source files from `DozerCore/` in its Xcode target.

Run `make test-runtime` from an active macOS desktop session with Dozer quit. The script builds the production sources into a native test executable, creates and removes its own fixture menu items, and verifies real hide/reveal, shortcut recovery, optional groups, and auto-hide behavior. It does not drag, reorder, or remove other applications’ items; its temporary divider can push neighboring items off-screen during a check and restores them afterward. Results and compact geometry diagnostics are saved in `build/runtime-checks.log`. The script refuses to run while Dozer is active to avoid competing global shortcuts.

Check Settings visually and exercise display changes, full-screen Spaces, and wake on the actual hardware when those paths change. The automated checks cover the current desktop configuration.

## License

[Mozilla Public License 2.0](LICENSE). Original Dozer by [Mortennn](https://github.com/Mortennn).
