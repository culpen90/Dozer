#!/usr/bin/env python3
"""Write a port-request description as text, without shell-interpolating notes."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    lock = json.loads(Path("ThirdParty/Rectangle/release.json").read_text())
    # The complete source and machine-readable diff inventory are in the manifest.
    body = """An official Rectangle release is ready to port into Dozer.

This draft contains the untouched upstream source snapshot and its pending
tracking record. Dozer's native window interface stays in place. No upstream
release is accepted automatically by the detector.

Before this becomes ready to merge:
- Review the manifest's changed paths and release notes against the previous accepted port.
- Port applicable fixes and new window behavior into Dozer's interface.
- Record dispositions, remaining differences, and validation in a versioned port report.
- Run the release-tool tests, Dozer tests, scoped Accessibility checks, and universal build.
- Accept the reviewed port with `Scripts/rectangle_release.py accept --review ...`.

See `ThirdParty/Rectangle/MAINTENANCE.md`. The recurring Codex maintenance job
can finish this port; this source-only draft must not be merged as an integrated update.
"""
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(body + "\nTracking record:\n```json\n" + json.dumps(
        {key: value for key, value in lock.items() if key not in ("files", "changed_paths", "release_notes")},
        indent=2,
    ) + "\n```\n")


if __name__ == "__main__":
    main()
