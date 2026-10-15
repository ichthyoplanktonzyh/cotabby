# Repository origin and development

This document records Lingrove's relationship to Cotabby and how development reaches a release. It
complements CONTRIBUTING.md, which owns the build and test instructions.

## Direction and attribution

- Repository: https://github.com/ichthyoplanktonzyh/lingrove
- Upstream: https://github.com/FuJacob/cotabby
- Product direction: inline autocomplete and language learning are equally core capabilities.
  Develop both together for everyday writing, including translation and expression learning.
- Current priority: stabilize the Swift macOS experience. Rust shared logic and Flutter clients are
  a future direction, not part of the current migration.
- Product name: **Lingrove** in English and **拾语** in Chinese. Use `lingrove` for new technical
  identifiers. The name reflects learning expressions from everyday reading and writing.
- The approved Lingrove whale mark is maintained in `assets/branding/lingrove-logo.svg`, with
  `scripts/generate_brand_assets.mjs` as its asset-generation entry point. Release installer artwork
  remains a separate follow-up task.
- The field-edge activation indicator uses a separate tail-only source at
  `assets/branding/lingrove-activation-indicator.svg`.
- App products are `Lingrove.app` and `Lingrove Dev.app`, with Bundle IDs
  `io.ichthyoplanktonzyh.lingrove` and `io.ichthyoplanktonzyh.lingrove.dev`. The internal Xcode
  schemes (`Cotabby`, `Cotabby Dev`), Swift module, source folders, and inference dependency keep
  their existing names for now; these are build/code boundaries, not the installed app identity.
- Models, encrypted typing history, and logs use separate `Lingrove` / `Lingrove Dev` folders.
  Preferences and Keychain services use the new Bundle IDs. Existing Cotabby data stays untouched;
  automatic import is not implemented. Encrypted history requires its original key for any future
  migration, so copying only its archive is insufficient.
- Sparkle stays disabled in every build until independent updates are configured. Manual update
  checks open this repository's releases. User-facing brand copy and project links use Lingrove.
  See RELEASING.md for the independent update plan.
- Original authorship and contributor attribution remain intact; Lingrove does not claim ownership
  of upstream contributions.
- LICENSE remains AGPL v3. Third-party code, dictionaries, and model weights retain their own terms.

## Repository workflow

The GitHub fork-network relationship to FuJacob/Cotabby is intentionally retained. Lingrove keeps
its own product direction and repository identity; the visible fork link preserves the repository's
existing collaboration records and does not enable automatic upstream merges.

`origin` points to `ichthyoplanktonzyh/lingrove`; `upstream` points to FuJacob/Cotabby. Lingrove's
`main` is the active in-development integration branch. Review upstream changes before applying
them; upstream changes are inputs to evaluate, not automatic product decisions.

Before adopting an unmerged upstream pull request, review its GitHub page: confirm its base branch,
head repository and branch, full diff, and whether it depends on other pull requests or unmerged
commits. Fetch only the PR head ref with tags disabled, then inspect and record its head SHA. Create
a topic branch from Lingrove's `main` before cherry-picking reviewed commit(s). The `-x` option adds
each source commit SHA to the resulting commit message:

```sh
git fetch --no-tags upstream refs/pull/123/head
git show --stat --oneline FETCH_HEAD
git rev-parse FETCH_HEAD
git switch -c codex/adopt-pr-123 main
git cherry-pick -x REVIEWED_COMMIT_SHA
```

Replace `123` with the pull request number and `REVIEWED_COMMIT_SHA` with a reviewed commit ID.
Record the PR URL, captured PR head SHA, selected commit SHA(s), dependencies, and adoption or
rejection result in the integration PR or review notes. If local comparison with the PR base is
needed, fetch only that specific upstream base ref with `--no-tags`. This is a manual review
workflow; it does not automatically merge upstream changes. Avoid rebasing or force-pushing a
shared development branch.

The original `codex/language-learning` branch was a checkpoint of the local learning implementation
and related input, insertion, endpoint, and settings work. The approved work from that checkpoint is
now part of Lingrove's `main` branch. The branch name records an intermediate development step; the
checkpoint itself was not a release-validation signoff.

Interface localization follows the same boundary: `Localizable.xcstrings` is the upstream common
catalog, while `Learning.xcstrings` contains Lingrove's learning and integration copy. English is
the UI source language with 14 translated locales. Interface language, autocomplete languages,
and learning source/target languages remain separate preferences. See CONTRIBUTING.md for catalog
ownership, translation imports, and compiled-resource checks.

## Before the first independent release

- Every developer supplies their own signing team through the local xcconfig; there is no upstream
  team default.
- Keep project destinations centralized in `ProductIdentity`, while retaining upstream credit.
- Update README's installation instructions when the first independent download is available.
- Configure Lingrove's Sparkle feed and public key, then enable automatic updates explicitly.
- Configure the repository's signing and notarization secrets and Pages hosting before setting
  `LINGROVE_RELEASES_ENABLED=true`. Release and Pages-republish jobs are paused by default; the
  upstream Homebrew dispatch has been removed.
- Review licenses for bundled dependencies, dictionaries, and any distributed model weights.
- Publish corresponding source and required build instructions for each distributed version.
- Validate the app's behavior, permissions, endpoint disclosure, and update flow before shipping.

Until these steps are complete, use the isolated Cotabby Dev configuration described in
CONTRIBUTING.md for local development. No independent production release is established yet.
