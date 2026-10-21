"""Offline regression coverage for release staging and scoped-review gates."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest import mock

MODULE = Path(__file__).resolve().parents[2] / "Scripts/rectangle_release.py"
spec = importlib.util.spec_from_file_location("rectangle_release", MODULE)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.snapshot = self.root / "Upstream"
        self.snapshot.mkdir()
        (self.snapshot / "README.md").write_text("Original source\n")
        self.metadata = {"version": "2.0.4", "tag": "v2.0.4", "commit": "a" * 40,
                         "release_url": release.WEB + "/releases/tag/v2.0.4",
                         "source_url": "https://codeload.github.com/rxhanson/Rectangle/tar.gz/" + "a" * 40,
                         "release_notes": ["Fixed window placement"]}
        self.lock = {"schema_version": 1, "repository": "rxhanson/Rectangle", **self.metadata,
                     "archive_sha256": "b" * 64,
                     "snapshot_sha256": release.snapshot_digest(release.source_files(self.snapshot)),
                     "changed_paths": ["README.md"],
                     "integration": {"status": "pending", "parity": "scoped", "last_reviewed_commit": None}}
        self.report = {"upstream_commit": "a" * 40, "parity": "scoped",
                       "paths": [{"pattern": "README.md", "disposition": "Documentation retained as upstream reference."}],
                       "release_notes": [{"item": "Fixed window placement", "disposition": "Applicable placement changes ported and validated."}],
                       "validation": ["Swift geometry tests passed without window changes."],
                       "limitations": ["Only Dozer's supported window actions are integrated."]}

    def tearDown(self):
        self.directory.cleanup()

    def upstream_release(self):
        return {"draft": False, "prerelease": False, "tag_name": "v2.0.4",
                "html_url": release.WEB + "/releases/tag/v2.0.4", "body": "## Changes\n* Fixed window placement\n"}

    def write_archive(self, path, commit, entries):
        with tarfile.open(path, "w:gz") as archive:
            for name, contents, kind in entries:
                member = tarfile.TarInfo(f"Rectangle-{commit}/{name}")
                member.type = kind
                member.size = len(contents) if kind == tarfile.REGTYPE else 0
                member.linkname = "../../outside"
                archive.addfile(member, io.BytesIO(contents) if member.isfile() else None)

    def test_stable_release_uses_exact_commit_and_official_source(self):
        metadata = release.metadata_from_release(self.upstream_release(), "a" * 40)
        self.assertEqual(metadata, self.metadata)

    def test_prerelease_and_draft_are_rejected(self):
        for field in ("draft", "prerelease"):
            upstream = self.upstream_release()
            upstream[field] = True
            with self.assertRaises(release.ReleaseError):
                release.metadata_from_release(upstream, "a" * 40)

    def test_foreign_repository_and_malicious_tag_are_rejected(self):
        upstream = self.upstream_release()
        upstream["html_url"] = "https://github.com/other/Rectangle/releases/tag/v2.0.4"
        with self.assertRaises(release.ReleaseError):
            release.metadata_from_release(upstream, "a" * 40)
        upstream = self.upstream_release()
        upstream["tag_name"] = "v2.0.4/../../main"
        with self.assertRaises(release.ReleaseError):
            release.metadata_from_release(upstream, "a" * 40)

    def test_no_update_does_not_change_review_status(self):
        self.assertFalse(release.is_newer(self.lock, self.metadata))
        self.assertEqual(self.lock["integration"]["status"], "pending")

    def test_downgrade_and_moved_tag_are_rejected(self):
        candidate = {**self.metadata, "version": "2.0.3"}
        with self.assertRaises(release.ReleaseError):
            release.is_newer(self.lock, candidate)
        candidate = {**self.metadata, "commit": "c" * 40}
        with self.assertRaises(release.ReleaseError):
            release.is_newer(self.lock, candidate)

    def test_numeric_versions_do_not_sort_lexically(self):
        self.assertTrue(release.is_newer(self.lock, {**self.metadata, "version": "2.0.10"}))

    def test_missing_or_invalid_source_digests_are_rejected(self):
        for key in ("archive_sha256", "snapshot_sha256"):
            lock = copy.deepcopy(self.lock)
            del lock[key]
            with self.assertRaises(release.ReleaseError):
                release.validate_lock(lock)
            lock[key] = "not-a-digest"
            with self.assertRaises(release.ReleaseError):
                release.validate_lock(lock)

    def test_foreign_source_url_is_rejected(self):
        self.lock["source_url"] = "https://attacker.invalid/source.tar.gz"
        with self.assertRaises(release.ReleaseError):
            release.validate_lock(self.lock)

    def test_snapshot_integrity_detects_modified_added_and_removed_files(self):
        release.verify(self.lock, self.snapshot)
        source = self.snapshot / "README.md"
        source.write_text("Ported edit inside upstream snapshot")
        with self.assertRaises(release.ReleaseError):
            release.verify(self.lock, self.snapshot)
        source.write_text("Original source\n")
        extra = self.snapshot / "extra.swift"
        extra.write_text("Extra file")
        with self.assertRaises(release.ReleaseError):
            release.verify(self.lock, self.snapshot)
        extra.unlink()
        source.unlink()
        with self.assertRaises(release.ReleaseError):
            release.verify(self.lock, self.snapshot)

    def test_archive_cannot_escape_snapshot_or_extract_links(self):
        for name, kind in [("../../outside", tarfile.REGTYPE), ("/outside", tarfile.SYMTYPE),
                           ("symlink", tarfile.SYMTYPE), ("hardlink", tarfile.LNKTYPE),
                           ("device", tarfile.CHRTYPE)]:
            archive = self.root / "source.tar.gz"
            self.write_archive(archive, "a" * 40, [(name, b"malicious", kind)])
            with self.assertRaises(release.ReleaseError):
                release.extract_source(archive, self.root / "extracted", "a" * 40)
            self.assertFalse((self.root.parent / "outside").exists())

    def test_archive_must_match_exact_commit(self):
        archive = self.root / "source.tar.gz"
        self.write_archive(archive, "c" * 40, [("README.md", b"Wrong commit", tarfile.REGTYPE)])
        with self.assertRaises(release.ReleaseError):
            release.extract_source(archive, self.root / "extracted", "a" * 40)

    def test_source_is_copied_unchanged_and_not_executed(self):
        archive = self.root / "source.tar.gz"
        text = b"#!/bin/sh\necho never-execute-upstream\n"
        self.write_archive(archive, "a" * 40, [("script.sh", text, tarfile.REGTYPE)])
        destination = self.root / "extracted"
        with mock.patch.object(release.subprocess, "run", side_effect=AssertionError("must not execute upstream")):
            release.extract_source(archive, destination, "a" * 40)
        self.assertEqual((destination / "script.sh").read_bytes(), text)

    def test_update_stages_pending_and_preserves_previous_reviewed_commit(self):
        review = self.root / "review.json"
        release.write_json(review, self.report)
        self.lock["integration"] = {"status": "reviewed", "parity": "scoped", "last_reviewed_commit": "a" * 40,
                                    "review_path": "review.json", "review_sha256": release.digest_file(review)}
        candidate = {**self.metadata, "version": "2.0.5", "tag": "v2.0.5", "commit": "c" * 40,
                     "release_url": release.WEB + "/releases/tag/v2.0.5",
                     "source_url": "https://codeload.github.com/rxhanson/Rectangle/tar.gz/" + "c" * 40}
        def download(metadata, archive):
            self.write_archive(archive, metadata["commit"], [("README.md", b"New original source\n", tarfile.REGTYPE)])
        lock_path = self.root / "release.json"
        with mock.patch.object(release, "download_source", side_effect=download), mock.patch.object(release, "ROOT", self.root):
            result = release.stage(candidate, self.lock, self.snapshot, lock_path)
        self.assertEqual(result["integration"], {"status": "pending", "parity": "scoped", "last_reviewed_commit": "a" * 40})
        self.assertEqual(result["changed_paths"], ["README.md"])
        self.assertEqual(json.loads(lock_path.read_text()), result)
        release.verify(result, self.snapshot)

    def test_new_release_cannot_supersede_an_unfinished_port(self):
        candidate = {**self.metadata, "version": "2.0.5", "tag": "v2.0.5", "commit": "c" * 40}
        with mock.patch.object(release, "download_source") as download:
            with self.assertRaisesRegex(release.ReleaseError, "pending"):
                release.stage(candidate, self.lock, self.snapshot, self.root / "release.json")
        download.assert_not_called()
        self.assertEqual((self.snapshot / "README.md").read_text(), "Original source\n")

    def test_tag_validation_occurs_before_api_request(self):
        with mock.patch.object(release, "api_json") as api:
            self.assertEqual(release.main(["check", "--lock", str(self.root / "missing.json"), "--tag", "../../main"]), 1)
        api.assert_not_called()

    def test_selected_tag_cannot_switch_releases(self):
        with mock.patch.object(release, "api_json", return_value=self.upstream_release()):
            self.assertEqual(release.main(["update", "--lock", str(self.root / "missing.json"), "--tag", "v2.0.5"]), 1)

    def test_update_refuses_to_overwrite_local_source_edits(self):
        (self.snapshot / "README.md").write_text("Local edit")
        with mock.patch.object(release, "download_source") as download:
            with self.assertRaises(release.ReleaseError):
                release.stage(self.metadata, self.lock, self.snapshot, self.root / "release.json")
        download.assert_not_called()

    def test_accept_requires_exact_commit_and_scoped_parity(self):
        release.validate_review(self.report, self.lock)
        for key, value in [("upstream_commit", "c" * 40), ("parity", "complete")]:
            report = {**self.report, key: value}
            with self.assertRaises(release.ReleaseError):
                release.validate_review(report, self.lock)

    def test_accept_requires_disposition_for_every_path_and_note(self):
        self.lock["changed_paths"].append("Rectangle/WindowManager.swift")
        with self.assertRaises(release.ReleaseError):
            release.validate_review(self.report, self.lock)
        self.report["paths"].append({"pattern": "Rectangle/*", "disposition": "All applicable changes ported into the Dozer window adapter."})
        release.validate_review(self.report, self.lock)
        self.lock["release_notes"].append("Added new window action")
        with self.assertRaises(release.ReleaseError):
            release.validate_review(self.report, self.lock)

    def test_accept_requires_validation_and_explicit_limitations(self):
        for key, value in [("validation", []), ("limitations", None)]:
            with self.assertRaises(release.ReleaseError):
                release.validate_review({**self.report, key: value}, self.lock)

    def test_reviewed_report_integrity_is_checked_offline(self):
        review = self.root / "review.json"
        release.write_json(review, self.report)
        self.lock["integration"] = {"status": "reviewed", "parity": "scoped", "last_reviewed_commit": "a" * 40,
                                    "review_path": "review.json", "review_sha256": release.digest_file(review)}
        release.validate_lock(self.lock)
        release.verify(self.lock, self.snapshot, self.root)
        review.write_text("Changed review")
        with self.assertRaises(release.ReleaseError):
            release.verify(self.lock, self.snapshot, self.root)

    def test_annotated_tag_resolves_to_commit(self):
        with mock.patch.object(release, "api_json", side_effect=[{"object": {"sha": "b" * 40, "type": "tag"}},
                                                                 {"object": {"sha": "a" * 40, "type": "commit"}}]):
            self.assertEqual(release.resolve_commit("v2.0.4"), "a" * 40)


if __name__ == "__main__":
    unittest.main()
