# Fork ownership and development

This document records how this independent fork relates to upstream and how development becomes
a release. It complements CONTRIBUTING.md, which owns the build and test instructions.

## Direction and attribution

- Fork: https://github.com/ichthyoplanktonzyh/cotabby
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
- Original authorship and contributor attribution remain intact; this fork does not claim ownership
  of upstream contributions.
- LICENSE remains AGPL v3. Third-party code, dictionaries, and model weights retain their own terms.

## Repository workflow

`origin` points to this fork; `upstream` points to FuJacob/Cotabby. This fork's `main` is the active
in-development integration branch. Review changes before integrating them there; upstream changes
are inputs to evaluate, not automatic product decisions.

The original `codex/language-learning` branch was a checkpoint of the local learning implementation
and related input, insertion, endpoint, and settings work. The approved work from that checkpoint is
now part of this fork's `main` branch. The branch name records an intermediate development step;
the checkpoint itself was not a release-validation signoff.

Fetch upstream changes explicitly and review them before merging. Avoid rebasing or force-pushing a
shared development branch.

Interface localization follows the same boundary: `Localizable.xcstrings` is the upstream common
catalog, while `Learning.xcstrings` contains this fork's learning and integration copy. English is
the UI source language with 14 translated locales. Interface language, autocomplete languages,
and learning source/target languages remain separate preferences. See CONTRIBUTING.md for catalog
ownership, translation imports, and compiled-resource checks.

```sh
git fetch upstream
```

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
