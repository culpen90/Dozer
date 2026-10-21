# Changelog

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
