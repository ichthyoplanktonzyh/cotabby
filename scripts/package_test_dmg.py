#!/usr/bin/env python3
"""Build a local Lingrove 0.5 test DMG, or package an existing Release app.

The shell entry point stays small; this module owns the installer contents and
publication rules. It only stages the finished app and explicit legal/install
files, so local models, preferences, signing overrides, and other checkout
data never enter the disk image.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from typing import Iterator, Sequence


PRODUCT_NAME = "Lingrove"
EXPECTED_BUNDLE_ID = "io.ichthyoplanktonzyh.lingrove"
EXPECTED_VERSION = "0.5"
EXPECTED_BUILD = "1"
REQUIRED_ARCHITECTURES = ("arm64", "x86_64")
SIGNING_HELPER = Path(__file__).with_name("sign_local_app.py")
INSTALL_GUIDE = Path(__file__).resolve().parents[1] / "assets" / "testing" / "INSTALL.zh-CN.txt"
REQUIRED_LEGAL_FILES = (
    Path("LICENSE"),
    Path("THIRD_PARTY_LICENSES.md"),
    Path("Cotabby/Resources/ThirdPartyLicenses"),
    Path("Cotabby/Resources/SpellingDictionaries/NOTICE.md"),
    Path("Cotabby/Resources/learning-expressions.NOTICE.md"),
)
APP_BUILD_INPUT_PATHS = (
    "Cotabby/",
    "Cotabby.xcodeproj/",
    "CotabbyInfo.plist",
    "Config/Package.resolved",
    "Config/Signing.xcconfig",
    "patches/",
    "project.yml",
    "scripts/create-inference-workspace.py",
    "scripts/prepare_cotabby_workspace.sh",
)
FORBIDDEN_SUFFIXES = {".gguf", ".p8", ".p12", ".key"}
FORBIDDEN_NAMES = {".env", "Signing.local.xcconfig"}


class PackageError(RuntimeError):
    """An actionable packaging error that can be shown without a traceback."""


def parse_architectures(values: Sequence[str]) -> tuple[str, ...]:
    """Normalize and validate the exact app slices the caller expects."""

    if len(set(values)) != len(values):
        raise PackageError("Architecture list contains a duplicate slice")
    if not values:
        raise PackageError("At least one architecture is required")
    unsupported = set(values) - set(REQUIRED_ARCHITECTURES)
    if unsupported:
        raise PackageError(f"Unsupported architecture(s): {', '.join(sorted(unsupported))}")
    return tuple(arch for arch in REQUIRED_ARCHITECTURES if arch in values)


def run_command(command: Sequence[str], *, cwd: Path | None = None) -> None:
    """Run a system tool with its output attached to the caller's terminal."""

    result = subprocess.run(list(command), cwd=cwd, check=False)
    if result.returncode != 0:
        raise PackageError(
            f"Command failed with exit code {result.returncode}: {' '.join(map(str, command))}"
        )


def run_output(command: Sequence[str], *, cwd: Path | None = None) -> str:
    """Capture small machine-readable output such as plist-independent lipo data."""

    result = subprocess.run(
        list(command), cwd=cwd, check=False, capture_output=True, text=True
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        suffix = f": {detail}" if detail else ""
        raise PackageError(
            f"Command failed with exit code {result.returncode}: {' '.join(map(str, command))}{suffix}"
        )
    return result.stdout.strip()


@contextmanager
def exclusive_build_lock(lock_path: Path) -> Iterator[None]:
    """Serialize this script's full build/package lifecycle.

    `flock` releases the lock automatically if the process exits, including on
    interruption. The small lock file lives beside DerivedData and is never a
    cleanup target. Holding the lock until DerivedData cleanup prevents a
    second invocation from deleting products that the first is still using.
    """

    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if lock_path.is_symlink():
        raise PackageError(f"Refusing to use a symlink as the build lock: {lock_path}")
    with lock_path.open("a+") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build the Lingrove 0.5 test DMG. Without --app-path, prepares the pinned workspace "
            "and builds Release into build/DerivedData."
        )
    )
    parser.add_argument(
        "--app-path",
        type=Path,
        help="Package an existing Release Lingrove.app without building or changing DerivedData.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Output directory (default: build/distributions). Existing outputs are never replaced.",
    )
    parser.add_argument(
        "--architectures",
        nargs="+",
        choices=REQUIRED_ARCHITECTURES,
        default=list(REQUIRED_ARCHITECTURES),
        metavar="ARCH",
        help="Exact app slices to build/require (default: arm64 x86_64).",
    )
    return parser.parse_args(argv)


