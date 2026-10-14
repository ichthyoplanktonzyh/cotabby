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

Local development can continue without a paid Apple Developer Program membership. The production
Developer ID signing and notarization flow described here requires that membership; keep release
jobs paused until its certificates and notarization credentials are available.

## Independent update architecture

Keep Sparkle as the updater. GitHub Releases stores the signed, notarized `Lingrove.dmg`, while
GitHub Pages hosts `appcast.xml`. No application server or custom domain is required for this plan.
With the current repository name, the intended standard Pages feed is
`https://ichthyoplanktonzyh.github.io/cotabby/appcast.xml`; this is a planned address, not a deployed
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
