# Releasing Lingrove (拾语)

This document owns the distribution boundary: how our app becomes a signed release and how
installed copies discover it. App lifecycle stays in `AppUpdateManager`, packaging stays in
`scripts/build_release_dmg.py`, and GitHub Actions coordinates building, notarizing, and publishing.

## Current state

- The production `Cotabby` scheme produces `Lingrove.app` with Bundle ID
  `io.ichthyoplanktonzyh.lingrove`; `Cotabby Dev` produces `Lingrove Dev.app` with
  `io.ichthyoplanktonzyh.lingrove.dev`. The internal scheme/module names remain unchanged.
- Sparkle is included but never started: `LingroveUpdatesEnabled` is false, automatic checks and
  installation are off, and there is no inherited `SUFeedURL` or `SUPublicEDKey`.
- The manual update action opens this repository's GitHub Releases page. There is no independent
  automatic-update service or verified upgrade path yet.
- Release and Pages-republish jobs require repository variable `LINGROVE_RELEASES_ENABLED=true`.
  Leave it unset until the steps below are complete. The upstream Homebrew dispatch is removed.
- Developer signing has no shared team default. Each developer uses `Config/Signing.local.xcconfig`;
  CI supplies its own distribution team and certificate.
- The v0.5 build 1 test app is ad-hoc signed and packaged in a DMG for the public `v0.5-test.1` prerelease. It
  is not Developer ID signed, notarized, or connected to automatic updates; this does not enable
  the production release or Pages workflows.

Local development can continue without a paid Apple Developer Program membership. The production
Developer ID signing and notarization flow described here requires that membership; keep release
jobs paused until its certificates and notarization credentials are available. The ad-hoc v0.5
test package also does not require a paid membership; its test status and Gatekeeper steps
are documented below.

## v0.5 test package (public prerelease)

