# Changelog

## 6.0.0 — Dozer Workspace

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
