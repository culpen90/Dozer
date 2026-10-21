#!/usr/bin/env python3
"""Keep bundled licenses and Rectangle provenance synchronized with their sources."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    parts = ["DOZER + RECTANGLE\n\nThis independent app ports Rectangle window tools into Dozer's native interface.\n"]
    for title, path in (("Rectangle and Spectacle", "ThirdParty/Rectangle/LICENSE"),
                        ("Source provenance", "ThirdParty/Rectangle/PROVENANCE.md"),
                        ("Dozer license", "LICENSE")):
        parts.append(title + "\n" + "=" * len(title) + "\n\n" + (ROOT / path).read_text().strip() + "\n")
    expected = "\n".join(parts)
    destination = ROOT / "Dozer/Resources/ThirdPartyNotices.txt"
    if args.check:
        if destination.read_text() != expected:
            raise SystemExit("Bundled notices are stale; run python3 Scripts/update_notices.py")
    else:
        destination.write_text(expected)


if __name__ == "__main__":
    main()
