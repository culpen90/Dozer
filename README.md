<p align="center">
  <img width="160" height="160" src="Stuff/AppIcon.png" alt="Dozer app icon">
</p>

# Dozer

A calmer menu bar and windows right where you want them. Dozer combines [Mortennn/Dozer](https://github.com/Mortennn/Dozer) menu bar hiding with window layout geometry adapted from [Rectangle](https://github.com/rxhanson/Rectangle), in one native macOS app. No separate Rectangle installation, account, or third-party runtime dependencies are required.

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

These commands use **local ad-hoc signing** and need no paid Apple Developer account. Rebuilding changes the app’s signing identity. If Accessibility is enabled but Dozer still reports no access after an update, remove Dozer from that system list and add the installed `/Applications/Dozer.app` again. The resulting app is not notarized for distribution. The Xcode project is generated from `project.yml`; no Carthage, CocoaPods, SwiftGen, or old helper-app downloads are needed.

## Arrange your menu bar

1. Launch Dozer. A **chevron control** and **divider dot** appear in the menu bar.
2. Hold **Command (⌘)** and drag the divider dot to the right of the icons you want to hide. Keep the chevron to the right of the divider so it remains accessible.
3. Click the chevron or divider dot to hide or reveal the group to the divider’s left.
4. Right-click either control for the workspace, window layouts, and settings. Reopening Dozer from Finder also reveals its controls.

Fresh installs register **Control–Option–D (⌃⌥D)** to toggle the hidden group. Change or clear it in Settings. Existing shortcuts are retained when they can be registered; a conflicting shortcut produces an error and leaves the menu control available.

Settings include a keyboard shortcut, hiding at launch, auto-hide with a configurable delay, icon sizing, and launch at login. Launch at login is opt-in and uses the actual system login-item status. A keyboard shortcut must be registered before enabling the option to hide both controls.

Enable the optional second, smaller divider dot for an additional hidden group. Place it to the left of the main divider. Option-click the chevron or main divider to reveal this group; ordinary reveal keeps it hidden.

## Arrange your windows

Open **Dozer Workspace → Windows** and choose **Enable Accessibility…**, then enable Dozer in **System Settings → Privacy & Security → Accessibility**. Only window management needs this permission. Quit Rectangle and other window managers to avoid competing shortcuts or drag previews.

The workspace offers visual layout buttons for your last active app or an app selected in the target picker. The menu bar control’s right-click menu also contains every layout. Window tools include halves, quarters, thirds, two thirds, maximize, almost maximize, center, size adjustments, next/previous display, and a per-window restore history. On portrait displays, thirds run vertically. Display movement fits the destination’s visible area and respects menu bar/Dock space.

Default global shortcuts:

| Action | Shortcut |
| --- | --- |
| Left / right / top / bottom half | Control–Option–arrow |
| Top left / top right / bottom left / bottom right | Control–Option–U / I / J / K |
| First / center / last third | Control–Option–E / T / R |
| First / last two thirds | Control–Option–F / G |
| Maximize / almost maximize | Control–Option–Return / Shift–Return |
| Center | Control–Option–C |
| Larger / smaller | Control–Option–= / − |
| Next / previous display | Control–Option–Shift–Right / Left |
| Restore previous arrangement | Control–Option–Delete |

Customize or clear each shortcut in Windows settings. A conflict preserves the previous working binding and shows an error. Clearing a shortcut persists across launches. Pausing window management releases its global shortcuts and drag monitor; the menu bar reveal shortcut remains separate.

Drag a normal window to a screen edge for a half, a corner for a quarter, or the top edge to maximize. A translucent preview appears before release. Hold **Option** to bypass Dozer's snapping; macOS's own window tiling may still respond to the drag. Window spacing is configurable from zero to 30 points. Restore after a drag returns to the frame from before the drag.

This integrates Rectangle’s core layout calculations, with a native Dozer accessibility/shortcut/drag adapter; it does not include every Rectangle preference, repeated-action cycle, custom snap region, application exclusion, or Pro feature. Full-screen windows, system dialogs, and windows that disallow resizing are left to their owning apps. Apps may enforce minimum sizes. With only one display connected, display-transfer geometry is covered by automated tests; physical multi-display behavior needs hardware validation.

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
make test-runtime # Run live menu bar integration checks (quit Dozer first)
make test-window-shortcuts # Run real Carbon binding and recorder checks (quit Dozer first)
make test-window-adjustment # Check scoped accessibility-state restoration (no permission required)
make install   # Install Release with an existing-app backup
make run       # Build and launch Debug
```

Core state and window geometry tests use Swift Package Manager. The app uses the same source files from `DozerCore/` in its Xcode target.

Run `make test-window-shortcuts` with Dozer and other window managers quit to verify real Carbon registration, conflicts, persistence, corrupt preferences, and recorder cleanup. It uses isolated preferences and does not move windows or require Accessibility. For live window placement checks, `Scripts/RunWindowFixture.sh` opens a disposable window and records its frame to `build/window-fixture-frame.json`. Its `--large-minimum` option exercises applications that enforce a 1000 × 700 minimum window size.

For explicitly authorized native input checks, `Scripts/RunWindowInputCheck.sh --pid <fixture-pid> --action shortcut-left --allow-native-input` posts Control–Option–Left to the disposable fixture. The other actions are `drag-left` and `option-drag-left`. The helper validates the fixture's executable, visible window, and foreground ownership before posting; it refuses to run without the explicit flag or existing event-posting access. Compare the resulting frame log with the expected layout. Run these checks individually with no physical keyboard or mouse input, and close the fixture when finished.

Run `make test-runtime` from an active macOS desktop session with Dozer quit. The script builds the production sources into a native test executable, creates and removes its own fixture menu items, and verifies real hide/reveal, shortcut recovery, optional groups, and auto-hide behavior. It does not drag, reorder, or remove other applications’ items; its temporary divider can push neighboring items off-screen during a check and restores them afterward. Results and compact geometry diagnostics are saved in `build/runtime-checks.log`. The script refuses to run while Dozer is active to avoid competing global shortcuts.

Check Settings visually and exercise display changes, full-screen Spaces, and wake on the actual hardware when those paths change. The automated checks cover the current desktop configuration.

## License

[Mozilla Public License 2.0](LICENSE) for Dozer. Original Dozer by [Mortennn](https://github.com/Mortennn). Rectangle-derived geometry retains its [MIT license](ThirdParty/Rectangle/LICENSE), with [source revisions and adaptations](ThirdParty/Rectangle/PROVENANCE.md). The app bundles both licenses in About → Open Source Licenses.
