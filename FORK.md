# Fork ownership and development

This document records how this independent fork relates to upstream and how development becomes
a release. It complements CONTRIBUTING.md, which owns the build and test instructions.

## Direction and attribution

- Fork: https://github.com/ichthyoplanktonzyh/cotabby
- Upstream: https://github.com/FuJacob/cotabby
- Product direction: translation and expression learning within everyday writing, with autocomplete
  retained as a supporting capability.
- Current priority: stabilize the Swift macOS experience. Rust shared logic and Flutter clients are
  a future direction, not part of the current migration.
- Cotabby remains the provisional name. Original authorship and contributor attribution remain
  intact; this fork does not claim ownership of upstream contributions.
- LICENSE remains AGPL v3. Third-party code, dictionaries, and model weights retain their own terms.

## Repository workflow

`origin` points to this fork; `upstream` points to FuJacob/Cotabby. Push development branches to
`origin` and open pull requests against this fork's `main`, not upstream by default.

The initial `codex/language-learning` branch contains a checkpoint of the existing local learning
implementation and supporting input, insertion, endpoint, and settings changes. A checkpoint is
not a claim that the code has passed release validation. Keep it separate from `main` until reviewed
and tested under CONTRIBUTING.md.

Fetch upstream changes explicitly and review them before merging. Upstream fixes are useful inputs,
not automatic product decisions. Avoid rebasing or force-pushing a shared development branch.

Interface localization follows the same boundary: `Localizable.xcstrings` is the upstream common
catalog, while `Learning.xcstrings` contains this fork's learning and integration copy. English is
the UI source language with 14 translated locales. Interface language, autocomplete languages,
and learning source/target languages remain separate preferences. See CONTRIBUTING.md for catalog
ownership, translation imports, and compiled-resource checks.

```sh
git fetch upstream
git push origin codex/language-learning
```

## Before the first independent release

- Choose the product name, icons, Bundle IDs, and signing configuration for the fork.
- Update in-app links for this build's source and license to the fork while retaining upstream credit.
- Replace upstream website, download, support, and release badges in README with fork destinations.
- Replace the production Sparkle feed and public key with the fork's update infrastructure.
- Configure release workflows for the fork's domains, repositories, signing and notarization secrets;
  the inherited workflows still contain upstream destinations. Do not publish with those defaults.
- Review licenses for bundled dependencies, dictionaries, and any distributed model weights.
- Publish corresponding source and required build instructions for each distributed version.
- Validate the app's behavior, permissions, endpoint disclosure, and update flow before shipping.

Until these steps are complete, use the isolated Cotabby Dev configuration described in
CONTRIBUTING.md for local development. No independent production release is established yet.
