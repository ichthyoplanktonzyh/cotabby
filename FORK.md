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

## Reviewed upstream autocomplete fixes — 2026-10-15

The following unmerged upstream PRs were reviewed and adopted on
`codex/adopt-upstream-autocomplete-fixes`, starting from Lingrove `4963cf3e`.
All target upstream `main`; none depends on another unmerged PR. Only each PR's head ref was
fetched, with tags disabled. The captured head repository/branch and SHA are recorded below.
All selected commits retain their original authors and full source SHA through `cherry-pick -x`.

| PR | Head repository / branch | Captured head SHA | Selected source commits |
| --- | --- | --- | --- |
| [#839](https://github.com/FuJacob/cotabby/pull/839) | `FuJacob/cotabby` / `fix/rapid-tab-unreadable-surface-facts` | `911d72f5832ac137dc304ed61a2cacfe22f237c0` | `3b7802e50e75ce2029f76d1b687d13b6a931ddbc`, `911d72f5832ac137dc304ed61a2cacfe22f237c0` |
| [#853](https://github.com/FuJacob/cotabby/pull/853) | `senadaruc/cotabby` / `fix/empty-field-no-value` | `8ce0a70c5afa999529bcb2f0320bc82f4979e45f` | `ff662bd0b36a8baec114c38fed11c0fd05d36714`, `fcb7bf15e7779e0f90611197dbc831c90977fa42`, `8ce0a70c5afa999529bcb2f0320bc82f4979e45f` |
| [#852](https://github.com/FuJacob/cotabby/pull/852) | `senadaruc/cotabby` / `fix/card-over-unmeasured-line` | `cba81c52e59614e360e68f8a746f37c86d3dae7b` | `cba81c52e59614e360e68f8a746f37c86d3dae7b` |
| [#867](https://github.com/FuJacob/cotabby/pull/867) | `senadaruc/cotabby` / `fix/ghost-field-bottom-main` | `3ee0fd75d579f708e16e4445089387d0e4b8ef28` | `3ee0fd75d579f708e16e4445089387d0e4b8ef28` |
| [#866](https://github.com/FuJacob/cotabby/pull/866) | `senadaruc/cotabby` / `fix/search-field-block` | `90fd178c0f13a1feaa14ded37bb3a363f6d7deef` | `90fd178c0f13a1feaa14ded37bb3a363f6d7deef` |
| [#856](https://github.com/FuJacob/cotabby/pull/856) | `senadaruc/cotabby` / `fix/ocr-field-and-prompt-echo` | `f6a22f4f59e42f9e056ef4ecbea4c6361cac5bc7` | `f6a22f4f59e42f9e056ef4ecbea4c6361cac5bc7` |

Two independent GPT-6 Luna reviewers (max reasoning), requested by the maintainer, reviewed
the focus/field and layout/OCR groups separately. Review findings were addressed before integration:

- Active-tail reconciliation tolerates an unreadable title/URL/placeholder, preserving rapid Tab
  acceptance. New async results and speculative predictions still require exact request identity;
  `ContextBuffer` retires a request when its surface facts become unreadable. A stale final result
  reconciles an already visible tail independently rather than hiding it unconditionally. Screen
  excerpts retain their existing exact identity boundary. Retaining an already displayed tail
  during one unreadable surface poll remains an explicit availability tradeoff.
- `GhostTextLayout` checks the field floor on every row entry, including the path that moves a
  whole word from an empty caret row to the next line. `OverlayController` ignores Monaco's hidden
  textarea as a vertical boundary, matching its existing horizontal-boundary rule.
- `WindowScreenshotService` provides the element's actual column to OCR selection before falling
  back to the widened card frame. OCR below the caret in that column is deliberately omitted;
  subsequent field text comes from the existing bounded AX suffix instead. Prompt-preface filtering
  remains a heuristic and can also truncate prose quoting those exact preface phrases.
- `LearningCapturePolicy` owns the pure distinction between passive previews and explicit learning.
  Search fields remain ineligible for automatic completion and passive translation, but a verified
  explicit learning shortcut may capture their text. The AX capture service retains all selection,
  secure-field, input-method and write-safety checks. The sentence coordinator checks capability
  before debounce and after AX capture, withdraws passive work on capability-only changes, and
  records whether the user explicitly requested a surviving search-field preview.
- Generated Xcode project conflicts were resolved through `project.yml` and XcodeGen, preserving
  Lingrove's identities, schemes and localization configuration.

Validation on Xcode 26.5 / Apple Silicon, against the prepared pinned inference workspace:

- Release `build-for-testing` passed. Targeted regression execution passed: 256 XCTest cases and
  31 Swift Testing cases. The complete unit run passed: 2866 XCTest cases (13 environment-gated
  skips) and 235 Swift Testing cases (one opt-in skip), zero failures: 3101 cases total, 3087 passed
  and 14 skipped. Model-backed evals were run separately.
- Both local model suites used `gemma-4-E2B.i1-Q6_K.gguf` with seed 42 before and after adoption.
  The 117 continuation cases retained quality score 0.882051; the 23 recall cases retained
  0.739130. All 140 displayed outputs, outcomes and suppression stages were identical.
- Strict SwiftLint on affected Swift files reports 13 inherited findings, versus 14 in the same
  baseline files, with no new findings. `git diff --check` passed. XcodeGen was regenerated from
  the fork's own specification and a second regeneration produced identical bytes.
- The separate `Cotabby Dev` Release build passed. Its candidate was signed with the installed
  development identity and checked against the existing designated requirement before replacement.
  The installed binary timestamp advanced; one dev process started successfully, with Accessibility
  and Input Monitoring still granted and the log reporting all services started.
- An initial full run was interrupted after sampling a block in developer screenshot cleanup's
  Desktop directory enumeration. The successful full run omitted only the `-cotabby-debug` test
  launch argument, avoiding diagnostic Desktop I/O. The unchanged aria2 cancel-process test also
  timed out in the initial run and an isolated recheck, then passed with its entire suite in the
  successful complete run. No aria2 production or test code was changed for this adoption.
- Full before/after pixel measurements across TextEdit, Chrome, Safari and Obsidian remain a
  manual follow-up. Computer automation detected a user application change during preparation,
  so further foreground interaction was stopped. The unit results above do not establish the
  approximately 0.2pt per-line placement target in real hosts.

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
