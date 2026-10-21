#!/usr/bin/env python3
"""Track official Rectangle releases while keeping Dozer's integration independent.

check reports a newer stable release or a pending port. update stages the exact
upstream source tree and marks it pending; it never claims the changes are ported.
accept --review PATH records a scoped integration review with path/note coverage.
verify checks source and review integrity offline. No upstream code is executed.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "rxhanson/Rectangle"
API = f"https://api.github.com/repos/{REPOSITORY}"
WEB = f"https://github.com/{REPOSITORY}"
VERSION_PATTERN = r"[0-9]+\.[0-9]+\.[0-9]+"
SHA_PATTERN = r"[0-9a-f]{40}"
DIGEST_PATTERN = r"[0-9a-f]{64}"
MAX_ARCHIVE_SIZE = 100 * 1024 * 1024
MAX_EXPANDED_SIZE = 500 * 1024 * 1024
MAX_FILES = 10000


class ReleaseError(RuntimeError):
    """Release, source snapshot, or integration report could not be verified."""


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def version_tuple(value: str) -> tuple[int, ...]:
    if not isinstance(value, str) or not re.fullmatch(VERSION_PATTERN, value):
        raise ReleaseError(f"Unsupported Rectangle version: {value!r}")
    return tuple(map(int, value.split(".")))


def api_json(path: str) -> dict:
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Dozer-Rectangle-release-sync",
               "X-GitHub-Api-Version": "2022-11-28"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        request = urllib.request.Request(API + path, headers=headers)
        with urllib.request.urlopen(request, timeout=45) as response:
            value = json.load(response)
    except (urllib.error.URLError, ValueError) as error:
        raise ReleaseError(f"Cannot read Rectangle metadata: {error}") from error
    if not isinstance(value, dict):
        raise ReleaseError("Expected an object from the Rectangle API")
    return value


def resolve_commit(tag: str) -> str:
    reference = api_json(f"/git/ref/tags/{tag}").get("object", {})
    for _ in range(8):
        sha = reference.get("sha")
        if not isinstance(sha, str) or not re.fullmatch(SHA_PATTERN, sha):
            raise ReleaseError("Upstream tag did not resolve to a Git object")
        if reference.get("type") == "commit":
            return sha
        if reference.get("type") != "tag":
            break
        reference = api_json(f"/git/tags/{sha}").get("object", {})
    raise ReleaseError("Upstream tag did not resolve to a commit")


def metadata_from_release(release: dict, commit: str) -> dict:
    if release.get("draft") is not False or release.get("prerelease") is not False:
        raise ReleaseError("Only published stable Rectangle releases are accepted")
    tag = release.get("tag_name", "")
    if not isinstance(tag, str) or not re.fullmatch("v" + VERSION_PATTERN, tag):
        raise ReleaseError("Unsupported Rectangle release tag")
    if release.get("html_url") != f"{WEB}/releases/tag/{tag}":
        raise ReleaseError("Release URL does not identify the official Rectangle project")
    if not isinstance(commit, str) or not re.fullmatch(SHA_PATTERN, commit):
        raise ReleaseError("Rectangle commit must be a full SHA")
    body = release.get("body") or ""
    if not isinstance(body, str):
        raise ReleaseError("Release notes must be text")
    notes = [line.strip()[2:].strip() for line in body.splitlines()
             if line.strip().startswith(("* ", "- "))]
    return {"version": tag[1:], "tag": tag, "commit": commit,
            "release_url": release["html_url"],
            "source_url": f"https://codeload.github.com/{REPOSITORY}/tar.gz/{commit}",
            "release_notes": notes}


def validate_lock(lock: dict) -> None:
    try:
        if lock["schema_version"] != 1 or lock["repository"] != REPOSITORY:
            raise ReleaseError("Unsupported lock schema or Rectangle repository")
        expected = metadata_from_release({"draft": False, "prerelease": False,
                                         "tag_name": lock["tag"], "html_url": lock["release_url"]}, lock["commit"])
        if any(lock[key] != expected[key] for key in ("version", "source_url")):
            raise ReleaseError("Rectangle version/source URL does not match its commit")
        for key in ("archive_sha256", "snapshot_sha256"):
            if not isinstance(lock[key], str) or not re.fullmatch(DIGEST_PATTERN, lock[key]):
                raise ReleaseError(f"Rectangle {key} must be a SHA256 digest")
        if not isinstance(lock["changed_paths"], list) or not all(isinstance(p, str) and p for p in lock["changed_paths"]):
            raise ReleaseError("Invalid changed source paths")
        if not isinstance(lock["release_notes"], list) or not all(isinstance(p, str) and p for p in lock["release_notes"]):
            raise ReleaseError("Invalid release notes")
        integration = lock["integration"]
        if integration["parity"] != "scoped" or integration["status"] not in ("pending", "reviewed"):
            raise ReleaseError("Integration must retain its scoped parity and explicit review status")
        if integration.get("last_reviewed_commit") is not None and not re.fullmatch(SHA_PATTERN, integration["last_reviewed_commit"]):
            raise ReleaseError("Invalid last reviewed commit")
        if integration["status"] == "reviewed":
            if integration["last_reviewed_commit"] != lock["commit"]:
                raise ReleaseError("Integration review is for a different upstream commit")
            if not re.fullmatch(DIGEST_PATTERN, integration["review_sha256"]):
                raise ReleaseError("Integration review must have a SHA256 digest")
            review = PurePosixPath(integration["review_path"])
            if review.is_absolute() or ".." in review.parts or not review.parts:
                raise ReleaseError("Review path must be repository-relative")
    except (KeyError, TypeError, AttributeError) as error:
        raise ReleaseError(f"Invalid Rectangle lock: {error}") from error


def read_lock(path: Path) -> dict:
    try:
        lock = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise ReleaseError(f"Cannot read Rectangle lock {path}: {error}") from error
    validate_lock(lock)
    return lock


def is_newer(current: dict | None, candidate: dict) -> bool:
    if current is None:
        return True
    old, new = version_tuple(current["version"]), version_tuple(candidate["version"])
    if new < old:
        raise ReleaseError("Refusing to downgrade the pinned Rectangle release")
    if new == old and candidate["commit"] != current["commit"]:
        raise ReleaseError("Pinned release tag moved to another commit; review required")
    return new > old


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def source_files(snapshot: Path) -> dict[str, str]:
    result = {}
    if not snapshot.is_dir():
        raise ReleaseError(f"Missing Rectangle source snapshot: {snapshot}")
    for path in sorted(snapshot.rglob("*")):
        if path.is_symlink():
            raise ReleaseError(f"Unexpected source symlink: {path}")
        if path.is_file():
            result[path.relative_to(snapshot).as_posix()] = f"{int(bool(path.stat().st_mode & 0o111))}:{digest_file(path)}"
    if not result:
        raise ReleaseError("Rectangle source snapshot is empty")
    return result


def snapshot_digest(files: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def extract_source(archive_path: Path, destination: Path, commit: str) -> None:
    expected_root = f"Rectangle-{commit}"
    try:
        with tarfile.open(archive_path, "r:gz") as archive:
            members = archive.getmembers()
            if len(members) > MAX_FILES or sum(member.size for member in members) > MAX_EXPANDED_SIZE:
                raise ReleaseError("Rectangle source archive exceeds its size limit")
            seen = set()
            for member in members:
                parts = PurePosixPath(member.name).parts
                if not parts or parts[0] != expected_root or ".." in parts or "\\" in member.name:
                    raise ReleaseError(f"Unsafe Rectangle archive path: {member.name!r}")
                if not member.isfile() and not member.isdir():
                    raise ReleaseError(f"Rectangle archive contains a link or special file: {member.name!r}")
                relative = Path(*parts[1:])
                if len(parts) == 1:
                    if not member.isdir():
                        raise ReleaseError("Rectangle archive root must be a directory")
                    continue
                if relative in seen:
                    raise ReleaseError("Rectangle archive contains a duplicate path")
                seen.add(relative)
                target = destination / relative
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.extractfile(member) as source, target.open("wb") as output:
                        shutil.copyfileobj(source, output)
                    target.chmod(0o755 if member.mode & 0o111 else 0o644)
    except (tarfile.TarError, OSError) as error:
        raise ReleaseError(f"Cannot extract Rectangle sources: {error}") from error


def download_source(candidate: dict, archive: Path) -> None:
    request = urllib.request.Request(candidate["source_url"], headers={"User-Agent": "Dozer-Rectangle-release-sync"})
    try:
        with urllib.request.urlopen(request, timeout=90) as response, archive.open("wb") as output:
            total = 0
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_ARCHIVE_SIZE:
                    raise ReleaseError("Rectangle source archive exceeds its size limit")
                output.write(chunk)
    except urllib.error.URLError as error:
        raise ReleaseError(f"Cannot download exact Rectangle sources: {error}") from error


def validate_review(report: dict, lock: dict) -> None:
    if not isinstance(report, dict):
        raise ReleaseError("Integration review must be a JSON object")
    if report.get("upstream_commit") != lock["commit"] or report.get("parity") != "scoped":
        raise ReleaseError("Review must identify the exact upstream commit and scoped parity")
    paths = report.get("paths", [])
    if not paths or not all(isinstance(entry, dict) and isinstance(entry.get("pattern"), str)
                            and isinstance(entry.get("disposition"), str) and len(entry["disposition"].strip()) >= 12 for entry in paths):
        raise ReleaseError("Review needs meaningful source-path dispositions")
    uncovered = [path for path in lock["changed_paths"]
                 if not any(fnmatch.fnmatchcase(path, entry["pattern"]) for entry in paths)]
    if uncovered:
        raise ReleaseError(f"Review does not cover changed paths: {', '.join(uncovered[:8])}")
    notes = report.get("release_notes", [])
    if not isinstance(notes, list):
        raise ReleaseError("Review needs release-note dispositions")
    covered_notes = {entry.get("item") for entry in notes if isinstance(entry, dict)
                     and isinstance(entry.get("item"), str)
                     and isinstance(entry.get("disposition"), str) and len(entry["disposition"].strip()) >= 12}
    if any(note not in covered_notes for note in lock["release_notes"]):
        raise ReleaseError("Review does not cover every upstream release note")
    validation = report.get("validation")
    if not isinstance(validation, list) or not validation or not all(isinstance(item, str) and len(item.strip()) >= 12 for item in validation):
        raise ReleaseError("Review needs recorded validation results")
    if not isinstance(report.get("limitations"), list) or not all(isinstance(item, str) for item in report["limitations"]):
        raise ReleaseError("Review must explicitly record integration limitations")


def verify(lock: dict, snapshot: Path, root: Path | None = None) -> dict[str, str]:
    root = root or ROOT
    files = source_files(snapshot)
    if snapshot_digest(files) != lock["snapshot_sha256"]:
        raise ReleaseError("Rectangle source snapshot changed; restore it before updating or accepting a review")
    integration = lock["integration"]
    if integration["status"] == "reviewed":
        review = root / integration["review_path"]
        if not review.is_file() or digest_file(review) != integration["review_sha256"]:
            raise ReleaseError("Stored integration review is missing or changed")
        try:
            validate_review(json.loads(review.read_text()), lock)
        except (ValueError, TypeError, AttributeError) as error:
            raise ReleaseError(f"Invalid integration review: {error}") from error
    return files


def stage(candidate: dict, current: dict | None, snapshot: Path, lock_path: Path) -> dict:
    if current and current["integration"]["status"] == "pending" and is_newer(current, candidate):
        raise ReleaseError("Finish the pending Rectangle integration review before staging another release")
    old_files = verify(current, snapshot) if current else {}
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    if current is None and snapshot.exists():
        raise ReleaseError("Refusing to overwrite an untracked Rectangle source snapshot")
    with tempfile.TemporaryDirectory(prefix=".rectangle-source-", dir=snapshot.parent) as temporary:
        temporary = Path(temporary)
        archive = temporary / "source.tar.gz"
        download_source(candidate, archive)
        staged_snapshot = temporary / "Upstream"
        staged_snapshot.mkdir()
        extract_source(archive, staged_snapshot, candidate["commit"])
        new_files = source_files(staged_snapshot)
        changed_paths = sorted(path for path in old_files.keys() | new_files.keys() if old_files.get(path) != new_files.get(path))
        lock = {"schema_version": 1, "repository": REPOSITORY, **candidate,
                "archive_sha256": digest_file(archive), "snapshot_sha256": snapshot_digest(new_files),
                "changed_paths": changed_paths,
                "integration": {"status": "pending", "parity": "scoped",
                                "last_reviewed_commit": current["integration"].get("last_reviewed_commit") if current else None}}
        validate_lock(lock)
        backup = temporary / "previous"
        if snapshot.exists():
            snapshot.rename(backup)
        try:
            staged_snapshot.rename(snapshot)
            write_json(lock_path, lock)
        except BaseException:
            if snapshot.exists():
                shutil.rmtree(snapshot)
            if backup.exists():
                backup.rename(snapshot)
            raise
        return lock


def report_result(lock: dict, changed: bool, args: argparse.Namespace) -> None:
    pending = lock["integration"]["status"] == "pending" if "integration" in lock else True
    result = {"changed": changed, "version": lock["version"], "tag": lock["tag"], "pending": pending,
              "commit": lock["commit"]}
    if args.github_output:
        with args.github_output.open("a") as handle:
            for key, value in result.items():
                handle.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")
    if args.summary:
        args.summary.parent.mkdir(parents=True, exist_ok=True)
        args.summary.write_text(f"Track the official [Rectangle {lock['version']} release]({lock['release_url']}) "
                                "while maintaining Dozer's own window interface and independent menu bar code.\n\n"
                                f"Upstream commit: `{lock['commit']}`\n\n"
                                "The full source snapshot is unchanged upstream code. Its presence is **not** an integration: "
                                "port applicable changes into Dozer, account for every changed source path and release note, "
                                "run validation, then accept the scoped review. New upstream features remain explicit "
                                "limitations until implemented. No original Dozer updates are imported.\n")
    print(json.dumps(result))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "update", "accept", "verify"))
    parser.add_argument("--lock", type=Path, default=ROOT / "ThirdParty/Rectangle/release.json")
    parser.add_argument("--snapshot", type=Path, default=ROOT / "ThirdParty/Rectangle/Upstream")
    parser.add_argument("--tag", help="stage this published stable tag instead of selecting latest (check/update only)")
    parser.add_argument("--review", type=Path, help="JSON review with exact commit, paths, notes, validation and limitations")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--summary", type=Path, help="write update pull request body")
    args = parser.parse_args(argv)
    try:
        if args.tag and args.command not in ("check", "update"):
            raise ReleaseError("--tag is only valid with check or update")
        current = read_lock(args.lock) if args.lock.exists() else None
        if args.command in ("check", "update"):
            if args.tag and not re.fullmatch("v" + VERSION_PATTERN, args.tag):
                raise ReleaseError("Unsupported Rectangle release tag")
            release = api_json(f"/releases/tags/{args.tag}" if args.tag else "/releases/latest")
            if args.tag and release.get("tag_name") != args.tag:
                raise ReleaseError("GitHub returned a different release than requested")
            candidate = metadata_from_release(release, "0" * 40)
            candidate["commit"] = resolve_commit(candidate["tag"])
            candidate["source_url"] = f"https://codeload.github.com/{REPOSITORY}/tar.gz/{candidate['commit']}"
            changed = is_newer(current, candidate)
            if changed and args.command == "update":
                current = stage(candidate, current, args.snapshot, args.lock)
            elif current and args.command == "update":
                verify(current, args.snapshot)
            result = current if current and not changed else candidate
            if args.command == "update":
                result = current
            report_result(result, changed, args)
        else:
            if current is None:
                raise ReleaseError("No Rectangle release has been staged")
            verify(current, args.snapshot)
            if args.command == "accept":
                if args.review is None:
                    raise ReleaseError("accept requires --review PATH")
                review = args.review.resolve()
                try:
                    relative = review.relative_to(ROOT).as_posix()
                except ValueError as error:
                    raise ReleaseError("Integration review must be stored in this repository") from error
                validate_review(json.loads(review.read_text()), current)
                current["integration"] = {"status": "reviewed", "parity": "scoped", "last_reviewed_commit": current["commit"],
                                          "review_path": relative, "review_sha256": digest_file(review)}
                write_json(args.lock, current)
            report_result(current, False, args)
        return 0
    except (ReleaseError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Rectangle release error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
