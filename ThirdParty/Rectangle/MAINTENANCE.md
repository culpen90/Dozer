# Following Rectangle releases

Dozer is maintained independently at `culpen90/Dozer`. Its menu bar code and
native workspace interface belong to this project. There is no automatic merge
or update feed from Mortennn/Dozer.

The user chose to keep Dozer's window interface and port Rectangle changes.
Do not replace the window interface with Rectangle.app. Follow official stable
releases from `rxhanson/Rectangle`, retaining its MIT license and attribution.

## Detection and porting are separate

GitHub's **Track Rectangle releases** workflow checks hourly, and can also be
started manually. It stages the complete, untouched upstream source tree in
`Upstream/`, pins the official tag and exact commit in `release.json`, and opens
a draft port PR. The snapshot includes tests, resources, and release notes so
changes outside the currently adapted files cannot silently disappear. Nothing
under `Upstream/` is compiled into Dozer or used as a build dependency.

The manifest distinguishes a pending source release from the last reviewed port.
Maintainers perform the coding work manually: review the entire upstream diff
and release notes, port fixes and new window behavior into Dozer-owned sources
and controls, add relevant regression coverage, then validate and merge the
completed port. GitHub handles release discovery only. Its hourly polling is
not an instantaneous upstream webhook.

If several releases arrive between runs, review their release notes in order
and account for every change since the last accepted port. Never overwrite a
partially completed port branch with another source-only snapshot. Use an
isolated worktree if the main checkout has other work in progress.

## Complete a port

```sh
make rectangle-check        # Read latest official release; no source changes
make rectangle-stage        # Stage a pending source snapshot, never acceptance
make rectangle-verify       # Verify snapshot and accepted review integrity
make test-rectangle-updates # Offline release tracking regression checks
make test
make test-window-adjustment
make release
```

Use `python3 Scripts/rectangle_release.py update --tag vX.Y.Z` to stage a specific
published stable release. Write `Ports/vX.Y.Z.json` using the existing report as
a schema example. Record every changed upstream path and release-note item with
its disposition and evidence, including newly added features. Then run:

```sh
python3 Scripts/rectangle_release.py accept --review ThirdParty/Rectangle/Ports/vX.Y.Z.json
make rectangle-verify
```

Only accept after the implementation and meaningful checks pass. A version-only
change, snapshot-only draft, or blanket dismissal of new window functionality is
insufficient. Mark a draft ready and merge only after required CI passes. Keep
failed or incomplete ports pending and report the concrete remaining work.

Record explicit reasons for changes that do not apply: Rectangle's own app
shell, automatic updater, product branding, settings layout, and documentation
are maintained differently here. Window fixes, calculations, new actions,
accessibility compatibility, snapping, shortcut behavior, and applicable new
preferences need actual review and porting into Dozer's interface.

## Scope and evidence

Dozer began as a scoped geometry port and still has differences from the full
Rectangle application. `Ports/` records the inspected release, implemented work,
checks, and remaining differences. A `reviewed` manifest means its recorded
scoped review passed; it does not certify complete Rectangle feature parity.
Do not advertise exact full-app parity while those differences exist.

The application remains independently built and signed by this project. CI
provides a universal build artifact; it does not install software onto users'
Macs or switch the old Dozer updater back on. Installed app updates use a
published Dozer download from GitHub Releases or the documented build/install
process. Dozer's combined app has its own release version, independent of the
upstream Rectangle version recorded in the manifest.
