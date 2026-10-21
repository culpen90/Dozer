# Changelog

## 1.0.0 — First independent combined release

This is the first public release of this combined Dozer app, with its own version line independent of Dozer and Rectangle upstream. Earlier 5.x and 6.x numbers below identify local development milestones. The internal build number continues at 34, and the existing preference domain is retained.

- Combine Dozer menu bar hiding and Rectangle-derived window tools in one native workspace.
- Include configurable window shortcuts, edge/corner snapping, per-window restore history, display transfer, window spacing, and sixth layouts.
- Offer optional opposite-side repeated half commands and recognize Emacs standard-window subroles during drag snapping.
- Use minimum-size-aware placement and avoid redundant Accessibility writes while preserving recovery.
- Preserve menu bar preferences, optional hidden groups, auto-hide, and opt-in launch at login.
- Publish a universal Apple Silicon and Intel app for macOS 13 or later, with SHA256 checksums and bundled MPL/MIT notices.
- Track official Rectangle releases as pending source snapshots for manual review and ports into Dozer's own interface.

Release builds are ad-hoc signed and not notarized. Rectangle integration remains scoped; the recorded feature differences are in `ThirdParty/Rectangle/Ports/`.

## Local milestone 6.1.0 — Independent Rectangle release ports

- Keep Dozer's window interface and independently maintained menu bar features.
- Track official Rectangle releases hourly, stage full source snapshots as draft ports, and require recorded review and validation before acceptance.
- Port Rectangle 2.0.4 vertical sixth layouts and optional opposite-side repeated half commands.
- Recognize Emacs standard-window subroles during drag snapping.
- Use minimum-size-aware window placement and avoid redundant Accessibility writes while preserving asynchronous recovery.
- Add CI for source integrity, port tooling, native core regressions, and universal builds.

## Local milestone 6.0.0 — Dozer Workspace

- Unified native workspace, Menu Bar, Windows, and About pages, with an explicit target-app picker for layout buttons.
- Rectangle-derived geometry for 21 window actions, with configurable spacing and display transfer.
- Configurable global shortcuts, conflict preservation, persistent clears, and safe recorder cleanup.
- Optional edge/corner drag snapping with a translucent preview and Option bypass.
- Per-window restore history, including the original frame before a snap drag, with independently queued window adjustments.
- Bounded placement for application minimum sizes, Rectangle-derived accessibility animation handling, and staged placement recovery.
- Existing menu bar hiding, recovery controls, login items, and preferences retained.
- Bundled MPL/MIT notices and pinned Rectangle source provenance.

## Version 5.0.0 (local revival)

* Native Apple Silicon and Intel builds for macOS 13 and later.
* Replace obsolete third-party frameworks with native settings, keyboard shortcuts, and system login items.
* Stabilize status item identity and layout, optional groups, shortcut recovery, and auto-hide behavior.
* Preserve existing preference keys and remove the upstream automatic-update feed.
* Add reproducible builds, local signing, installation backups, and focused state tests.

## Version 4.2.0
New features:
* Configure amount of seconds to hide the icons after #104. @blakedgordon
* Resize icons and padding capability added #101. @blakedgordon

Fixed:
* Fix both dozer icons from being hidden #105. @blakedgordon

Thank you @blakedgordon for the contributions🙌

## Version 4.1.0
New features:
* Hide status bar icons at launch #78. @aonez

Fixed:
* Reduce CPU usage when "Hide status bar icons after 10 seconds" is checked #78. @aonez

Thank you @aonez for the contributions🙌

## Version 4
New features:
* ”Remove”-icon. Additional icon to hide/show icons with `option+click`
* Auto-hide status bar icons #22
* ”No Icon”-mode. Hide/show only using keyboard shortcut

Other:
* Improved UI in preferences
