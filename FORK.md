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

## Reviewed upstream appearance and CI updates — 2026-10-15

The maintainer approved #854, #857, #873 and #874 for the next adoption batch. They were
reviewed on `codex/adopt-ghost-appearance-and-ci`, starting from Lingrove `608b3159`.
All target upstream `main`; each contains one independent commit and has no dependency on another
unmerged PR. Only the exact PR head refs were fetched, with tags disabled. All four source commits
retain original authorship and their full source SHA through `cherry-pick -x`.

| PR | Head repository / branch | Captured head and selected source SHA | Result |
| --- | --- | --- | --- |
| [#854](https://github.com/FuJacob/cotabby/pull/854) | `senadaruc/cotabby` / `feat/match-host-text-size` | `3ad26d6d468b7564b6a4aa78eb7e315a51e8277f` | Adopted: optional host-size matching, with the shared 9pt readability minimum. |
| [#857](https://github.com/FuJacob/cotabby/pull/857) | `senadaruc/cotabby` / `feat/ghost-text-style` | `67928d80f99068076d63d7789d18cf5fc43908d7` | Adopted: bold, italic and white suggestion presentation. Accepted text keeps the host's style. |
| [#873](https://github.com/FuJacob/cotabby/pull/873) | `FuJacob/cotabby` / `dependabot/github_actions/actions/download-artifact-8.0.2` | `d9da9cab821f235ecdcdb73de077751074fcc904` | Adopted: official download-artifact v8.0.2 SHA. |
| [#874](https://github.com/FuJacob/cotabby/pull/874) | `FuJacob/cotabby` / `dependabot/github_actions/actions/upload-artifact-7.0.2` | `d377057124a097ff526038f758338688c176b465` | Adopted: official upload-artifact v7.0.2 SHA. |

Two independent GPT-6 Luna reviewers (max reasoning), requested by the maintainer, reviewed
font/layout and settings/localization/CI separately, then re-reviewed the integration fixes. Neither
reported a remaining P1/P2 blocker. The integration includes these corrections:

- `GhostFontResolver.resolveForMirror` seeds card sizing from valid reported font/width evidence,
  with a conservative 13pt fallback when no size is known. It never derives a size from an
  unreliable field-height caret. `OverlayController` then applies its existing pixel match, zoom,
  caret-advance and settled-font memory pipeline. Matching therefore does not bypass measurements
  by passing raw CSS font size straight to the card. The normal inline path remains unchanged.
- Bold card measurement reserves the heavy next-acceptance prefix used by the view. Inline drawing
  styles the resolved host face only after host measurements; consumed prefixes continue to use
  the original host font, preserving the host insertion advance.
- All three new toggles default off. Existing size tuning and plain text therefore remain the
  defaults. Model/store round trips and reset coverage include the new values. The preview ignores
  the custom multiplier when host matching is on, and Settings search can find matching via `ghost`.
- New appearance copy and all palette help/accessibility labels use the fork's `Learning` catalog,
  covering English and all 14 translated locales. `Localizable.xcstrings` remains byte-identical to
  the baseline common catalog. Wording discloses the 9pt readability minimum rather than promising
  an exact match for a 6pt host.
- The Actions changes only replace existing pinned upload/download versions. Independent release
  and Pages publication gates remain intact; Sparkle remains disabled. Model requests, prompting,
  sampling, hosted-transmission scope and the language-learning pipeline are unchanged.

A pre-existing RTL partial-acceptance geometry gap identified during review is outside this batch:
its remaining-tail alignment does not yet account for the accepted prefix's host advance. The new
LTR styling path does not introduce that gap; it remains a follow-up rather than a verified fix.

Validation on Xcode 26.5 / Apple Silicon, using the prepared pinned inference workspace:

- Release `build-for-testing` passed. Three early attempts exposed only newly written test-source
  compile issues (private layout constants and the Foundation property-list read options); those
  were corrected before the successful build and actual test execution.
- Targeted execution passed all 220 test items, with no skips or failures. This includes host-font
  resolution, font styling, pixel alignment, inline/floor/card layout, settings storage/reset,
  Settings search and compiled localization resources. Parameterized font checks cover invalid
  sizes and a field-height caret, plus the measured 14-to-15.4pt web sizing case.
- Complete unit execution passed: 3118 test items, 3098 passed, 20 environment/opt-in skips, zero
  failures. This comprises 2879 XCTest items and 239 Swift Testing items. The test host's debug
  launch flag was removed before execution to avoid the already documented Desktop debug-capture
  I/O issue. No model-backed quality suite was rerun because prompt/context/sampling/model code
  is unchanged in this batch.
- Both String Catalogs validate across 15 languages (1091 source keys); all five localization
  import/validation script tests passed. Compiled resource checks cover every palette label and
  the new appearance controls in all 14 translated locales.
- Strict SwiftLint on changed Swift files reports the same three inherited `large_tuple` findings
  as those files at `608b3159`, with no new findings. `git diff --check` passed. Regenerating with
  XcodeGen a second time produced identical project bytes.
- Real-host pixel signoff remains incomplete. Native UI automation entered synthetic text in an
  isolated TextEdit document, but the dev app's focus stream continued to identify Lingrove itself
  as frontmost, so no live ghost/accepted-host screenshot pair was obtained. The numerical 0.2pt
  TextEdit/Chrome/Obsidian matrix was therefore not claimed. Automated raster alignment tests pass;
  they do not substitute for that live-host matrix.
- The separate `Cotabby Dev` Release build passed. The candidate was signed with the installed
  development identity and verified against its designated requirement before replacement. The
  installed binary timestamp advanced, one dev process launched, Accessibility and Input Monitoring
  remained granted, and the local runtime reached ready state. The Chinese Appearance pane shows
  the new style, white palette and size-matching controls; all three new toggles remain off. Further
  UI input stopped when automation detected a concurrent user change.
- Test logs, xcresult summaries and the install receipt are retained under the gitignored
  `build/upstream-batch2/`. Production/test source hashes were verified unchanged after validation.
  Repo-local `build/DerivedData` was removed and its absence verified before completion.

## Reviewed upstream per-app settings adoption — 2026-10-15

The maintainer approved selective adoption of [#842](https://github.com/FuJacob/cotabby/pull/842)
after a dedicated review. Integration started from Lingrove `a99fc134` on
`codex/unify-per-app-settings`. The exact upstream head was
`senadaruc/cotabby:feat/per-app-settings` at
`cc77eb64c9f510a805e5dd7201554f6b0993a9af`, based on
`7724926b3e93f14e3b576ba46ff52c4f64d9712d`.

The per-app feature commit `e86b259d5b957cea3d3b86e2511965e1f666174b` was cherry-picked
with original authorship and a full `-x` source trailer, then adapted in `4beaa2e3`.
Selected list/UI corrections from the captured head were retained. Its stacked older #841 history
implementation and old history-fix commit were not replayed: Lingrove already has a newer history
store with message identity, cross-caret and card-number redaction, disabled-domain recording gates,
endpoint isolation and unavailable-archive/global-deletion recovery. #843 and #673 remain deferred.

The Apps pane now combines configured, historical, excluded and running apps in one searchable
list, with one detail page for completion availability, mid-line behavior, typo checks, acceptance
shortcuts, app instructions, history collection and app-scoped deletion. The list derives its data
from the existing stores rather than introducing another settings owner. Optional behavior fields
extend the existing per-app JSON record, preserving saved shortcuts and disabled-app rules.

The UI reuses `SettingsPaneScaffold`, grouped settings sections, `SettingsRowLabel`,
`SettingsCalloutView`, `KeybindRow` and `KeyRecorderView`. New list/detail composition remains in
`UI/Settings`, pure inheritance/list rules in `Support/Settings`, and durable values in
`Models/Settings`. Settings search retains the old Disabled Apps and Per-App Shortcuts aliases.
New copy uses the `Learning` catalog in English and all 14 translated locales; the common
`Localizable.xcstrings` catalog remains byte-identical to `a99fc134`.

The integration fixes the three confirmed upstream P2 findings and related acceptance gaps:

- App-scoped history deletion invalidates pending imports and synchronously retires the old index,
  phrase predictor and lookup cache. The existing serialized encrypted writer commits the filtered
  snapshot off MainActor; failure leaves records visible and retryable. A pending snapshot lets quit
  flush the intended deletion. Global deletion waits for an app deletion, and app errors do not hide
  an unresolved global archive/key deletion failure.
- App instructions are a separate bounded request value and prompt section, so a full global notes
  section cannot silently truncate them. Both Apple and base renderers receive the value. Empty app
  instructions emit no additional prompt bytes. The UI discloses that instructions reach whichever
  engine the user has selected, including an existing configured endpoint.
- Ordinary, speculative and rebased predictions apply the same per-app mid-line and committed-word
  typo rules. Existing visible-tail reconciliation is preserved. Autocorrect On retains the global
  auto-fix choice; Off disables all typo checks for that app. The inherited full-accept shortcut label
  still reflects global double-tap behavior and an app-specific accept-word shortcut.
- Final review reproduced an additional settings-cache gap: editing app instructions at an unchanged
  prefix restored old cached text without another request, and a suspended old prefetch could write
  back after the edit. `e20d8204` replaces the anchor cache on settings changes, model switches and
  shutdown. Each cache lifetime has an immutable identity; prefetch writes require the same identity.
  This also respects existing screen-context cache invalidation. Three coordinator regressions
  demonstrate both failures against the pre-fix binary and preserve valid unchanged-cache prefetching.

Two independent GPT-6 Luna reviewers (max reasoning), requested by the maintainer, re-reviewed
history/privacy and UI/settings/policy respectively. Both final reviews found no remaining P1/P2
blocker after the cache correction.

Validation on Xcode 26.5 / Apple Silicon, using the prepared pinned inference workspace:

- Release `build-for-testing` passed. The final targeted run passed all 318 test items, with no skips
  or failures. This includes the three cache regressions, ordinary/rebased per-app gates, settings
  persistence/publication, double-tap acceptance, prompt sections and deletion races.
- Final complete execution passed: 3150 test items, 3136 passed and 14 environment/opt-in skips,
  zero failures (2900 XCTest and 250 Swift Testing items). The host's diagnostic debug launch flag
  was omitted to avoid the previously documented Desktop debug-capture I/O issue.
- The first post-cache full attempt encountered the previously documented aria2 fake-process
  progress timeout and an unchanged endpoint test fixture's duplicate expectation-fulfillment
  crash. The next attempt completed with only the aria2 timeout. Both unchanged suites then passed
  all 33 cases when isolated on both baseline `a99fc134` and the integrated binary. The earlier
  pre-cache integration full run also passed all 3147 items (14 environment skips). Failure bundles
  and logs are retained alongside subsequent verification; neither aria2 nor endpoint production or
  fixture source was changed for this adoption.
- Both String Catalogs validate: 1114 source keys across 15 languages. All five localization tool
  tests passed, and compiled resource tests cover the new per-app copy in every translated locale.
  Eight opt-in offscreen renders of the real Apps list/detail views were generated and visually
  checked in English/Simplified Chinese and light/dark appearances, with isolated settings/history
  fixtures rather than edits to the user's preferences or encrypted archive.
- Strict SwiftLint on changed Swift files reports the same single inherited
  `implicit_optional_initialization` finding as baseline `a99fc134`, with no new findings.
  `git diff --check` passed. Repeated XcodeGen generation produced identical project bytes.

- Both local model suites ran before and after the final integration in Release with the same
  `gemma-4-E2B.i1-Q6_K.gguf` and seed 42. All 117 continuation and 23 recall cases retained identical
  raw/displayed output, outcome and suppression stage. Quality scores remained 0.882051 and 0.739130
  respectively. These default-settings evals establish compatibility; the dedicated prompt tests
  separately check full app notes, app scoping and both renderer shapes.
- The separate `Cotabby Dev` Release build passed. Its signed candidate matched the installed
  development designated requirement before replacement. The binary timestamp advanced, exactly
  one installed dev process launched, Accessibility/Input Monitoring remained granted, all services
  started and the local runtime reached ready state. Native UI inspection confirmed the Chinese
  Apps list and Obsidian detail page in the real settings window; inherited values and the shared
  shortcut controls rendered correctly. This inspection navigated the UI without editing the user's
  app policies, instructions, shortcuts or history.
- Test logs, xcresult bundles, baseline/integrated eval JSON, UI renders and the verified install
  receipt are retained under gitignored `build/pr842-integration/`. All 827 tracked production/test
  and project/configuration file hashes remained unchanged after validation. Both the current
  repo-scoped `build/DerivedData` and the isolated baseline's `build/DerivedData` were removed and
  their absence verified before completion.

## Scoped translation and model context budgets — 2026-10-16

After reviewing [upstream #845](https://github.com/FuJacob/cotabby/pull/845), the maintainer approved
an adapted target/reference design, starting from Lingrove `43ce5eec`. The inspected upstream draft
head was `1bafbdce5c40981d2ee4f250dfc0e81ce3d3a933`. This work implements that approved design in
Lingrove's existing subsystems; it does not merge the upstream draft wholesale. Incoming-chat OCR,
automatic whole-field selection and Cmd-A replacement from the draft are outside this adoption.
#843 and #673 remain deferred.

Completion and translation now have independent token context preferences saved by effective
backend/model/destination. Local preparation uses the selected window; endpoint settings bound
application input without resizing or claiming the server's capacity. Translation's native planner
counts actual vocabulary and trusted template tokens off MainActor, reserves output and crops only
reference. Endpoint planning uses a disclosed conservative estimate/margin off MainActor. The full
current sentence or explicit selection is never silently cropped. Oversized targets or incomplete
model output are rejected before they can become replacement offers. A larger budget can reserve
more output, up to 32K tokens, instead of inheriting the old fixed output ceiling.

The default reference mode uses only the target. Optional draft reference adds nearest excerpts
from the same editable field; selecting the entire draft makes that whole selection the target.
The model-specific generic/Hy-MT/TranslateGemma task adapter is unchanged without references, and
references never redefine the retained AX replacement range. TranslateGemma's 2K input limit is
shared by native and endpoint paths. Neither learning prompt includes screen OCR, clipboard or
history. Default on-device completion keeps its shipped prompt policy; explicit overrides expand
the existing AX capture and sliding prompt window. Actual capture size travels through snapshots
and optimistic copies. History retains its separate original capture boundary.

Automatic and explicit requests share the existing sentence card, TextKit highlights, lookup and
nonactivating panel. It identifies sentence versus selection, offers explicit Replace separately
from detail expansion, and reuses the existing AX replacement service. A versioned single-write
transaction survives cancellation until verification settles. Changes to text, selection, field,
IME state, model, reference mode, language or budget invalidate old offers. Failure expands source
and translation copy recovery, blocks retry, and never automatically restores or overwrites text.
Explicit capture failures have an error-only card rather than a silently consumed command.

All editable shortcuts now live in Settings → Shortcuts, including translation replace/details
and per-app overrides. A pane-owned transient recording state ensures that starting a recorder
in any section retires the previous one; late cleanup cannot clear the newer owner. Writing/App
detail provide summaries and navigation; onboarding shows read-only keycaps. Existing saved conflicts
are shown when translation is enabled, and the runtime
arbiter checks the current app. KeybindRow, KeyRecorderView, PerAppShortcutRowsView, native form
scaffolds and row labels are reused. App behavior reset preserves key overrides. Pending budget
text-field edits cannot commit into a newly selected power/model profile. New copy is translated
into all 15 supported languages in `Learning.xcstrings`; `Localizable.xcstrings` is unchanged.

Two independent GPT-6 Luna reviewers with max reasoning performed read-only behavior/budget and
preview/input/UI reviews, as requested. The fixes include equal-budget model identity publication,
actual AX capture expansion, copied truncation metadata, existing shortcut-conflict feedback,
manual error feedback, source-copy recovery and document-scoped replacement transaction state.
Their final reviews found no remaining P1/P2 after those corrections.

Validation on Xcode 26.5 / Apple Silicon with the prepared pinned inference workspace:

- Final Release `build-for-testing` passed; all 353 targeted test items passed without skips.
  The final complete run executed 3174 items: 3138 passed, 35 environment/opt-in skips and one
  failure in the inherited aria2 fake-process progress wait. The failure is
  `Aria2DownloadServiceTests.test_cancelStopsRunningProcessAsCancelled` at the pre-cancellation
  fixture wait, also seen in the preceding adoption's validation. All 14 aria2 items passed when
  isolated. No aria2 production or fixture code was changed. Unsigned test-host AX checks account
  for 20 of the environment skips; these results are not presented as a completely passing suite.
- Both Release model eval suites passed with the same Gemma GGUF and seed 42 as baseline
  `43ce5eec`. All 117 continuation and 23 recall cases retained identical raw/displayed output,
  outcome and suppression stage. Quality scores remained 0.882051 and 0.739130. Native Hy-MT2 1.8B
  and TranslateGemma 4B checks generated 12 target-only translations, including explicit selection,
  whole-draft selection and both language directions; each also planned a large cropped reference
  while retaining the complete target.
- Actual SwiftUI settings/card views were rendered and visually checked in English/Simplified
  Chinese and light/dark appearances, using isolated settings fixtures. The final Chinese render
  run passed all five items. Both String Catalogs validate: 1144 source keys across 15 languages;
  all five localization tool tests passed. The common catalog remains byte-identical to baseline.
- Normal SwiftLint on changed production Swift passed with zero errors and 70 warnings; strict
  lint is not clean. `git diff --check` passed and repeated XcodeGen generation produced identical
  project bytes. All 845 production/test/project/configuration hashes matched the final validated
  source after testing.
- The separate `Cotabby Dev` Release build passed and replaced the installed development app
  only after matching its existing designated signing requirement. The binary timestamp advanced,
  exactly one installed dev process launched, Accessibility/Input Monitoring remained granted,
  all services started and the completion runtime reached ready state. All 18 existing shortcut
  preference values were semantically preserved; the inherited startup store only reordered the
  keys in its encoded per-app JSON. Native settings acceptance on this installed binary verified
  the Chinese unified shortcut rows, exclusive recording handoff across global/translation/app
  sections, Escape cancellation, Writing navigation and App-detail navigation retaining Obsidian
  as the selected app. App detail exposes a read-only shortcut summary. Completion/translation
  panes independently displayed their 4096/8192-token defaults. All 18 shortcut preference values
  remained semantically unchanged across this interaction; no budget values were edited.
- Logs, xcresult bundles, source/eval comparisons, rendered UI, native translation outputs and
  the signed install receipt are retained under gitignored `build/model-context/`. Repo-scoped
  `build/DerivedData` was removed and its absence verified before completion.

## Settings background-update performance (2026-10-16)

This follow-up starts from `18ef0fbb` and isolates settings rendering from unrelated live service
updates. `SettingsCoordinator` owns a `SettingsAttentionModel` that combines incoming permission,
engine configuration and runtime failure/availability values into a deduplicated category warning
set. The container observes that projection and navigation. Individual destination panes keep their
own subscriptions, so their controls and live metrics continue updating. This avoids rebuilding the
whole split view for every request counter, download notification or model search edit.

The real SwiftUI container was measured in a Release fixture with isolated preferences and inactive
services. Each source published eight updates while Writing was visible:

| Source | Baseline container / Writing bodies | Final container / Writing bodies |
| --- | ---: | ---: |
| Suggestion quality counter | 8 / 8 | 0 / 0 |
| Performance metric | 8 / 8 | 0 / 0 |
| Download notification | 8 / 8 | 0 / 0 |
| Model search query | 8 / 8 | 0 / 0 |

Positive checks also verify that changing Writing's own settings rebuilds Writing, and visible
Performance metrics rebuild Performance without rebuilding the container. Endpoint warnings read
the newly published URL/model value and clear on recovery. Re-selecting a category avoids an
identical selection publication while retaining search highlights, model-task and app targeting.

The existing pane scaffold, components, scrolling, search arrival and macOS 14 detail identity
workaround are retained. Native switching measurements did not establish a stable first-entry
latency improvement; this change claims reduced background invalidation, not an eliminated sidebar
switching delay. AX polling, host publication probes, inference, prompting and model settings are
unchanged. Sampling did not establish that AX polling caused the settings symptom.

`-cotabby-debug -cotabby-settings-performance` enables optional body counts and handled selection to
first nonzero AppKit layout logs. Navigation generations reject stale A → B → A layout callbacks.
The diagnostics record no field text, mount no probe during normal launches, and do not measure
mouse-event queueing, final stable layout or pixel presentation. Fixture wall times include explicit
settling and are not CPU measurements. Local receipts are retained in gitignored
`build/settings-performance/`.

Validation on Xcode 26.5 / Apple Silicon:

- The final Release `build-for-testing`, opt-in benchmark and all 292 targeted items passed.
  The final full run passed 3160 items with 21 environment/opt-in skips and no failures (3181
  total). A preceding run and isolated retry hit the inherited aria2 fake-process progress wait;
  the final complete run passed that item. Both its fixture and production source are unchanged.
- Strict SwiftLint on changed production Swift passed with zero findings. Changed tests have no
  lint errors and one closure-style warning. Both catalogs still validate: 1144 keys, 15 languages.
- Two independent GPT-6 Luna reviewers with max reasoning found no remaining P1/P2 in the final
  subscription, lifecycle, navigation and diagnostics changes.
- Native acceptance on the installed final Dev binary verified Writing scrolling, its translation
  model link (8192-token budget), App → Obsidian → Shortcuts retaining Obsidian, and live Performance
  readings. Twelve same-window transitions after 24 warm-up transitions gave handled-selection to
  first-layout medians of 294.537 / 250.711 / 313.278 ms for General / Appearance / Writing;
  baseline was 215.097 / 247.634 / 297.666 ms. Samples were three / three / six per version in
  separate time periods, so these establish no first-entry speedup and are not display latency.
- Search category navigation worked, but automatic scrolling to the target did not: searching
  `ghost text size` and pressing Return entered Appearance while leaving the target below the
  viewport. The scaffold is byte-identical to `18ef0fbb` and search entry/anchors were not changed;
  the evidence points to an existing nested-scroll issue. This is recorded separately and is not
  presented as passing native search-position acceptance.
- The separate `Cotabby Dev` Release build was installed after matching the existing designated
  signing requirement; its binary timestamp advanced. Normal startup was restored with the profiling
  switch absent and exactly one installed dev process. Accessibility and Input Monitoring remained
  granted, all services started and the completion runtime reached ready state. Repeated XcodeGen
  output was identical and all 849 validated production/test/project/configuration hashes matched.
- Repo-scoped `build/DerivedData` was removed and its absence verified after validation. The
  benchmark, xcresult bundles, source hashes, native traces and signed install receipts remain
  under gitignored `build/settings-performance/`.

## Settings search target scrolling (2026-10-16)

The user requested fixing the separate search-position defect recorded above after performance
commit `13b32702`. The shared `SettingsPaneScaffold` now lets its grouped Form own the visible
scroll viewport, instead of placing a second ScrollView around it. Existing Form sections, rows,
callout rendering and target highlights are reused. A callout is the first section of the same
document, with standard Form insets.

Search reveals use one SwiftUI task keyed by the current target, including initial pane arrival
and same-pane searches. A new target or pane disappearance cancels pending work. After the existing
80 ms layout allowance it scrolls once; the previous delayed second attempt is removed so it cannot
pull the viewport back after the user starts scrolling. This fixes target visibility; it does not
claim a measured first-entry performance improvement.

Validation on Xcode 26.5 / Apple Silicon:

- Release `build-for-testing` passed. All 293 targeted items passed, including the four real-AppKit
  Form combinations (callout present/absent × initial/later search). They assert one scroll owner,
  actual movement to the distant target and a later search back toward the beginning.
- The final complete run passed 3161 items, with 21 environment/opt-in skips and no failures (3182
  total). Repeating the background benchmark retained zero container/Writing bodies for each of
  the four groups of eight unrelated updates.
- The real shared callout/Form rendering was inspected in light and dark appearances. Strict
  SwiftLint on the changed production and test files passed with zero findings. The independent
  GPT-6 Luna max review found no P1/P2 after removing the delayed second scroll.
- The separately built Dev Release was signed against the existing installed requirement and
  installed with an advanced binary timestamp. Native Chinese settings acceptance verified the
  original `ghost text size` path reaches and highlights Match Original Text Size, a same-pane
  `fade in` search scrolls back to the upper target, and the Writing `languages` result scrolls to
  the bottom section. Manual scrolling back up remained available. No setting values were edited.
  One normal dev process remained, profiling was disabled, permissions remained granted and the
  completion runtime reached ready state. Repeated XcodeGen output was identical and all 850
  validated production/test/project/configuration hashes matched.
- Repo-scoped `build/DerivedData` was removed and its absence verified. Test results, UI renders,
  benchmark, native acceptance and signing receipts remain under gitignored
  `build/settings-search-scroll/`.