def locate_prepared_workspace(repo_root: Path) -> Path:
    workspace = repo_root / "build/cotabby-dependencies/Cotabby.xcworkspace"
    if not workspace.exists():
        run_command([str(repo_root / "scripts/prepare_cotabby_workspace.sh")], cwd=repo_root)
    if not workspace.exists():
        raise PackageError(f"Prepared workspace was not created at {workspace}")
    return workspace


def build_release_app(repo_root: Path, architectures: tuple[str, ...]) -> Path:
    """Build production identity into repo-scoped DerivedData.

    The caller must hold the exclusive build lock through packaging and cleanup;
    keeping this function focused on the Xcode call makes that lifecycle
    explicit at the higher-level build-and-package boundary.
    """

    derived_data = repo_root / "build/DerivedData"
    app_path = derived_data / "Build/Products/Release/Lingrove.app"
    if derived_data.is_symlink():
        raise PackageError(f"Refusing to build into symlinked DerivedData: {derived_data}")
    derived_data.mkdir(parents=True, exist_ok=True)
    workspace = locate_prepared_workspace(repo_root)
    command = [
        "xcodebuild",
        "-workspace",
        str(workspace),
        "-scheme",
        "Cotabby",
        "-configuration",
        "Release",
        "-destination",
        "platform=macOS",
        "-derivedDataPath",
        str(derived_data),
        f"ARCHS={' '.join(architectures)}",
        "ONLY_ACTIVE_ARCH=NO",
        "CODE_SIGN_IDENTITY=-",
        "CODE_SIGN_STYLE=Manual",
        "DEVELOPMENT_TEAM=",
        "CODE_SIGNING_ALLOWED=YES",
        "CODE_SIGNING_REQUIRED=YES",
        "ENABLE_HARDENED_RUNTIME=NO",
        "build",
    ]
    run_command(command, cwd=repo_root)
    if not app_path.is_dir():
        raise PackageError(f"Xcode build completed without producing {app_path}")
    return app_path


def cleanup_owned_derived_data(repo_root: Path) -> None:
    """Remove only this repo's exact DerivedData directory, never a symlink."""

    repo_root = repo_root.resolve()
    build_root = repo_root / "build"
    derived_data = build_root / "DerivedData"
    if build_root.is_symlink() or derived_data.is_symlink():
        raise PackageError("Refusing to clean DerivedData through a symlink")
    if derived_data.exists():
        if not derived_data.is_dir():
            raise PackageError(f"Refusing to clean a non-directory DerivedData path: {derived_data}")
        shutil.rmtree(derived_data)


def build_and_package_release(
    *,
    repo_root: Path,
    output_dir: Path,
    expected_architectures: tuple[str, ...],
) -> tuple[Path, Path, Path]:
    """Hold the repo build lock until the artifact is published and DerivedData is removed."""

    repo_root = repo_root.resolve()
    derived_data = repo_root / "build/DerivedData"
    if (repo_root / "build").is_symlink() or derived_data.is_symlink():
        raise PackageError("Refusing to build through a symlinked build/DerivedData path")
    resolved_output_dir = output_dir.expanduser().resolve()
    try:
        resolved_output_dir.relative_to(derived_data)
    except ValueError:
        pass
    else:
        raise PackageError(
            f"Output directory cannot be inside DerivedData, which this build cleans: {derived_data}"
        )

    lock_path = repo_root / "build/.DerivedData.test-dmg.lock"
    with exclusive_build_lock(lock_path):
        try:
            app_path = build_release_app(repo_root, expected_architectures)
            return package_app(
                repo_root=repo_root,
                app_path=app_path,
                output_dir=resolved_output_dir,
                expected_architectures=expected_architectures,
            )
        finally:
            cleanup_owned_derived_data(repo_root)


def read_app_info(app_path: Path) -> tuple[dict[str, object], Path]:
    info_path = app_path / "Contents/Info.plist"
    if app_path.name != "Lingrove.app" or not info_path.is_file():
        raise PackageError(
            f"Expected the production Lingrove.app bundle containing Contents/Info.plist: {app_path}"
        )
    try:
        with info_path.open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise PackageError(f"Could not read app metadata at {info_path}: {error}") from error
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name:
        raise PackageError(f"App bundle has no CFBundleExecutable: {info_path}")
    executable_path = app_path / "Contents/MacOS" / executable_name
    if not executable_path.is_file():
        raise PackageError(f"App executable is missing: {executable_path}")
    return info, executable_path


