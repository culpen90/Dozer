# Rectangle source attribution

The window geometry in `DozerCore/WindowLayout.swift` adapts calculations from
[Rectangle](https://github.com/rxhanson/Rectangle), an MIT-licensed application by
Ryan Hanson, based on Spectacle by Eric Czarny. Its license is included beside
this file and must be retained with distributed copies.

Upstream revision inspected: `e9bb8521e51727de21c31c3a96747909d42c098f`.
The upstream `DisplayTransfer.swift` and license were fetched directly at that
revision. The other calculations were inspected in the local Rectangle checkout
at `be974d9b500187aaa37ad7342f84df24d2027f96` (an Emacs-window-detection fix based on
upstream); the Dozer integration does not depend on that checkout at build time.

Adapted source files under `Rectangle/WindowCalculation/`:

- `DisplayTransfer.swift`: axis-by-axis display transfer, edge attachment, fitting,
  and the landscape/portrait three-edge exception. Removed the `Defaults` and
  `Edge` dependencies, accept the gap explicitly for the four-point-plus-gap edge tolerance, accept explicit display
  frames, validate finite positive geometry, and contain the final result.
- `GapCalculation.swift`: outer edges receive a full gap and shared tile edges a
  half gap. Replaced `Dimension`/`Edge` options with frame comparisons and clamp
  invalid or excessive gaps to keep a positive window frame.
- `WindowCalculation.swift`, `LeftRightHalfCalculation.swift`, `TopHalfCalculation.swift`,
  `BottomHalfCalculation.swift`, and quarter calculations: fractional screen
  layouts, consolidated into one stateless function with shared rounded boundaries
  so odd display dimensions do not leave a one-point seam.
- `FirstThirdCalculation.swift`, `CenterThirdCalculation.swift`,
  `LastThirdCalculation.swift`, `FirstTwoThirdsCalculation.swift`, and
  `LastTwoThirdsCalculation.swift`: horizontal thirds on landscape displays and
  vertical thirds on portrait displays. Removed history/cycling dependencies.
- `CenterCalculation.swift` and `AlmostMaximizeCalculation.swift`: fit and center
  windows; almost-maximize uses Rectangle's default 90 percent dimensions.
- `ChangeSizeCalculation.swift`: centered 30-point size steps. This integration
  uses explicit minimum dimensions and display containment rather than Rectangle's
  preference-driven edge-curtain and repeated-action behavior.

The action enumeration, display selection, simple snap-zone selection, validation,
preferences, AppKit interface, accessibility adapter, and shortcut integration are
Dozer integration code. This is a scoped integration of Rectangle geometry, not
all Rectangle features. It does not embed Rectangle's app delegate, updater,
MASShortcut dependency, settings, private window-ID bridge, or app bundle.