The current test artifact is `build/distributions/Lingrove-0.5-test-universal.dmg`, accompanied by
`SHA256SUMS.txt` and `build-info.json`. The DMG, Chinese install guide, checksum, and build metadata
are published at the [v0.5-test.1 prerelease](https://github.com/ichthyoplanktonzyh/lingrove/releases/tag/v0.5-test.1).
The app is an ad-hoc-signed, unnotarized test build, has no automatic updates, and is not a public
production release. The DMG includes the Simplified Chinese `INSTALL.txt` guide (copied from the
source file `assets/testing/INSTALL.zh-CN.txt`), the app, an Applications shortcut, and license
materials: `LICENSE`, `THIRD_PARTY_LICENSES.md`, `SpellingDictionaries-NOTICE.md`,
`LearningExpressions-NOTICE.md`, and `ThirdPartyLicenses/`. It does not include user preferences,
credentials, or downloaded inference/learning model weights.

`build-info.json` records the package's product/bundle identity, version/build, source commit,
actual architecture slices, minimum macOS version, signing/notarization state, and creation time.
Its `sourceDirty` flag reports whether tracked or untracked app build inputs were modified;
`workingTreeDirty` reports whether anything in the full checkout was modified. The checkout can
therefore be dirty because of documentation or packaging work while the built app inputs remain
clean.

The Xcode deployment target is macOS 14.0. The universal app contains `arm64` and `x86_64` slices.
Build, package-integrity, and basic-launch checks run locally on Apple Silicon; Intel hardware and
the downloaded first-install flow on other Macs remain for testers to validate. This does not claim
a fresh-machine Gatekeeper flow has been validated. Apple Intelligence autocomplete requires a
supported Mac running macOS 26 or later. Otherwise, testers can download a compatible GGUF model
(which may take several GB) or explicitly configure an OpenAI-compatible endpoint. No provider
credentials are bundled. Translation and optional chunk alignment use their own independently
configured local models or endpoints.

Before installation, verify the DMG against the accompanying checksum file from the same trusted
delivery:

```sh
cd build/distributions
shasum -a 256 -c SHA256SUMS.txt
```

Open the DMG, drag `Lingrove.app` to its `Applications` shortcut, eject the mounted disk image in
Finder, then launch Lingrove from Applications. Do not run the app from the mounted DMG. Because
this test build is not Developer ID signed or notarized, Gatekeeper may require the user to open it
once, dismiss the first warning, then choose **Open Anyway** under System Settings → Privacy &
Security. Continue only for a package downloaded from this repository's Releases with a matching
checksum. If macOS says the app “will damage your computer,” or reports a broken/corrupt signature,
stop and verify the checksum with the distributor; do not bypass the warning, remove quarantine, or
disable Gatekeeper. See Apple's [Gatekeeper guidance](https://support.apple.com/en-us/102445).

Accessibility and Input Monitoring are required for autocomplete. Screen Recording is optional and
is needed only when a tester enables screenshot-based visual context. After granting the first two
permissions the first time, quit Lingrove and reopen it once so the input listener starts with the
updated permission state. This package uses the production bundle identifier, while Lingrove Dev
uses a separate identifier and separate preferences/model storage; settings and models are not
imported from the dev app. During production-app testing, quit Lingrove Dev so only one app instance
owns the global keyboard monitor; uninstalling the dev app is unnecessary. Replacing an ad-hoc build
may require granting macOS permissions again.

Updates to this test build are manual: quit Lingrove, replace the app in Applications with the new
test copy, eject the DMG, and launch the replacement. Back up anything important before replacing
test builds. Input-history recording is optional, encrypted, and off by default; no history is
automatically imported from Lingrove Dev.

For autocomplete, use Settings → Appearance → **Show Field Indicator** if the focus indicator is
helpful, then type in a supported text field and press **Tab** to accept the suggestion. Acceptance
keys can be changed in Settings → Shortcuts. To try language learning, open Settings → Writing,
enable expression translation and (optionally) sentence previews, choose a target language, and
configure a translation model in Engine & Model. A pause after newly typed text can show its target
expression; the configured learning-detail shortcut expands source/translation alignment when that
feature and its separate model are enabled. Double-click an expression to try dictionary lookup.
Autocomplete and language learning are both core test areas.

Send feedback at [GitHub Issues](https://github.com/ichthyoplanktonzyh/lingrove/issues) with the
app version/build, macOS version, chip, and reproducible steps. Do not attach full prompts, model
logs, or private input; remove personal text and credentials from any diagnostic excerpt before
sharing it. A later formal distribution will require the Developer ID membership, signing and
notarization setup below. Although the production bundle identifier is already set, the ad-hoc test
signature is not the stable Developer ID distribution identity.

## Independent update architecture

Keep Sparkle as the updater. GitHub Releases stores the signed, notarized `Lingrove.dmg`, while
GitHub Pages hosts `appcast.xml`. No application server or custom domain is required for this plan.
With the current repository name, the intended standard Pages feed is
`https://ichthyoplanktonzyh.github.io/lingrove/appcast.xml`; this is a planned address, not a deployed
service. Confirm the actual URL after enabling Pages. Optionally set `LINGROVE_UPDATES_DOMAIN` to a
domain we control; release CI then writes its CNAME.

The flow is:

1. Archive the production app with an increasing build number and our Developer ID signature.
2. Package, notarize, and staple the final DMG.
3. Sign that final archive with our Sparkle Ed25519 private key.
4. Generate the appcast with version, minimum-platform metadata where needed, download URL,
   archive length, and signature. The workflow passes its own GitHub owner/repository explicitly.
5. Upload the DMG to Releases, then publish the appcast to Pages.
6. Installed apps read the feed; Sparkle compares build numbers, downloads and validates the archive,
   and handles installation/relaunch. Checking for an update and installing it are separate policies.

Apple Developer ID signing/notarization establishes the macOS distribution identity. Sparkle's
Ed25519 signature authenticates the update archive to the installed app. These are separate keys
and both must belong to Lingrove's release process.

## Configuration before enabling updates

1. Configure our Developer ID certificate and Apple notarization account in repository secrets:
   `DEVELOPER_ID_APPLICATION_CERT`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`,
   and `APPLE_APP_SPECIFIC_PASSWORD`. Preserve their existing workflow encodings.
2. Generate a distinct Sparkle key using the pinned Sparkle tools. Use a separate Keychain account
   so another product's existing key is not silently reused:

   ```sh
   <Sparkle tools>/generate_keys --account lingrove
   ```

   Put the printed public key in `SUPublicEDKey` in `CotabbyInfo.plist`. Keep the private key in
   Keychain, back it up securely, and provide the exported key to CI as
   `SPARKLE_ED25519_PRIVATE_KEY`. Do not put it in the repository or command output. The existing
   release job checks that CI's private key matches the bundled public key.
3. Enable GitHub Pages with GitHub Actions as its source and configure the `github-pages`
   environment. Add `SUFeedURL` using the confirmed HTTPS feed URL.
4. Set `LingroveUpdatesEnabled` to true for production. Choose automatic-check/install defaults
   explicitly; development remains disabled regardless of this flag. Recommended initial behavior
   is automatic checks with user-confirmed installation.
5. Set `LINGROVE_RELEASES_ENABLED=true` only after the app and workflow configuration agree. A
   `workflow_dispatch` run with `publish: false` validates packaging/notarization without publishing;
   a `v<version>` tag publishes. Versions use SemVer and `github.run_number` supplies the increasing
   build number. Preserve monotonic build numbers if the workflow or repository is replaced.
6. Test an older signed Lingrove version upgrading to a newer signed version using a staging feed.
   Verify the signature, install location, restart, settings/history/model preservation, permissions,
   failure/cancellation behavior, and that dev/upstream installations are unaffected. Use a staging
   feed to confirm invalid signatures are rejected before declaring updates ready.
7. Publish the corresponding source and build instructions for each distributed release, including
   the pinned inference revision and applied patch. See LICENSE and THIRD_PARTY_LICENSES.md.

## Native dependency and historical releases

Run `scripts/prepare_cotabby_workspace.sh` before building: it pins CotabbyInference and applies
`patches/cotabbyinference-upstream-pending.patch`. Do not remove the patch before a compatible
package revision is available. See CONTRIBUTING.md for builds and tests.

Historical Cotabby / CoHamster release notes describe earlier binaries. They do not configure
Lingrove's identity, feed, keys, or release destinations.

References: [Sparkle setup](https://sparkle-project.org/documentation/) and
[publishing updates](https://sparkle-project.org/documentation/publishing/), plus
[GitHub Pages setup](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)
and [Apple Developer ID](https://developer.apple.com/developer-id/).
