from __future__ import annotations

import importlib.util
import plistlib
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release", ROOT / "Scripts" / "release.py")
release = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = release
spec.loader.exec_module(release)


class AutomaticSyncIPAValidationTests(unittest.TestCase):
    secret = b"A" * 32

    def make_ipa(self, *, sync_resource: bytes | None) -> Path:
        temp = tempfile.NamedTemporaryFile(suffix=".ipa", delete=False)
        temp.close()
        ipa = Path(temp.name)
        info = plistlib.dumps({
            "CFBundleIdentifier": release.BUNDLE_ID,
            "CFBundleShortVersionString": "1.0.5",
            "CFBundleVersion": "6",
        })
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/PokeBinder.app/Info.plist", info)
            if sync_resource is not None:
                archive.writestr("Payload/PokeBinder.app/auto-sync-code.txt", sync_resource)
        self.addCleanup(ipa.unlink, missing_ok=True)
        return ipa

    def test_accepts_ipa_with_the_matching_automatic_sync_resource(self):
        ipa = self.make_ipa(sync_resource=self.secret + b"\n")
        release.verify_ipa(ipa, "1.0.5", "6", self.secret)

    def test_rejects_ipa_when_automatic_sync_resource_is_missing(self):
        ipa = self.make_ipa(sync_resource=None)
        with self.assertRaisesRegex(RuntimeError, "automatic sync"):
            release.verify_ipa(ipa, "1.0.5", "6", self.secret)

    def test_rejects_ipa_when_automatic_sync_resource_does_not_match(self):
        ipa = self.make_ipa(sync_resource=b"B" * 32)
        with self.assertRaisesRegex(RuntimeError, "automatic sync"):
            release.verify_ipa(ipa, "1.0.5", "6", self.secret)


if __name__ == "__main__":
    unittest.main()
