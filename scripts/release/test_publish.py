"""Exercise real release sequencing against an in-memory GitHub API, without credentials."""
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from publish import release, select_version, state
from version import version_code

SHA = "a" * 40
TAG = "v1.2.3"
BASE = "repos/IlyasYOY/stack-attack"


class FakeGitHub:
    def __init__(self):
        self.tags = []
        self.releases = []
        self.assets = []
        self.fail_on_tag = False

    def api(self, path, *opts, payload=None):
        url = path.split("?")[0]
        if "--paginate" in opts:
            result = {BASE + "/tags": self.tags, BASE + "/releases": self.releases,
                      BASE + "/releases/1/assets": self.assets}[url]
            return "\n".join(json.dumps(item) for item in result)
        if url == BASE + "/releases":
            assert not self.releases
            self.releases.append(dict(payload, id=1, assets=self.assets))
            return json.dumps(self.releases[0])
        if url == "https://uploads.github.com/" + BASE + "/releases/1/assets":
            path = Path(opts[opts.index("--input") + 1])
            assert path.name not in [a["name"] for a in self.assets]
            self.assets.append(dict(name=path.name, state="uploaded",
                                    digest="sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()))
            return "{}"
        if url == BASE + "/git/refs":
            assert not self.tags
            if self.fail_on_tag:
                raise ConnectionError("API interrupted")
            self.tags.append(dict(name=payload["ref"].removeprefix("refs/tags/"), commit={"sha": payload["sha"]}))
            return "{}"
        if url == BASE + "/git/ref/tags/" + TAG:
            return json.dumps({"object": {"type": "commit", "sha": self.tags[0]["commit"]["sha"]}})
        if url == BASE + "/releases/1" and "PATCH" in opts:
            self.releases[0].update(payload, html_url="https://example.invalid/mock-release")
            return json.dumps(self.releases[0])
        raise AssertionError((url, opts))


class ReleaseTests(unittest.TestCase):
    def test_version_codes(self):
        for version, code in (("0.0.0", 1), ("0.999.999", 1000000),
                              ("1.0.0", 1000001), ("2099.999.999", 2100000000)):
            self.assertEqual(version_code(version), code)
        for version in ("01.0.0", "v1.2.3", "1.0.0-rc.1", "0.1000.0", "2100.0.0", "1.0.0\n"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                version_code(version)

    def test_auto_version(self):
        tags = [dict(name=name, commit={"sha": "b" * 40}) for name in
                ("v1.1.9", "v1.1.10", "v1.1.11-rc.1", "v02.0.0", "other")]
        self.assertEqual(select_version("", SHA, tags, []), ("1.1.11", "b" * 40))
        self.assertEqual(select_version("2.0.0", SHA, tags, [])[0], "2.0.0")
        with self.assertRaises(ValueError):
            select_version("", SHA, [], [])
        with self.assertRaises(ValueError):
            select_version("", SHA, [dict(name="v1.2.999", commit={"sha": "b" * 40})], [])

    def test_source_reservation(self):
        draft = dict(tag_name=TAG, target_commitish=SHA)
        for tags, releases in (([], [draft]), ([dict(name=TAG, commit={"sha": SHA})], [])):
            self.assertEqual(select_version("", SHA, tags, releases)[0], TAG[1:])
            with self.assertRaisesRegex(ValueError, "already has"):
                select_version("1.2.4", SHA, tags, releases)

    def test_conflicts(self):
        for tags, releases in (([{"name": TAG, "commit": {"sha": SHA}}], []),
                               ([{"name": "v2.0.0", "commit": {"sha": SHA}}], []),
                               ([], [{"tag_name": TAG, "target_commitish": SHA, "body": "foreign"}])):
            with self.subTest(tags=tags, releases=releases), self.assertRaises(ValueError):
                state("1.2.3", SHA, tags, releases)

    def test_resume_without_replacing_assets(self):
        github = FakeGitHub()
        with tempfile.TemporaryDirectory() as tmp, patch("publish.api", github.api), patch.dict(
            os.environ, GITHUB_REPOSITORY="IlyasYOY/stack-attack", APK_SIGNING_CERT_SHA256="f" * 64
        ):
            apk = Path(tmp, "stack-attack-v1.2.3.apk")
            apk.write_bytes(b"test APK")
            Path(tmp, "stack-attack-v1.2.3-web.zip").write_bytes(b"test web")
            github.fail_on_tag = True
            with self.assertRaises(ConnectionError):
                release("publish", "1.2.3", SHA, tmp)
            self.assertTrue(github.releases[0]["draft"])
            github.fail_on_tag = False
            apk.write_bytes(b"changed APK")
            with self.assertRaisesRegex(ValueError, "different build bytes"):
                release("publish", "1.2.3", SHA, tmp)
            apk.write_bytes(b"test APK")
            release("publish", "1.2.3", SHA, tmp)
            release("publish", "1.2.3", SHA, tmp)
            self.assertEqual(len(github.assets), 3)
            self.assertFalse(github.releases[0]["draft"])
            github.assets.pop()
            with self.assertRaisesRegex(ValueError, "assets differ"):
                release("publish", "1.2.3", SHA, tmp)


if __name__ == "__main__":
    unittest.main()
