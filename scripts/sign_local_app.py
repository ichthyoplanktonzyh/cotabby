#!/usr/bin/env python3
"""Sign a local dev/test app outside Documents/iCloud, then replace the build product.

Xcode's compile output stays in repo-scoped DerivedData. A temporary metadata-free
copy is the signing boundary because a file provider can restore FinderInfo while
codesign is running. build_and_run.sh calls this helper before launching the app.
The test-DMG packager also uses it for a staged ad-hoc app, with an explicit
ad-hoc-only option to omit hardened runtime. Developer certificate behavior
stays unchanged, and the test-package path never grants XCTest entitlements.
"""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def run(*args):
    subprocess.run(args, check=True)


def codesign_arguments(identity, *, no_hardened_runtime=False):
    """Build the common codesign prefix while preserving certificate defaults."""

    command = ["codesign", "--force"]
    if not no_hardened_runtime:
        command.extend(["--options", "runtime"])
    command.extend(["--timestamp=none", "--sign", identity])
    return command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--testing", action="store_true")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument(
        "--no-hardened-runtime",
        action="store_true",
        help="Omit hardened runtime only for an ad-hoc test package.",
    )
    args = parser.parse_args()
    if args.no_hardened_runtime and args.identity != "-":
        parser.error("--no-hardened-runtime is allowed only with ad-hoc identity '-'")
    if args.no_hardened_runtime and (args.debug or args.testing):
        parser.error("--no-hardened-runtime cannot be combined with debug or testing entitlements")
    original = args.app.resolve()
    if original.suffix != ".app" or not (original / "Contents/Info.plist").is_file():
        parser.error("Expected a built .app bundle")
    with tempfile.TemporaryDirectory(prefix="cotabby-local-sign-") as temporary:
        app = Path(temporary) / original.name
        run("ditto", "--norsrc", "--noextattr", str(original), str(app))
        run("xattr", "-cr", str(app))
        # Sign leaf Mach-O files first, followed by their containing code bundles.
        # Don't follow symlinks: versioned frameworks expose the same binary twice.
        magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
                 b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
                 b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
        candidates = []
        for path in app.rglob("*"):
            if path.is_symlink():
                continue
            if path.is_dir() and path.suffix in (".app", ".framework", ".xpc", ".xctest"):
                candidates.append(path)
            elif path.is_file():
                with path.open("rb") as stream:
                    if stream.read(4) in magic:
                        candidates.append(path)
        sign = codesign_arguments(
            args.identity, no_hardened_runtime=args.no_hardened_runtime
        )
        for path in sorted(candidates, key=lambda item: len(item.parts), reverse=True):
            run(*sign, str(path))
        entitlements = {}
        if args.debug or args.testing:
            entitlements["com.apple.security.get-task-allow"] = True
        if args.testing:
            # XCTest injects its runner libraries into the host. Only the temporary
            # test build gets this entitlement; production packages never use it.
            entitlements["com.apple.security.cs.disable-library-validation"] = True
        entitlement_file = Path(temporary) / "local.entitlements"
        entitlement_file.write_bytes(plistlib.dumps(entitlements))
        if entitlements:
            run(*sign, "--entitlements", str(entitlement_file), str(app))
        else:
            run(*sign, str(app))
        run("codesign", "--verify", "--deep", "--strict", str(app))
        # Preserve the existing product until a complete valid signature exists.
        shutil.rmtree(original)
        run("ditto", "--norsrc", "--noextattr", str(app), str(original))
        run("codesign", "--verify", "--deep", "--strict", str(original))


if __name__ == "__main__":
    main()
