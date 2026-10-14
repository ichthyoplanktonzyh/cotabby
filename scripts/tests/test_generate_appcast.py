"""Check release destinations through the appcast CLI without keys, uploads, or real signing.

The signing-tool fixture returns archive metadata; these tests own URL/format behavior only.
Actual signature validation belongs to the release workflow and the signed upgrade exercise.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class AppcastDestinationTests(unittest.TestCase):
    def generate(self, *arguments):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            archive = directory / "Lingrove.dmg"
            archive.write_bytes(b"fixture archive")
            signer = directory / "sign_update"
            signer.write_text('#!/bin/sh\nprintf \'sparkle:edSignature="fixture" length="15"\\n\'\n')
            signer.chmod(0o755)
            output = directory / "appcast.xml"
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/generate_appcast.py"),
                 "--release-version", "1.0.1", "--build-number", "2",
                 "--archive", str(archive), "--output", str(output),
                 "--template", str(ROOT / "scripts/appcast.template.xml"),
                 "--sign-update-tool", str(signer), *arguments],
                check=True, capture_output=True, text=True,
            )
            return ET.fromstring(output.read_text())

    def test_default_feed_downloads_this_projects_build(self):
        document = self.generate()
        repository = "https://github.com/ichthyoplanktonzyh/cotabby"
        self.assertEqual(document.findtext("channel/title"), "Lingrove Updates")
        self.assertEqual(document.findtext("channel/link"), repository)
        item = document.find("channel/item")
        self.assertEqual(item.find("enclosure").get("url"),
                         repository + "/releases/download/v1.0.1/Lingrove.dmg")
        self.assertEqual(item.findtext("{" + SPARKLE + "}releaseNotesLink"),
                         repository + "/releases/tag/v1.0.1")
        self.assertEqual(item.findtext("{" + SPARKLE + "}version"), "2")

    def test_repository_and_notes_overrides_follow_a_future_rename(self):
        document = self.generate("--github-owner", "fixture-owner", "--github-repository", "lingrove",
                                 "--release-notes-base-url", "https://example.com/notes/")
        item = document.find("channel/item")
        self.assertEqual(item.find("enclosure").get("url"),
                         "https://github.com/fixture-owner/lingrove/releases/download/v1.0.1/Lingrove.dmg")
        self.assertEqual(item.findtext("{" + SPARKLE + "}releaseNotesLink"),
                         "https://example.com/notes/v1.0.1")