def validate_app(app_path: Path, expected_architectures: tuple[str, ...]) -> dict[str, object]:
    """Reject dev, stale, Sparkle-enabled, model-bearing, or mislabeled app bundles."""

    app_path = app_path.expanduser().resolve()
    info, executable = read_app_info(app_path)
    expected_values = {
        "CFBundleIdentifier": EXPECTED_BUNDLE_ID,
        "CFBundleShortVersionString": EXPECTED_VERSION,
        "CFBundleVersion": EXPECTED_BUILD,
    }
    for key, expected in expected_values.items():
        actual = info.get(key)
        if actual != expected:
            raise PackageError(f"{key} must be {expected!r}; found {actual!r} in {app_path}")

    if info.get("LingroveUpdatesEnabled") is not False:
        raise PackageError("Test package requires LingroveUpdatesEnabled=false in the app Info.plist")
    for key in (
        "SUAllowsAutomaticUpdates",
        "SUAutomaticallyUpdate",
        "SUEnableAutomaticChecks",
    ):
        if info.get(key) is not False:
            raise PackageError(f"Test package requires {key}=false in the app Info.plist")
    for key in ("SUFeedURL", "SUPublicEDKey"):
        value = info.get(key)
        if value not in (None, ""):
            raise PackageError(f"Test package must not contain configured {key}")

    minimum_os = info.get("LSMinimumSystemVersion")
    if not isinstance(minimum_os, str) or not minimum_os:
        raise PackageError("App bundle is missing LSMinimumSystemVersion")

    raw_architectures = set(run_output(["lipo", "-archs", str(executable)]).split())
    actual_architectures = tuple(arch for arch in REQUIRED_ARCHITECTURES if arch in raw_architectures)
    if actual_architectures != expected_architectures:
        raise PackageError(
            f"App architectures are {', '.join(actual_architectures) or 'unknown'}; "
            f"expected exactly {', '.join(expected_architectures)}"
        )

    for path in app_path.rglob("*"):
        if path.is_symlink():
            continue
        if path.name in FORBIDDEN_NAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES:
            raise PackageError(f"Refusing to package a sensitive or model file inside the app: {path}")

    return {
        "bundleIdentifier": EXPECTED_BUNDLE_ID,
        "version": EXPECTED_VERSION,
        "build": EXPECTED_BUILD,
        "architectures": list(actual_architectures),
        "minimumMacOS": minimum_os,
    }


def copy_package_contents(repo_root: Path, app_path: Path, staging_root: Path) -> Path:
    """Stage only the app, Applications shortcut, install guide, and legal notices."""

    missing = [str(path) for path in REQUIRED_LEGAL_FILES if not (repo_root / path).exists()]
    if not INSTALL_GUIDE.is_file():
        missing.append(str(INSTALL_GUIDE.relative_to(repo_root)))
    if missing:
        raise PackageError(f"Required package file(s) are missing: {', '.join(missing)}")

    staged_app = staging_root / app_path.name
    run_command(["ditto", "--norsrc", "--noextattr", str(app_path), str(staged_app)])
    (staging_root / "Applications").symlink_to("/Applications")
    shutil.copy2(INSTALL_GUIDE, staging_root / "INSTALL.txt")
    shutil.copy2(repo_root / "LICENSE", staging_root / "LICENSE")
    shutil.copy2(repo_root / "THIRD_PARTY_LICENSES.md", staging_root / "THIRD_PARTY_LICENSES.md")
    shutil.copy2(
        repo_root / "Cotabby/Resources/SpellingDictionaries/NOTICE.md",
        staging_root / "SpellingDictionaries-NOTICE.md",
    )
    shutil.copy2(
        repo_root / "Cotabby/Resources/learning-expressions.NOTICE.md",
        staging_root / "LearningExpressions-NOTICE.md",
    )
    shutil.copytree(
        repo_root / "Cotabby/Resources/ThirdPartyLicenses",
        staging_root / "ThirdPartyLicenses",
    )
    return staged_app


def source_snapshot(repo_root: Path) -> tuple[str, bool, bool]:
    commit = run_output(["git", "rev-parse", "HEAD"], cwd=repo_root)
    status_command = ["git", "status", "--porcelain", "--untracked-files=all"]
    working_tree_dirty = bool(run_output(status_command, cwd=repo_root))
    source_status = run_output(
        [*status_command, "--", *APP_BUILD_INPUT_PATHS], cwd=repo_root
    )
    return commit, bool(source_status), working_tree_dirty


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def package_name(architectures: tuple[str, ...]) -> str:
    label = "universal" if architectures == REQUIRED_ARCHITECTURES else "-".join(architectures)
    return f"Lingrove-{EXPECTED_VERSION}-test-{label}.dmg"


def build_info(
    *,
    app_metadata: dict[str, object],
    source_commit: str,
    source_dirty: bool,
    working_tree_dirty: bool,
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "product": PRODUCT_NAME,
        **app_metadata,
        "sourceCommit": source_commit,
        "sourceDirty": source_dirty,
        "workingTreeDirty": working_tree_dirty,
        "codeIdentity": "ad-hoc",
        "notarized": False,
        "createdAtUTC": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }


