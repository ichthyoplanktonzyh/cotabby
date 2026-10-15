"""Exercise the local test-package contract without invoking macOS build tools."""

import contextlib
import fcntl
import io
import json
import os
from pathlib import Path
import plistlib
import select
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import package_test_dmg as packaging
import sign_local_app as local_sign


class TestDMGPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.app = self.root / "Lingrove.app"
        contents = self.app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "MacOS/Lingrove").write_bytes(b"test executable")
        info = {
            "CFBundleIdentifier": packaging.EXPECTED_BUNDLE_ID,
            "CFBundleShortVersionString": packaging.EXPECTED_VERSION,
            "CFBundleVersion": packaging.EXPECTED_BUILD,
            "CFBundleExecutable": "Lingrove",
            "LSMinimumSystemVersion": "14.0",
            "LingroveUpdatesEnabled": False,
            "SUAllowsAutomaticUpdates": False,
            "SUAutomaticallyUpdate": False,
            "SUEnableAutomaticChecks": False,
        }
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        self.output = self.root / "distributions"
        self.output.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def package_mocks(self, commands):
        def run(command, *, cwd=None):
            command = list(command)
            commands.append(command)
            if command[0] == "ditto":
                shutil.copytree(command[-2], command[-1], symlinks=True)
            elif command[:2] == ["hdiutil", "create"]:
                root = Path(command[command.index("-srcfolder") + 1])
                self.assertEqual(
                    {path.name for path in root.iterdir()},
                    {
                        "Lingrove.app",
                        "Applications",
                        "INSTALL.txt",
                        "LICENSE",
                        "THIRD_PARTY_LICENSES.md",
                        "SpellingDictionaries-NOTICE.md",
                        "LearningExpressions-NOTICE.md",
                        "ThirdPartyLicenses",
                    },
                )
                self.assertTrue((root / "Applications").is_symlink())
                self.assertEqual(os.readlink(root / "Applications"), "/Applications")
                self.assertTrue((root / "ThirdPartyLicenses/SOURCES.md").is_file())
                Path(command[-1]).write_bytes(b"mock compressed read-only DMG")

        def output(command, *, cwd=None):
            command = list(command)
            if command[:2] == ["lipo", "-archs"]:
                return "arm64 x86_64"
            if command[:2] == ["git", "rev-parse"]:
                return "a" * 40
            if command[:3] == ["git", "status", "--porcelain"]:
                return "" if "--" in command else " M scripts/package_test_dmg.py"
            raise AssertionError(f"Unexpected captured command: {command}")

        return run, output

    def test_help_exposes_build_and_package_only_paths(self):
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                packaging.parse_args(["--help"])
        self.assertEqual(caught.exception.code, 0)

    def test_packages_complete_signed_test_candidate_with_metadata_and_checksum(self):
        commands = []
        run, output = self.package_mocks(commands)
        with (
            mock.patch.object(packaging, "run_command", side_effect=run),
            mock.patch.object(packaging, "run_output", side_effect=output),
        ):
            dmg, checksum_file, info_file = packaging.package_app(
                repo_root=ROOT,
                app_path=self.app,
                output_dir=self.output,
                expected_architectures=("arm64", "x86_64"),
            )

        self.assertEqual(dmg.name, "Lingrove-0.5-test-universal.dmg")
        self.assertTrue(dmg.is_file())
        self.assertEqual(
            checksum_file.read_text(encoding="utf-8"),
            f"{packaging.sha256(dmg)}  {dmg.name}\n",
        )
        metadata = json.loads(info_file.read_text(encoding="utf-8"))
        self.assertEqual(metadata["bundleIdentifier"], packaging.EXPECTED_BUNDLE_ID)
        self.assertEqual(metadata["version"], "0.5")
        self.assertEqual(metadata["build"], "1")
        self.assertEqual(metadata["architectures"], ["arm64", "x86_64"])
        self.assertEqual(metadata["minimumMacOS"], "14.0")
        self.assertEqual(metadata["codeIdentity"], "ad-hoc")
        self.assertFalse(metadata["notarized"])
        self.assertEqual(metadata["sourceCommit"], "a" * 40)
        self.assertFalse(metadata["sourceDirty"])
        self.assertTrue(metadata["workingTreeDirty"])
        self.assertTrue(metadata["createdAtUTC"].endswith("Z"))

        signer = next(command for command in commands if command[0] == sys.executable)
        self.assertEqual(signer[-3:], ["--identity", "-", "--no-hardened-runtime"])
        hdiutil = next(command for command in commands if command[:2] == ["hdiutil", "create"])
        self.assertEqual(hdiutil[hdiutil.index("-format") + 1], "UDZO")
        self.assertNotIn("-ov", hdiutil)
        self.assertFalse(any(command[0] in {"open", "xattr"} for command in commands))
        self.assertFalse(any(command[:2] == ["hdiutil", "detach"] for command in commands))

    def test_rejects_wrong_product_before_running_packaging_commands(self):
        info_path = self.app / "Contents/Info.plist"
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        info["CFBundleIdentifier"] = "io.ichthyoplanktonzyh.lingrove.dev"
        with info_path.open("wb") as stream:
            plistlib.dump(info, stream)

        with mock.patch.object(packaging, "run_command") as run_command:
            with self.assertRaisesRegex(packaging.PackageError, "CFBundleIdentifier"):
                packaging.package_app(
                    repo_root=ROOT,
                    app_path=self.app,
                    output_dir=self.output,
                    expected_architectures=("arm64", "x86_64"),
                )
        run_command.assert_not_called()

    def test_refuses_sparkle_enabled_or_configured_app(self):
        info_path = self.app / "Contents/Info.plist"
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
        info["LingroveUpdatesEnabled"] = True
        info["SUFeedURL"] = "https://example.invalid/appcast.xml"
        with info_path.open("wb") as stream:
            plistlib.dump(info, stream)

        with mock.patch.object(packaging, "run_output") as run_output:
            with self.assertRaisesRegex(packaging.PackageError, "LingroveUpdatesEnabled=false"):
                packaging.validate_app(self.app, ("arm64", "x86_64"))
        run_output.assert_not_called()

    def test_rejects_gguf_and_private_key_material_inside_app(self):
        (self.app / "Contents/Resources").mkdir()
        (self.app / "Contents/Resources/model.gguf").write_bytes(b"model")
        with mock.patch.object(packaging, "run_output", return_value="arm64 x86_64"):
            with self.assertRaisesRegex(packaging.PackageError, "model.gguf"):
                packaging.validate_app(self.app, ("arm64", "x86_64"))

        (self.app / "Contents/Resources/model.gguf").unlink()
        (self.app / "Contents/Resources/developer.p8").write_bytes(b"private key")
        with mock.patch.object(packaging, "run_output", return_value="arm64 x86_64"):
            with self.assertRaisesRegex(packaging.PackageError, "developer.p8"):
                packaging.validate_app(self.app, ("arm64", "x86_64"))

    def test_never_overwrites_any_existing_package_output(self):
        existing = self.output / "Lingrove-0.5-test-universal.dmg"
        existing.write_bytes(b"previous package")
        run, output = self.package_mocks([])
        with (
            mock.patch.object(packaging, "run_command", side_effect=run),
            mock.patch.object(packaging, "run_output", side_effect=output),
        ):
            with self.assertRaisesRegex(packaging.PackageError, "Refusing to overwrite"):
                packaging.package_app(
                    repo_root=ROOT,
                    app_path=self.app,
                    output_dir=self.output,
                    expected_architectures=("arm64", "x86_64"),
                )
        self.assertEqual(existing.read_bytes(), b"previous package")

    def test_publish_rolls_back_partial_hard_links_on_collision(self):
        candidate = self.root / "candidate"
        candidate.mkdir()
        source_a = candidate / "a"
        source_b = candidate / "b"
        source_a.write_text("ready a")
        source_b.write_text("ready b")
        destination_a = self.output / "a"
        destination_b = self.output / "b"

        real_link = os.link

        def collide_after_first_link(source, destination):
            if Path(destination) == destination_b:
                destination_b.write_text("another run")
                raise FileExistsError(destination_b)
            real_link(source, destination)

        with mock.patch.object(packaging.os, "link", side_effect=collide_after_first_link):
            with self.assertRaisesRegex(packaging.PackageError, "Could not publish complete"):
                packaging.publish_candidate(
                    {source_a: destination_a, source_b: destination_b}
                )
        self.assertFalse(destination_a.exists())
        self.assertEqual(destination_b.read_text(), "another run")

    def test_default_pipeline_holds_lock_through_package_then_cleans_only_derived_data(self):
        build_dir = self.root / "build"
        build_dir.mkdir()
        unrelated = build_dir / "keep.txt"
        unrelated.write_text("preserve")
        workspace = self.root / "Cotabby.xcworkspace"
        workspace.mkdir()
        commands = []
        derived_data = (build_dir / "DerivedData").resolve()
        lock_path = build_dir / ".DerivedData.test-dmg.lock"
        package_outputs = (
            self.output / "Lingrove-0.5-test-universal.dmg",
            self.output / "SHA256SUMS.txt",
            self.output / "build-info.json",
        )
        cleanup_observed_locked = []
        real_cleanup = packaging.cleanup_owned_derived_data

        def run(command, *, cwd=None):
            command = list(command)
            commands.append(command)
            app = derived_data / "Build/Products/Release/Lingrove.app"
            app.mkdir(parents=True)
            (derived_data / "partial-build-product").write_text("built")

        def package(**kwargs):
            self.assertTrue(derived_data.is_dir())
            self.assertTrue((derived_data / "partial-build-product").is_file())
            lock_file = lock_path.open("a+")
            try:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            finally:
                lock_file.close()
            return package_outputs

        def cleanup(repo_root):
            lock_file = lock_path.open("a+")
            try:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            finally:
                lock_file.close()
            cleanup_observed_locked.append(True)
            real_cleanup(repo_root)

        with (
            mock.patch.object(packaging, "locate_prepared_workspace", return_value=workspace),
            mock.patch.object(packaging, "run_command", side_effect=run),
            mock.patch.object(packaging, "package_app", side_effect=package),
            mock.patch.object(packaging, "cleanup_owned_derived_data", side_effect=cleanup),
        ):
            result = packaging.build_and_package_release(
                repo_root=self.root,
                output_dir=self.output,
                expected_architectures=("arm64", "x86_64"),
            )

        self.assertEqual(result, package_outputs)
        command = commands[0]
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertEqual(command[command.index("-derivedDataPath") + 1], str(derived_data))
        self.assertIn("ARCHS=arm64 x86_64", command)
        self.assertIn("CODE_SIGN_IDENTITY=-", command)
        self.assertFalse(derived_data.exists())
        self.assertEqual(cleanup_observed_locked, [True])
        self.assertEqual(unrelated.read_text(), "preserve")

    def test_default_pipeline_cleans_derived_data_when_build_or_packaging_fails(self):
        for failing_stage in ("build", "package"):
            with self.subTest(stage=failing_stage):
                repo = self.root / failing_stage
                (repo / "build").mkdir(parents=True)
                workspace = repo / "Cotabby.xcworkspace"
                workspace.mkdir()
                derived_data = repo / "build/DerivedData"
                output = repo / "distributions"
                output.mkdir()

                def run(command, *, cwd=None):
                    app = derived_data / "Build/Products/Release/Lingrove.app"
                    app.mkdir(parents=True)
                    (derived_data / "partial-build-product").write_text("built")
                    if failing_stage == "build":
                        raise packaging.PackageError("mock build failure")

                def package(**kwargs):
                    raise packaging.PackageError("mock packaging failure")

                with (
                    mock.patch.object(packaging, "locate_prepared_workspace", return_value=workspace),
                    mock.patch.object(packaging, "run_command", side_effect=run),
                    mock.patch.object(packaging, "package_app", side_effect=package),
                ):
                    with self.assertRaisesRegex(packaging.PackageError, "mock .* failure"):
                        packaging.build_and_package_release(
                            repo_root=repo,
                            output_dir=output,
                            expected_architectures=("arm64", "x86_64"),
                        )
                self.assertFalse(derived_data.exists())

    def test_app_path_mode_never_touches_derived_data(self):
        fake_repo = self.root / "repo"
        (fake_repo / "scripts").mkdir(parents=True)
        derived_data = fake_repo / "build/DerivedData"
        derived_data.mkdir(parents=True)
        sentinel = derived_data / "another-build-product"
        sentinel.write_text("preserve")
        package_outputs = (
            self.output / "Lingrove-0.5-test-universal.dmg",
            self.output / "SHA256SUMS.txt",
            self.output / "build-info.json",
        )

        with (
            mock.patch.object(
                packaging, "__file__", str(fake_repo / "scripts/package_test_dmg.py")
            ),
            mock.patch.object(packaging, "package_app", return_value=package_outputs) as package,
        ):
            result = packaging.main(
                ["--app-path", str(self.app), "--output-dir", str(self.output)]
            )

        self.assertEqual(result, 0)
        package.assert_called_once()
        self.assertTrue(derived_data.is_dir())
        self.assertEqual(sentinel.read_text(), "preserve")

    def test_repo_build_lock_serializes_competing_invocations(self):
        build_dir = self.root / "build"
        derived_data = build_dir / "DerivedData"
        derived_data.mkdir(parents=True)
        sentinel = derived_data / "another-build-product"
        sentinel.write_text("preserve")
        lock_path = build_dir / ".DerivedData.test-dmg.lock"
        code = "\n".join(
            [
                "from pathlib import Path",
                "import sys, time",
                "from package_test_dmg import exclusive_build_lock",
                "with exclusive_build_lock(Path(sys.argv[1])):",
                "    print('acquired', flush=True)",
                "    time.sleep(0.35)",
            ]
        )
        env = {**os.environ, "PYTHONPATH": str(ROOT / "scripts")}
        first = subprocess.Popen(
            [sys.executable, "-c", code, str(lock_path)],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        second = None
        try:
            self.assertEqual(first.stdout.readline().strip(), "acquired")
            second = subprocess.Popen(
                [sys.executable, "-c", code, str(lock_path)],
                cwd=ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            readable, _, _ = select.select([second.stdout], [], [], 0.08)
            self.assertFalse(readable, "second build entered the critical section concurrently")
            _, first_err = first.communicate(timeout=5)
            self.assertEqual(first.returncode, 0, first_err)
            second_acquired = second.stdout.readline().strip()
            self.assertEqual(second_acquired, "acquired")
            _, second_err = second.communicate(timeout=5)
            self.assertEqual(second.returncode, 0, second_err)
        finally:
            for process in (first, second):
                if process and process.poll() is None:
                    process.kill()
                    process.communicate(timeout=5)
        self.assertEqual(sentinel.read_text(), "preserve")

    def test_adhoc_no_hardened_runtime_does_not_change_certificate_defaults(self):
        developer_sign = local_sign.codesign_arguments("Apple Development: Example")
        adhoc_sign = local_sign.codesign_arguments("-", no_hardened_runtime=True)
        self.assertEqual(developer_sign[:4], ["codesign", "--force", "--options", "runtime"])
        self.assertIn("--timestamp=none", developer_sign)
        self.assertIn("--sign", developer_sign)
        self.assertNotIn("--options", adhoc_sign)
        self.assertEqual(adhoc_sign[-2:], ["--sign", "-"])

    def test_no_hardened_runtime_is_restricted_to_plain_adhoc_signing(self):
        certificate = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/sign_local_app.py"),
                "unused.app",
                "--identity",
                "Apple Development: Example",
                "--no-hardened-runtime",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(certificate.returncode, 2)
        self.assertIn("only with ad-hoc identity '-'", certificate.stderr)

        testing = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/sign_local_app.py"),
                "unused.app",
                "--identity",
                "-",
                "--no-hardened-runtime",
                "--testing",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(testing.returncode, 2)
        self.assertIn("cannot be combined with debug or testing entitlements", testing.stderr)


if __name__ == "__main__":
    unittest.main()