def publish_candidate(candidate_files: dict[Path, Path]) -> None:
    """Atomically add complete candidate files without replacing existing outputs.

    Each link is a same-volume atomic publication operation. If an unexpected
    collision or filesystem error interrupts the set, remove only the links
    created by this invocation; the completed candidate itself remains staged
    until its temporary directory is cleaned up.
    """

    destinations = list(candidate_files.values())
    existing = [str(path) for path in destinations if path.exists()]
    if existing:
        raise PackageError(
            "Refusing to overwrite existing package output(s): " + ", ".join(existing)
        )

    published: list[Path] = []
    try:
        for source, destination in candidate_files.items():
            os.link(source, destination)
            published.append(destination)
    except OSError as error:
        for path in reversed(published):
            path.unlink(missing_ok=True)
        raise PackageError(f"Could not publish complete test package: {error}") from error


def package_app(
    *,
    repo_root: Path,
    app_path: Path,
    output_dir: Path,
    expected_architectures: tuple[str, ...],
) -> tuple[Path, Path, Path]:
    """Validate, sign, stage, build, and publish the complete DMG candidate."""

    repo_root = repo_root.resolve()
    app_path = app_path.expanduser().resolve()
    output_dir = output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    app_metadata = validate_app(app_path, expected_architectures)
    dmg_name = package_name(expected_architectures)
    dmg_path = output_dir / dmg_name
    checksums_path = output_dir / "SHA256SUMS.txt"
    info_path = output_dir / "build-info.json"
    collisions = [path for path in (dmg_path, checksums_path, info_path) if path.exists()]
    if collisions:
        raise PackageError(
            "Refusing to overwrite existing package output(s): "
            + ", ".join(str(path) for path in collisions)
        )

    source_commit, source_dirty, working_tree_dirty = source_snapshot(repo_root)
    with tempfile.TemporaryDirectory(prefix=".lingrove-test-package-", dir=output_dir) as temporary:
        candidate_root = Path(temporary)
        dmg_candidate = candidate_root / f".{dmg_name}.candidate.dmg"
        staged_root = candidate_root / "disk"
        staged_root.mkdir()
        staged_app = copy_package_contents(repo_root, app_path, staged_root)

        # The local package has no Developer ID. Re-sign a clean staging copy
        # without hardened runtime or testing entitlements, then verify the
        # nested code before it enters the disk image.
        run_command(
            [
                sys.executable,
                str(SIGNING_HELPER),
                str(staged_app),
                "--identity",
                "-",
                "--no-hardened-runtime",
            ]
        )
        run_command(["codesign", "--verify", "--deep", "--strict", str(staged_app)])

        run_command(
            [
                "hdiutil",
                "create",
                "-srcfolder",
                str(staged_root),
                "-volname",
                PRODUCT_NAME,
                "-format",
                "UDZO",
                str(dmg_candidate),
            ]
        )
        if not dmg_candidate.is_file():
            raise PackageError(f"hdiutil did not create the expected image: {dmg_candidate}")
        run_command(["hdiutil", "verify", str(dmg_candidate)])

        info_candidate = candidate_root / "build-info.json"
        info_candidate.write_text(
            json.dumps(
                build_info(
                    app_metadata=app_metadata,
                    source_commit=source_commit,
                    source_dirty=source_dirty,
                    working_tree_dirty=working_tree_dirty,
                ),
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        checksum_candidate = candidate_root / "SHA256SUMS.txt"
        checksum_candidate.write_text(
            f"{sha256(dmg_candidate)}  {dmg_name}\n", encoding="utf-8"
        )

        publish_candidate(
            {
                dmg_candidate: dmg_path,
                checksum_candidate: checksums_path,
                info_candidate: info_path,
            }
        )
    return dmg_path, checksums_path, info_path


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    repo_root = Path(__file__).resolve().parents[1]
    try:
        architectures = parse_architectures(args.architectures)
        output_dir = args.output_dir or repo_root / "build/distributions"
        if args.app_path:
            dmg_path, checksums_path, info_path = package_app(
                repo_root=repo_root,
                app_path=args.app_path,
                output_dir=output_dir,
                expected_architectures=architectures,
            )
        else:
            dmg_path, checksums_path, info_path = build_and_package_release(
                repo_root=repo_root,
                output_dir=output_dir,
                expected_architectures=architectures,
            )
    except (PackageError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"Created {dmg_path}")
    print(f"Checksums: {checksums_path}")
    print(f"Build metadata: {info_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
