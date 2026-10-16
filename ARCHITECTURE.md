# Lingrove Architecture

This is the ten-minute maintainer map for Lingrove. It explains the product loops, ownership
boundaries, reliability rules, and the best files to read before changing behavior. It is intentionally
a roadmap rather than an encyclopedia.

## What Lingrove Is

Lingrove has two equally core capabilities: inline autocomplete and language learning in other
applications. Internal source/module names remain Cotabby during migration. The autocomplete loop is:

1. Find the focused editable field through macOS Accessibility.
2. Observe global keyboard input without taking focus.
3. Gate work using permissions, field capability, settings, and runtime state.
4. Build a bounded request from caret text and optional context.
5. Generate through Apple Intelligence, an in-process llama.cpp model, or a user-configured
   OpenAI-compatible endpoint.
6. Normalize the result into a safe short continuation.
7. Render inline ghost text or a mirror card near the caret.
8. Reconcile typing against the active suggestion and insert accepted chunks through configurable
   shortcuts.

The language-learning loop reads the current sentence or selected text, translates it using its
configured local model or endpoint, optionally recognizes learning units and aligns source/target
chunks, and presents correspondence and dictionary lookup beside the field. Its coordinators share
the app-lifetime dependency graph and input/focus boundaries with autocomplete, while owning their
own task identities, cancellation, runtime profiles, and presentation state.

The product is local-first, not unconditionally offline. Apple Intelligence and the bundled
open-source path run on the Mac. An endpoint can be loopback, on the local network, or a public HTTPS
service; when selected, the bounded request is sent to that server.

## Architectural Constraints

These rules explain most of the structure:

- There is one app-lifetime dependency graph. Views never create process-wide services.
- Accessibility state is eventually consistent and app-specific. Every async result can be stale.
- Generation, presentation, and insertion fail closed for secure and unsupported fields. Early
  acquisition has a current secure-field caveat described under privacy below.
- User text and optional context are bounded before generation.
- On-device work stays local unless the user explicitly selects an endpoint engine.
- Global input is observed in a fail-open way; Cotabby consumes only events it successfully handles.
- MainActor owns UI, published state, AppKit, and most AX access. OCR, downloads, and generation do
  not block it.
- Mutable native llama state is explicitly serialized and released before process teardown.
- Pure policy belongs outside coordinators so the state machine remains testable.

## Repository Map

- [Cotabby/App](Cotabby/App): application entry point, composition root, lifecycle, and coordinators.
- [Cotabby/UI](Cotabby/UI): SwiftUI and AppKit-facing presentation for settings, onboarding, menus,
  previews, and user surfaces.
- [Cotabby/Services](Cotabby/Services): side-effectful boundaries for AX, event taps, insertion,
  capture/OCR, generation, downloads, permissions, updates, and AppKit panels.
- [Cotabby/Models](Cotabby/Models): shared values, settings, states, configuration, and protocol
  contracts.
- [Cotabby/Support](Cotabby/Support): deterministic rules, prompt rendering, normalization,
  reconciliation, layout, and low-level bridging helpers.
- [CotabbyTests](CotabbyTests): unit tests and microbenchmarks, with emphasis on pure Support and
  Models behavior.
- CotabbyInference: the llama.cpp Swift wrapper consumed from an external SwiftPM package; native
  code is not vendored here. The mid-word anchoring needs a required-prefix constraint that is not in
  `FuJacob/cotabbyinference` main yet, so the package resolves from the `feat/required-prefix` branch
  of the `Mason363/cotabbyinference` fork that adds it; the pin returns to main once it lands there.

[SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) expands this map into the canonical nested source and test
layout. Child folders name stable responsibilities inside a subsystem; they do not create Swift
namespaces or additional build targets.

Folder names describe the dominant responsibility, not the UI framework. Cotabby/UI contains
SwiftUI views, while AppKit panel/window controllers live mostly under Cotabby/Services/Presentation or app
coordinators because they own process-level presentation behavior.

## End-to-End Data Flow

~~~text
CGEvent and focus poll
  -> FocusTracker
  -> FocusSnapshotResolver + AXTextGeometryResolver
  -> FocusSnapshot
  -> SuggestionCoordinator
       -> availability and native correction
       -> debounce + current work identity
       -> SuggestionRequestFactory
            -> bounded AX / surface / clipboard / visual / user context
       -> SuggestionEngineRouter
            -> Apple | in-process llama | OpenAI-compatible endpoint
       -> SuggestionTextNormalizer + seam guards
       -> SuggestionInteractionState
       -> SuggestionOverlayPresenter -> OverlayController
  -> typing reconciliation or configured acceptance
  -> SuggestionInserter
  -> host AX publication check and next prediction
~~~

The request is immutable after generation begins. Engines do not reach back into live AX state.
Before a partial, final, or insertion applies, the coordinator verifies current work identity, focus,
content signatures, settings continuity, and session state.

## Lifecycle and Ownership

Read these first:

1. [CotabbyApp.swift](Cotabby/App/Core/CotabbyApp.swift)
2. [AppDelegate.swift](Cotabby/App/Core/AppDelegate.swift)
3. [CotabbyAppEnvironment.swift](Cotabby/App/Core/CotabbyAppEnvironment.swift)

| Owner | Responsibility | Lifetime |
| --- | --- | --- |
| CotabbyApp | SwiftUI scenes, MenuBarExtra, AppDelegate bridge | Process |
| CotabbyAppEnvironment | Construct the shared object graph and retain graph-internal subscriptions | Process |
| AppDelegate | Start/stop services and retain lifecycle-driven subscriptions | Process |
| Coordinators | Orchestrate one product surface across services | App or window |
| Services | Own one side effect, OS boundary, or mutable subsystem | Injected |
| Views | Render shared state and send narrow user intents | SwiftUI/AppKit surface |

AppDelegate starts the selected runtime, focus polling, input monitoring, updates, suggestion
coordination, inline commands, and onboarding after launch. It stops new work before tearing down
global taps, polling, and native resources at termination. Production service startup is skipped in
the XCTest host.

CotabbyAppEnvironment also owns important subscriptions: focus cadence, global-toggle tap binding,
power-profile application, engine/model selection, and endpoint connection invalidation. AppDelegate
owns permission reactions, engine runtime start/stop, overlays, model-directory refresh, and
process-lifecycle behavior. Both retain subscriptions because both own different relationships.

[SuggestionSettingsModel.swift](Cotabby/Models/Settings/SuggestionSettingsModel.swift) is the
individually published UI-facing source of app behavior. Its
[SuggestionSettingsData.swift](Cotabby/Models/Settings/SuggestionSettingsData.swift) projection groups
the same values by product domain without replacing the existing API. The immutable snapshot used by
the pipeline is derived from those domains. [SuggestionSettingsStore.swift](Cotabby/Support/Settings/SuggestionSettingsStore.swift)
keeps the established flat UserDefaults keys stable; endpoint credentials live in Keychain.

SettingsCoordinator also owns `SettingsAttentionModel`, a deduplicated projection of required
permissions, the selected engine/endpoint configuration and runtime availability/failures. The
settings container observes this warning set and its own navigation, rather than every source
service. Destination panes retain their direct subscriptions: background request counters, model
diagnostics or download progress update the relevant pane without rebuilding Writing or the whole
split view. Incoming `@Published` values feed the projection directly, avoiding willSet-era rereads.
Repeated selection of the same category does not republish an identical value; the existing
macOS 14 detail identity workaround and in-pane search/highlight/hover animations remain.

Each completion/learning settings owner also retains a bounded `ModelContextIdentityCache` for
canonical destination strings. Its two slots retain the current local and nonlocal identities;
budget values remain live lookups in the existing task-owned maps. Completion's Combine projection
passes incoming values explicitly to preserve `@Published` willSet correctness. Runtime preparation
supplies its actual model filename rather than relying on the UI's mirrored selection. A focus
resolve freezes its capture-window value once and passes that Int through all candidate reads,
slicing and truncation metadata, without changing the requested window or polling cadence.

`SettingsPaneScaffold` gives search's `ScrollViewReader` one grouped Form scroll owner. Nesting an
outer ScrollView around the Form allowed category navigation to succeed without revealing the row
in the visible viewport. Shared callouts are the first Form section and scroll with its controls.
A task keyed by the highlighted item waits for initial layout and reveals once; replacement or
disappearance cancels it. There is no delayed repair that can pull back a user's manual scroll.

`SettingsRenderDiagnostics` is optional measurement infrastructure. Launching with
`-cotabby-debug -cotabby-settings-performance` logs body evaluations and handled selection to first
nonzero AppKit layout, without text content. A generation token rejects obsolete layouts, including
rapid A → B → A navigation. It does not measure input-event queueing, stable layout or display
presentation. With the switch absent, no layout probe is mounted. The opt-in Release settings
benchmark uses isolated preferences and inactive services; its cold-window measurements and
background-publication counts complement, rather than replace, native same-window navigation.

## Suggestion State Machine

Read the coordinator in this order:

1. [SuggestionCoordinator.swift](Cotabby/App/Coordinators/Suggestion/SuggestionCoordinator.swift)
2. [SuggestionCoordinator+Lifecycle.swift](Cotabby/App/Coordinators/Suggestion/SuggestionCoordinator+Lifecycle.swift)
3. [SuggestionCoordinator+Input.swift](Cotabby/App/Coordinators/Suggestion/SuggestionCoordinator+Input.swift)
4. [SuggestionCoordinator+Prediction.swift](Cotabby/App/Coordinators/Suggestion/SuggestionCoordinator+Prediction.swift)
5. [SuggestionCoordinator+Acceptance.swift](Cotabby/App/Coordinators/Suggestion/SuggestionCoordinator+Acceptance.swift)

The coordinator owns orchestration plus active suggestion and presentation state. It delegates rules
and cohesive mutable sub-state to smaller boundaries:

- [SuggestionAvailabilityEvaluator.swift](Cotabby/Support/Suggestion/Request/SuggestionAvailabilityEvaluator.swift):
  pure permission, settings, focus, and runtime gates.
- [SuggestionRequestFactory.swift](Cotabby/Support/Suggestion/Request/SuggestionRequestFactory.swift): pure bounded
  request construction and the selected backend's developer-debug prompt payload. Nothing is generated
  with the caret inside a token ([CaretTokenPosition.swift](Cotabby/Support/Suggestion/Request/CaretTokenPosition.swift)),
  and on the llama path a request made mid-word is anchored at the word boundary
  ([WordBoundaryAnchorPolicy.swift](Cotabby/Support/Suggestion/Request/WordBoundaryAnchorPolicy.swift)): the partial
  word leaves the prompt (so its last token is a whole word) and the engine is handed the boundary whitespace plus the
  typed letters as a required prefix it masks every inconsistent token against, so the model finishes the word the
  user started; the normalizer shows only the untyped remainder. The word-count preset also bounds the result
  ([SuggestionLengthPolicy.swift](Cotabby/Support/Suggestion/Output/SuggestionLengthPolicy.swift) trims to the
  preset's upper bound at a clause boundary; the decoder's sentence stop waits for its lower bound).
- [SuggestionWorkController.swift](Cotabby/Services/Suggestion/State/SuggestionWorkController.swift):
  debounce/generation tasks and monotonically increasing work IDs.
- [SuggestionInteractionState.swift](Cotabby/Services/Suggestion/State/SuggestionInteractionState.swift):
  active session, materialized context, consumed prefix, and known post-insertion AX lag.
- [SuggestionStreamingState.swift](Cotabby/Support/Suggestion/Streaming/SuggestionStreamingState.swift): latest-wins
  partial coalescing, one scheduled drain, and monotonic rendered-text state.
- [PostExhaustionAcceptanceState.swift](Cotabby/Support/Suggestion/Session/PostExhaustionAcceptanceState.swift):
  pure state for the bounded Tab-ownership window while an exhausted tail regenerates.
- [SuggestionSessionReconciler.swift](Cotabby/Support/Suggestion/Session/SuggestionSessionReconciler.swift): type-through,
  acceptance, and live-host reconciliation.
- [SuggestionTextNormalizer.swift](Cotabby/Support/Suggestion/Output/SuggestionTextNormalizer.swift): backend-independent
  cleanup, echo removal, whitespace policy, trailing-text deduplication, word-boundary reconciliation, and
  unsafe-output rejection. [CompletionContentPolicy.swift](Cotabby/Support/Suggestion/Output/CompletionContentPolicy.swift)
  then drops punctuation-only output, closing punctuation after a typed space, forum/chat scaffolding or
  meta-responses about the prompt, a word sequence looping back to back, and text lifted verbatim from what the
  user just wrote.

A native correction path runs before model generation. NSSpellChecker and bundled SymSpell indexes
can suppress completion while a likely typo is forming, offer a green atomic replacement, or apply
an opt-in automatic fix after Space. A word the checker can still complete ("apprec") is treated as
in progress rather than misspelled, so the continuation finishes it.

Engines can stream cumulative partials. SuggestionStreamingState coalesces token-rate callbacks into
latest-wins UI work, accepts only monotonic extensions, and lets a displayed partial become an active
accept-ready session. The coordinator still owns scheduling and presentation. The final result
remains authoritative and can replace or suppress provisional text.

Normal sessions support exact type-through, word or phrase acceptance, full-tail acceptance, CJK-aware
segmentation, punctuation handling, optional trailing space, and speculative generation after final
acceptance. When rapid Tab presses cross the exhausted-tail regeneration gap,
PostExhaustionAcceptanceState can queue at most one unseen accept and has a generation-keyed backstop
that returns Tab ownership to the host. Corrections commit atomically rather than exposing partial
acceptance.

## Focus and Accessibility

Read:

1. [FocusTracker.swift](Cotabby/Services/Focus/FocusTracker.swift)
2. [FocusSnapshotResolver.swift](Cotabby/Services/Focus/Resolution/FocusSnapshotResolver.swift)
3. [FocusModels.swift](Cotabby/Models/Focus/FocusModels.swift)
4. [AXTextGeometryResolver.swift](Cotabby/Services/Focus/Resolution/AXTextGeometryResolver.swift)
5. [AXHelper.swift](Cotabby/Support/Accessibility/AXHelper.swift)

FocusTracker uses timer polling as the authoritative source because AX notifications are inconsistent
across AppKit, browsers, Electron, and custom editors. Activity resets the cadence; idle unchanged
state backs it off. Input and acceptance paths may request an explicit fresh capture, but do not trust
event payloads as complete field state.

FocusSnapshotResolver finds a usable editable candidate, blocks secure/unsupported surfaces (and
Mail's compose header rows, [MailHeaderFieldDetector.swift](Cotabby/Support/Accessibility/MailHeaderFieldDetector.swift):
Tab is the way from To to Subject to body there, not an accept; and single-line sign-in and
verification fields, [CredentialFieldDetector.swift](Cotabby/Support/Accessibility/CredentialFieldDetector.swift):
a completion there is a guess at the user's identity), bounds
text on both sides of the caret, resolves the focused process, and publishes stable domain values.
Chromium/Electron require accessibility priming, cursor hit-test recovery, and out-of-process iframe
handling. All fallbacks are revalidated and yield to a valid system-focused element.

AXTextGeometryResolver tries direct range bounds, browser text-marker bounds, a nearby measured
character, child static-text runs, and field-frame estimation. Geometry is labeled exact, derived,
estimated, or layoutEstimated; presentation uses that quality rather than pretending every rectangle
is equally trustworthy.

AX is synchronous cross-process IPC on MainActor. Deep walks are gated, cached, bounded, and
throttled. Calendar has a narrow capture guard because enumerating its transient editor can dismiss
the editor. Async consumers carry focus/content signatures instead of relying on AX element identity
alone.

## Global Input and Insertion

[InputMonitor.swift](Cotabby/Services/Input/InputMonitor.swift) owns three event-tap responsibilities:

- A steady listen-only observer for typing, deletion, navigation, and pointer activity.
- A conditional consuming tap while a suggestion or inline-command capture needs interception.
- A separate consuming tap for the configured global-toggle shortcut.

The conditional tap consumes a matching key only after the owning coordinator succeeds. Stale taps,
missing overlays, rejected sessions, and revoked permission fail open so the host receives the key.
Word/phrase and full-tail acceptance have independent configurable key/modifier bindings.

[InputSuppressionController.swift](Cotabby/Services/Input/InputSuppressionController.swift) marks and
counts Cotabby-generated events so insertion does not re-enter the typing pipeline.

[SuggestionInserter.swift](Cotabby/Services/Suggestion/SuggestionInserter.swift) normally posts short
Unicode key events without touching the clipboard. Active IME composition uses a clipboard paste
commit. A default-off policy can also paste long or multiline chunks. Paste tries the target app's
Accessibility Paste menu item before synthetic Command-V and restores every pasteboard representation
unless newer user clipboard activity wins.

Replacement sessions delete their validated literal run before inserting correction, emoji, or macro
text. Posting events is not treated as proof of success; the later AX snapshot is reconciled.

## Engines and Prompting

[SuggestionEngineRouter.swift](Cotabby/Services/Runtime/SuggestionEngineRouter.swift) selects one of:

- [FoundationModelSuggestionEngine.swift](Cotabby/Services/Runtime/AppleIntelligence/FoundationModelSuggestionEngine.swift)
  for Apple Intelligence. It uses the framework's instructions channel, streams cumulative partials,
  and keeps a one-use compatible prewarmed session. Unsupported language/locale can fall back to llama.
- [LlamaSuggestionEngine.swift](Cotabby/Services/Runtime/Llama/LlamaSuggestionEngine.swift) for an in-process
  GGUF base model through CotabbyInference. [LlamaRuntimeManager.swift](Cotabby/Services/Runtime/Llama/LlamaRuntimeManager.swift)
  publishes state; [LlamaRuntimeCore.swift](Cotabby/Services/Runtime/Llama/LlamaRuntimeCore.swift) owns native
  pointers, tokenization, KV-cache reuse, prefill, sampling, abort, and shutdown.
- [OpenAICompatibleSuggestionEngine.swift](Cotabby/Services/Runtime/OpenAICompatible/OpenAICompatibleSuggestionEngine.swift)
  for completion/chat APIs and SSE streams. The default is loopback Ollama at
  http://127.0.0.1:11434/v1; LAN and public HTTPS endpoints are supported, while insecure public HTTP
  is rejected.

`NativeLlamaSession` is the common native ownership boundary used by `LlamaRuntimeCore` and each
`LearningLocalRuntime`. Each owner constructs a separate session/engine. `NativeRuntimeWorkGate`
serializes allocation, vocabulary/cache access and decoding, closes admission before release,
cancels only the live operation/sequence identity, and drains work before freeing native state.
Learning leases are checked both on admission and after an idle release waits for the current work;
a new claim makes that old release obsolete. No prompt, sampler policy or KV bookkeeping lives in
the common session. `LlamaRuntimeCore` retains its autocomplete prefix/sequence/fingerprint policy.
Heavy work runs away from MainActor; these serialized native owners are not Swift actors.

The session's allocation identity includes the standardized model URL, GPU layer request, context
window and batch size. Failed loading clears the identity and partial allocation so the same file
can be retried. The autocomplete shutdown timeout is a drain grace period, never permission to free
live pointers. Already-started native loading has no safe abort API and can delay termination.

The app and CotabbyInference intentionally expose one live autocomplete sequence. The package uses
one llama.cpp sequence slot and a changing external ID to reject stale work after a reset; the Swift
generation loop remains the single owner of the output-token budget.

Autocomplete heals the final prompt token when its printable bytes exactly match the text at the
caret. The native sampler replays those bytes under a vocabulary-prefix constraint, allowing a
longer token to finish an unfinished word without forcing every complete word to continue.
[TokenHealingBuffer.swift](Cotabby/Support/Runtime/TokenHealingBuffer.swift) removes replay bytes and
holds incomplete UTF-8 until it can publish lossless cumulative text. The extra replay allowance is
bounded separately from visible generation. Special tokens and oversized pieces take the ordinary
continuation path; no model weights or tokenizer files are modified.

Cache reuse is based on actual native restoration, not a permanent model-family blacklist. Ordinary
attention can trim its suffix; recurrent/hybrid or sliding-window memory uses one bounded partial
state checkpoint near the prompt tail, with at most eight tokens replayed. A miss falls back to a
cold prompt. Checkpoints live only in memory, are size-capped, and are cleared with the sequence.
Sampler history is rebuilt from the current prompt so discarded suggestions do not affect the next
request. Native memory may retain a generated tail between requests; the app tracks only the
validated prompt prefix and restores exactly the shared prefix before the next decode. Deferring
restoration avoids replaying the same tail both after generation and again on the next keystroke.
Cancellation targets a request identity as well as the native sequence, preventing a late
cancel from aborting a later request that reused the same sequence.

[BaseCompletionPromptRenderer.swift](Cotabby/Support/Prompting/BaseCompletionPromptRenderer.swift) renders a
base-model text continuation with optional budgeted context and the caret prefix last. It does not
wrap a base GGUF in an instruction conversation. The writer's name enters that preface only when
the caret follows a valediction ([SignOffCue.swift](Cotabby/Support/Prompting/SignOffCue.swift)):
named in every prompt, a base model introduced the writer at openings ("Hi, I'm Jacob"), addressed
them as the recipient, and copied the preface wording into the ghost; at a sign-off the name is the
one token wanted. The first-launch name is the Mac account's full name, never a placeholder. [FoundationModelPromptRenderer.swift](Cotabby/Support/Prompting/FoundationModelPromptRenderer.swift)
keeps Apple's instruction-shaped prompt separate.

The llama context window is 4096 tokens. `SuggestionConfiguration.derivedLlamaPromptTokenBudget`
subtracts the output ceiling and a safety margin from it, so the prompt budget (3982 tokens) can never
silently drift from the KV capacity the model actually has. The prefix caps (14000 characters / 2400
words) are sized to bind at roughly the same point: raising one without the other does nothing,
because whichever is smaller truncates the prefix to its tail and drops the early text that carries
the setup. Both were doubled together after the recall eval showed facts stated more than ~1900
tokens before the caret were invisible to the model.
The request window and section allocator preserve the prefix's spaces, line breaks, and indentation.
Multiline output cleanup also preserves the leading space needed to join a new word at the caret.
Bounded right-of-caret text is descriptive reference material before the prefix, not invented
fill-in-the-middle control tokens. This added suffix section is local-only: the endpoint renderer
does not receive it. Optional user-authored notes retain their existing budgets and settings; no
automatic writing-history collection is introduced.

Prewarm is opportunistic and goes only to the selected backend. Context reset reaches every backend.
The local runtime is loaded only for the Open Source engine and is released when switching to Apple
or endpoint mode so mapped weights and Metal buffers do not stay resident unnecessarily.

Two measurements happen at presentation time rather than in the focus resolver, because they read
the host's pixels (Screen Recording) and are asynchronous:

- [HostBaselineCalibrator.swift](Cotabby/Services/Presentation/HostBaselineCalibrator.swift) finds
  the painted baseline on the caret's line. A reading is accepted only if the letter bodies it was
  read from are the right size to be a line of this font (`describesPlausibleBodies`: body rows
  within 0.45x-1.35x the font's ascent) and the answer sits within the policy window; otherwise the
  policy baseline, the font's own metric, stands. Measured in a real session, one field's lines read
  12.0 and 15.0 for the same font: both passed the policy window, and the 12.0 lines put the ghost
  three points high. The gate is on the measurement, not a vote across lines: an earlier attempt to
  let one line's reading speak for the whole field adopted a bad first reading and made every line
  wrong instead of one.
- [PixelCaretLocator.swift](Cotabby/Services/Presentation/PixelCaretLocator.swift) places the caret
  inside a paragraph the host exposes only as one union-framed run with no answer to any bounds
  query (Obsidian's CodeMirror), and in a single-line field whose caret Accessibility could only
  estimate (Chrome's address bar answers every bounds query with a zero rect): there the field's
  frame is the line and the caret is where its ink ends, so the ghost goes inline instead of to the
  card. A single-line paragraph run gets the same treatment, read in its own line box widened to
  where its text now ends: its proportional caret landed 3pt off in Obsidian, and the full
  padding read its neighbours' ink as lines of its own. A capture cannot see the run under
  Cotabby's own ghost (the excluded window
  comes back black), so while the ghost is up a re-anchor for text typed since the run's last
  capture carries that caret forward by the typed advance (`extrapolatedMeasurement`), and
  anything else takes the ghost down for the read; re-anchoring to the Accessibility estimate
  instead put the ghost four lines up on every other keystroke.
  [InkCaretAnalyzer.swift](Cotabby/Support/Presentation/Geometry/InkCaretAnalyzer.swift)
  finds the inked lines in a capture of the run's frame; the caret is the end of the last line, the
  pitch is the distance between line tops, and the line box is the frame height less the pitch per
  extra line. Only a caret at the end of its paragraph is measured; a caret inside one keeps the
  card. `OverlayController` holds the first presentation for a paragraph text until the capture
  answers (tens of milliseconds) and reuses it for every later presentation of that text.

## Context, Privacy, and Permissions

[PermissionManager.swift](Cotabby/Services/Permission/PermissionManager.swift) tracks:

- Accessibility: required for focus, text, capability, geometry, and insertion validation.
- Input Monitoring: required for global keyboard observation and acceptance interception.
- Screen Recording: optional, used only for screenshot-derived context.

Context sources are independently enabled and bounded: recent AX prefix/trailing text, surface
metadata, user rules/extended context, relevant clipboard content, visual OCR, language, and settings.
[PromptContextSanitizer.swift](Cotabby/Support/Context/PromptContextSanitizer.swift) sanitizes optional text,
and prompt renderers apply per-section budgets.

Whether any of that context survives into the completion is measured, not assumed:
`CotabbyTests/Fixtures/llama-recall-cases.json` hides a fact in each context source (same-field text,
screen OCR, clipboard) and requires the completion to reproduce it. It is reported separately from the
continuation suite because averaging the two lets fluent prose hide a total failure to use context.

[ClipboardContextProvider.swift](Cotabby/Services/Context/ClipboardContextProvider.swift) reads a
fresh bounded value at request time rather than recording clipboard history. Relevance and distillation
policies drop unrelated or excessive content.

Visual context is one field-scoped session:

~~~text
VisualContextCoordinator
  -> WindowScreenshotService (local: focused window; endpoint: original field crop)
  -> ScreenTextExtractor (Vision OCR + line confidence)
  -> OCRTextHygiene
  -> VisualContextExcerptSelector (local: proximity, deduplication, reading order)
  -> bounded sanitized excerpt
~~~

There is no model summarization step and raw screenshots do not enter prompts. Missing Screen Recording
produces an explicit unavailable state without disabling text-only autocomplete. Debug screenshot/OCR
artifacts exist only under the explicit debug launch mode.

Local engines refresh context three seconds after the previous capture finishes, while generation
continues using the last ready excerpt. Every refresh rechecks focus, permissions and eligibility;
unchanged pixels reuse OCR and unchanged excerpts do not trigger generation. Local selection admits
up to 4,000 characters, additionally constrained by estimated-token budgets and caret-prefix priority.
The endpoint retains its original crop, focus-only lifecycle, 1,500-character excerpt and 500-character
prompt section. Increasing local context does not opt users into broader network transmission.
Local excerpts use confidence/line hygiene without the legacy English token whitelist, preserving
recognized names, ordinary words, dates and amounts instead of silently stripping them.

Secure fields cannot schedule generation, show a suggestion, accept text, or open an inline command,
so their context cannot flow into an engine request. VisualContextCoordinator also rejects secure
fields before starting screenshot/OCR work. FocusSnapshotResolver still creates a bounded AX context
before marking a secure field blocked; that lower-level acquisition remains separate privacy debt.

Endpoint credentials are stored in Keychain. A remote endpoint receives its bounded, legacy-scope
request; its privacy scope must remain visible in settings and documentation.

Typing history (Settings → Context → Typing History) is the one store of the user's writing that
outlives its field. Both of its switches are off by default. When recording is on,
`TypingHistoryStore` keeps the text of fields where Cotabby is active (the same
`SuggestionAvailabilityEvaluator` rule as suggestions; never secure fields, terminals, or excluded
apps), one record per piece of writing (a chat composer that clears after sending yields one record
per message), scrubs secret-like tokens and card numbers (`TypingHistoryScrubber`), and seals the
archive with AES-GCM under a Keychain key that never syncs (`TypingHistoryVault`). Nothing is
written until something is recorded or imported. Delete All removes the file and the key. A Cotypist
`user_inputs.json` export can be imported. Only text that was before the caret is learned from,
because the rest of a field is often a quoted thread. History shapes suggestions in two ways:
`TypingHistoryIndex` adds two short passages of similar past writing to the prompt, and
`TypingHistoryPhraseEngine` answers from `TypingHistoryPhrasePredictor` when history confidently
knows how a phrase ends. Both are on-device only: the provider returns nothing
for the endpoint, the request factory drops examples for it, and the router refuses to send any
request that still carries them.

## Presentation and Sibling Features

[SuggestionOverlayPresenter.swift](Cotabby/Services/Suggestion/SuggestionOverlayPresenter.swift)
decides presentation actions. [OverlayController.swift](Cotabby/Services/Presentation/OverlayController.swift)
owns a reusable borderless non-activating NSPanel and SwiftUI-hosted content.

Automatic presentation uses inline ghost text for exact/derived caret geometry and a mirror card for
estimated/layout-estimated geometry, mid-line editing, or explicit user preference. The overlay can
match host font/color, render corrections distinctly, respect right-to-left and multiline layout,
show an acceptance hint, and advance a partial tail without waiting for noisy AX geometry.

Inline ghost text is built to occupy the pixels the accepted text will occupy:

- [GhostFontResolver.swift](Cotabby/Support/Presentation/Style/GhostFontResolver.swift) picks the
  host's face and size from the field's reported style, from a measured width sample
  ([HostTextMetricsProbe.swift](Cotabby/Services/Focus/Resolution/HostTextMetricsProbe.swift); a host
  that answers no width query gets one from how far its caret moves as the user types,
  [CaretAdvanceSampler.swift](Cotabby/Support/Focus/CaretAdvanceSampler.swift), because a Chromium
  size is CSS pixels that know nothing of page or Electron zoom: the Claude composer reported 14
  and painted 15.4), or from the host's own pixels
  ([TypefaceMatcher.swift](Cotabby/Support/Presentation/Style/TypefaceMatcher.swift))
  when the host names no face. Every capture is snapped to whole device pixels first: a fractional
  edge makes ScreenCaptureKit resample the image and the blurred glyphs correlate with nothing. The pixel match searches size as well as face (a caret-box size is
  a guess: Obsidian's 16px body arrived as 17 and 20, and a face matched at the wrong size is
  confidently wrong), carries every candidate to its exact size (the correlation drops from 0.95
  to 0.66 a sixth of a point away, and a wrong face at a lucky size outscores the true face at a
  grid point), marks down a candidate whose letter bodies are not the height the host
  painted, prefers the system face on a near tie, and declines on too little ink. The size it
  keeps is then fitted to the host's glyph positions alone, the chosen face rendered once and
  stretched about the caret (`advanceFitted`): shape scoring picked Chrome's 18px Georgia at
  18.054, a ghost two device pixels long by a line's end, while the positions put it at 18. An
  Electron host's own bundled faces join the candidates
  ([HostBundledFontRegistry.swift](Cotabby/Services/Presentation/HostBundledFontRegistry.swift)
  registers its TrueType/OpenType files for this process alone), which is how Claude's composer
  can be drawn in Anthropic Sans rather than a stand-in. The calibrator
  keeps one record per field, replaced only when a later strip's winner beats the recorded face on
  that same strip; scores from different strips are not comparable. A reported size stands when the
  caret box is shorter than its glyphs (VS Code's hidden textarea reports 8.5pt boxes for 14pt text).
- [GhostBaselinePolicy.swift](Cotabby/Support/Presentation/Geometry/GhostBaselinePolicy.swift) places
  the baseline the way TextKit or Blink/WebKit would inside the caret box;
  [HostBaselineCalibrator.swift](Cotabby/Services/Presentation/HostBaselineCalibrator.swift) measures a
  web host's painted baseline from a small screen capture (Screen Recording permitting) to recover
  the sub-point line position Accessibility rounds away.
- [GhostTextLayout.swift](Cotabby/Support/Presentation/Geometry/GhostTextLayout.swift) lays rows out
  from the caret with CTTypesetter inside the band
  [GhostWrapBandPolicy.swift](Cotabby/Support/Presentation/Geometry/GhostWrapBandPolicy.swift) derives
  from the element's real frame, one row per host line at the measured line pitch (the probe scans
  single-character bounds for the nearest other line when a host's line APIs give none, as Chromium's
  do; sibling text runs give it for CodeMirror; the caret box height stands in until a field has a
  second line). A row is never placed over the host's own text: with the host's lines below the
  caret the ghost keeps to the caret row and reveals the rest as it is accepted, and a caret with
  characters after it on its line gets the card under the caret from
  [CompletionRenderModePolicy.swift](Cotabby/Support/Presentation/Policy/CompletionRenderModePolicy.swift)
  (an opaque band in the field's background color was tried and read as the suggestion overwriting
  the user's text). Accepted or typed-through text only advances a consumed offset, so remaining
  glyphs never move. [GhostTextPanelView.swift](Cotabby/Services/Presentation/GhostTextPanelView.swift)
  draws the rows with CoreText on a whole-point panel origin.
- While the host shows uncommitted text of its own (macOS inline predictive text, an IME
  composition; [HostMarkedTextPolicy.swift](Cotabby/Support/Input/HostMarkedTextPolicy.swift)) the
  coordinator holds: no generation, no ghost, session kept. Chromium's address bar completes inline
  and leaves the completion selected; the resolver strips that selection from the text and treats
  the completion as the host's marked text, so the hold covers it too and its ink is never read as
  the caret line's end.
- Editors that expose a whole wrapped paragraph as one text run (CodeMirror in Obsidian) get their
  caret from a layout of that paragraph inside the run's own frame at the sibling runs' pitch
  (`WrappedRunAnchor`, laid out by
  [TextLayoutCaretEstimator.swift](Cotabby/Support/Presentation/Geometry/TextLayoutCaretEstimator.swift)
  in the coordinator's repair step); whitespace-only spacer runs never anchor the caret mapping.

[ActivationIndicatorController.swift](Cotabby/Services/Presentation/ActivationIndicatorController.swift) owns
the optional field/caret indicator. [FocusDebugOverlayController.swift](Cotabby/Services/Presentation/FocusDebugOverlayController.swift)
is developer-only and gated by -cotabby-debug.

[InlineCommandCoordinator.swift](Cotabby/App/Coordinators/InlineFeatures/InlineCommandCoordinator.swift) arbitrates
the single input-capture slot between:

- [EmojiPickerController.swift](Cotabby/App/Coordinators/InlineFeatures/EmojiPickerController.swift): colon query,
  lazy catalog/matcher, non-activating picker, recency/frequency ranking, and literal-run replacement.
- [MacroController.swift](Cotabby/App/Coordinators/InlineFeatures/MacroController.swift): slash query and deterministic
  date, random, unit, currency, and arithmetic evaluation through MacroEngine.

Both use pure trigger state machines, stay pinned to one supported focus sequence, and cancel on
focus change or incompatible input. They do not call a language model.

[SettingsCoordinator.swift](Cotabby/App/Coordinators/SettingsCoordinator.swift) and
[WelcomeCoordinator.swift](Cotabby/App/Coordinators/WelcomeCoordinator.swift) own app-lifetime AppKit
windows hosting SwiftUI content. Settings and onboarding observe the shared graph. Hiding the menu bar
icon retains a recovery path to Settings.

## Concurrency and Reliability Rules

- Revalidate after every await that can outlive focus, content, settings, or work identity.
- Treat cancellation as expected lifecycle, not automatically as a backend failure.
- Keep AX and AppKit access MainActor-isolated, but bound synchronous AX work aggressively.
- Use actors or explicit serialization for mutable non-UI state; do not move native pointers across
  an ownership boundary casually.
- Never use only AX element identity as a stale-result guard.
- Keep overlay text and active-session remaining text equal before acceptance.
- Preserve the narrow known-insertion sentinel; general stale AX tolerance hides real divergence.
- Stop new generation and input work before releasing runtime state at termination.

## Safe Change Order

When behavior changes, prefer:

1. Pure policy and helpers in Support.
2. Domain values, state, settings, and contracts in Models.
3. Side-effectful boundaries in Services.
4. Orchestration in App.
5. Presentation in UI.

This is a dependency direction, not a demand to touch every layer. A pure rule should not be added to
SuggestionCoordinator just because that is where its symptom becomes visible.

## Debugging and Validation

Development schemes launch with -cotabby-debug. That enables local privacy-sensitive diagnostics in
addition to unified logging:

- ~/Library/Logs/Cotabby/cotabby.jsonl: structured event stream.
- ~/Library/Logs/Cotabby/llm-io.jsonl: full prompt/completion records.
- ~/Desktop/cotabby-ax-dump.txt: most recent Chrome focus AX tree.
- ~/Desktop/cotabby-debug-screenshots/: retained visual-context capture/OCR pairs.

Every prediction carries a request_id through coordinator, router, engine, and LLM-I/O records. Start
with category focus for field/geometry failures, suggestion for state/acceptance failures, runtime for
model failures, and app for permissions/lifecycle.

[project.yml](project.yml) is the Xcode project source of truth. XcodeGen produces the committed
[Cotabby.xcodeproj](Cotabby.xcodeproj); CI regenerates it and fails when the checked-in project differs.
Debug and Release build the same Cotabby app identity, preference domain, icon, and model storage.
The Debug configuration exposes General > Development > Show Development Debug Overlays (off by
default); AppDelegate forwards that live preference to the presentation controller and polling
diagnostics. The `-cotabby-debug` launch argument controls local diagnostic logging independently.
Keep the signing identity consistent across builds to preserve macOS permission grants.
Swift default actor isolation is MainActor.

Use the narrowest relevant tests first, then broaden. The standard build boundary is:

~~~bash
xcodebuild -project Cotabby.xcodeproj -scheme Cotabby -destination 'platform=macOS' build \
  -derivedDataPath build/DerivedData

xcodebuild -project Cotabby.xcodeproj -scheme Cotabby -destination 'platform=macOS' build-for-testing \
  -derivedDataPath build/DerivedData
~~~

CI independently checks project generation, compilation, tests, and SwiftLint. Pure state machines,
policies, prompt utilities, normalization, and layout logic should receive focused unit coverage.

## Problem-to-File Map

| Symptom or change | Start here |
| --- | --- |
| App startup, duplicate service, shutdown | CotabbyAppEnvironment, AppDelegate |
| Field not detected or wrong app policy | FocusTracker, FocusSnapshotResolver |
| Ghost at wrong location | AXTextGeometryResolver, CompletionRenderModePolicy, OverlayController |
| Suggestion never starts | SuggestionAvailabilityEvaluator, SuggestionCoordinator+Prediction |
| Old suggestion appears | SuggestionWorkController, focus/content signatures |
| Wrong prompt or leaked optional context | SuggestionRequestFactory, prompt renderer, sanitizer |
| Backend selection or memory issue | SuggestionEngineRouter, AppDelegate, LlamaRuntimeManager |
| Native decode/cache/shutdown issue | LlamaRuntimeCore, CotabbyInference boundary |
| Partial/final output mismatch | streaming policy, SuggestionTextNormalizer, seam guards |
| Rapid Tab leaks to the host after exhausting a tail | PostExhaustionAcceptanceState, acceptance coordinator |
| Acceptance key passes through or is stolen | InputMonitor, acceptance validation |
| Wrong or repeated inserted text | SuggestionInserter, InputSuppressionController, reconciler |
| Clipboard context is irrelevant | ClipboardRelevanceFilter, ClipboardContentDistiller |
| Screenshot context is stale/noisy | VisualContextCoordinator, OCRTextHygiene |
| Emoji or macro conflicts with suggestions | InlineCommandCoordinator, feature trigger machine |
| Permission loop or lost grant | PermissionManager, PermissionGuidanceController, app identity |
| Settings/onboarding window issue | SettingsCoordinator, WelcomeCoordinator |
| Settings persistence or domain mismatch | SuggestionSettingsModel, SuggestionSettingsData, SuggestionSettingsStore |

When a change crosses several rows, keep ownership at these boundaries rather than teaching one
coordinator to perform every step itself.

## Cross-Language Expression Learning

The primary workflow is `LearningSentencePreviewCoordinator`, owned once by
`InlineCommandCoordinator`. It initializes from the focus snapshot without sending its text, observes
subsequent same-field mutations and debounces a bounded, read-only `LearningSelectionCapture`.
Keyboard observations hide the preview/details/lookup immediately and invalidate in-flight work
without claiming ordinary keys. Automatic presentation resumes only after the existing 600ms quiet
period; stale documents remain internal history/cache evidence and cannot render. The detail shortcut
opens an existing document or explicitly captures a selected/current sentence. The previous result
retains its source and range; only a verified adjacent predecessor can be carried into a new preview.

`LearningExpressionService` is an app-owned facade over `LearningTranslationService` and
`LearningAnalysisService`. `LearningSentenceGenerating` exposes the two stages explicitly. The
translator returns only the natural expression; the coordinator displays and caches it before
starting independent offline unit recognition and optional analysis. `LearningAnalysisPrompt` sends
the source plus that exact translation, using the complete restored GE baseline to request
`[[source fragment, translation fragment]]`: reusable phrases/grammar constructions, clause-level
long-sentence splits and a suggested 3–6 pairs with short/long-sentence exceptions. Pair count is
prompt guidance; the parser and presentation do not require a fixed count or complete coverage.
`LearningAlignmentParser` validates the complete array before one batch reaches the UI, resolves
exact continuous quotations to grapheme-safe UTF-16 spans and rejects rewrites or overlaps. Unique
pairs can disambiguate remaining repeated occurrences; still ambiguous pairs stay uncolored and
are counted explicitly. Source order generates IDs, while target order may differ. There are no
explanations, model-generated IDs, positions or colors. `LearningSentenceStreamParser` retains the
historical NDJSON experiment protocol but is not used by product analysis. Analysis failures preserve
the expression, and changing an analysis model, credential, or switch restarts only analysis. Its
cache includes the fixed sentence pair, languages and analysis model snapshot. With analysis off,
expansion still shows the sentence pair, learning units and dictionary interaction.

`LearningUnit` owns click ranges independently of `LearningMeaningChunk` correspondence ranges.
`LearningUnitRecognizer` is a pure per-language index of exact dictionary headwords/recorded forms
and conservative single-word slots in explicitly recorded patterns. UTF-16 ranges always reference
the untouched translation; normalized keys never become display text. Pattern fixed parts may be
separated, and their slot words stay individually clickable. It does not infer arbitrary morphology
or grammatical phrases. `LearningUnitPolicy` provides fallback word occurrences and filters out any
correspondence that intersects only part of a unit; a correspondence may contain several units.

`CotabbyAppEnvironment` owns one `LearningLexiconService` actor, shared by recognition and lookup.
It lazily loads the independent CC BY-SA expression resource and builds language indices away from
MainActor. The coordinator owns a separately cancelled recognition task and a bounded memory cache
keyed by fixed translation/language. Recognition and analysis can finish in either order; changing
analysis settings restarts only analysis. Their request identities prevent late units or colors
attaching to a new sentence, and each failed stage preserves the translation.

`LanguageLearningSettings` owns two `LearningModelSettings` profiles and separate translation and
analysis switches. `CotabbyAppEnvironment` constructs one `LearningModelCollection`; settings views,
services and termination share those controllers. Each role owns model selection, status, task identity
and a separate `LearningLocalRuntime`, or its own configured OpenAI-compatible Endpoint and Keychain
namespace. Legacy learning model/address/key migrate once into translation; later completion changes
cannot redirect it. Analysis defaults off and never inherits a remote address or credential.

Model controls live in Engine & Model. `SettingsNavigationModel.engineTask` is window-owned
navigation state for the fixed completion/translation/analysis tabs; it never writes runtime
selection. Completion retains its existing grouped form. `LearningModelConfigurationView` uses
the same scaffold, section structure and row controls for each learning role. Writing observes
profile summaries and routes through `openLearningModel`; it contains no server or key editors.
Learning page identity is bound to its role so an unsaved key draft cannot carry into another role.
Existing engine search anchors navigate back to the completion page before scrolling.
The three forms reuse `ModelsFolderSection`, `InstalledRuntimeModelRow` and
`ModelEndpointConnectionSection`: layout parity comes from common presentation code, while each
role retains its own controller, endpoint catalog and unsaved credential draft. Catalog entries are
task-specific (Hy-MT2 1.8B / 7B and TranslateGemma 4B translation, Gemma 4 E4B / Qwen3.5 4B alignment candidates). The global LM Studio source
refresh notifies all runtimes. `ModelUsagePolicy` combines completion and learning selections,
including saved battery/AC choices; deletion rechecks that set when the confirmation is executed.

`LearningTranslationPrompt` owns the pure specialist payload and per-request sampling values;
`LearningTranslationService` selects it from local GGUF identity or a recognizable endpoint alias.
`LearningLocalPrompt` owns bounded metadata inspection and trusted turn framing, while source text
is tokenized literally by `LearningLocalRuntime`. Hy-MT2's 1.8B and 7B have the same architecture
but different tokenizers, so their embedded chat-template metadata selects distinct turn tokens.
TranslateGemma shares Gemma 3 framing but gets
the Ollama plaintext translation guide with language codes, not generic assistant instructions.
Its native token-budget policy enforces the documented 2K input ceiling before decoding, separately
from the shared 8K allocation. The endpoint path uses text chat, not Google's structured HF processor;
servers own token-limit enforcement and receive only supported temperature/top_p sampling fields.
TranslateGemma's manual template is offered only on the translation page. Recommendations reuse
the completion download rows with an optional task caption; no catalog refresh changes a saved choice.

Each learning role persists independent `LearningPowerProfile` values and defaults source switching
off. The shared power monitor selects its active profile without editing completion. Request
snapshots include only the effective backend/model/template/address/credential revision. The
post-assignment `changes` publisher invalidates work only when that snapshot changes, so a dormant
Endpoint or inactive power-source edit does not unload the active model. Endpoint discovery still
invalidates separately on its role's server/key changes. Low Power Mode uses the existing shared
pause preference and immediately clears learning work and panels when pausing becomes active.
`LearningModelCollection` also stops the native controllers. It reads global/temporary pause and the
existing low-power provider through the shared `LocalRuntimeResidencyPolicy`: translator warm,
analyzer on demand. Live eligibility callbacks and tracked warmup tasks prevent queued work from
loading after a disable. An analyzer native-load attempt schedules idle release even if cancellation
prevented delivery of its ready event. After 60 seconds idle it unloads; cached sentence/chunk values
remain in the coordinator. Endpoint eligibility does not imply native residency and never cancels
an unrelated HTTP request just because local residency is released.


Local learning uses fresh native sequences and instruction templates, independent of autocomplete's
base renderer, KV cache and sentence stop rules. GGUF metadata selects supported templates; explicit
selection handles renamed/variant models. Trusted turn markers are tokenized as specials while the
source-bearing payload is tokenized literally. Native load/decode/unload use the same per-instance
`NativeLlamaSession` ownership boundary as autocomplete, with operation leases preventing stale unloads. Disabling a role releases its model. Quit
cancels decoding and waits for any non-cancellable native load to finish before unloading Metal
contexts; a slow native load can therefore delay quit. The inference workspace patch reference-counts
global backend ownership and installs its global logger once before engines run. A shared GGUF
folder/download manager does not share contexts; catalogued translation specialists are excluded from
autocomplete candidates and fallback selection.

`LearningRequestTelemetry` wraps each validated service operation. A task-local sentence request ID
is shared by translation and analysis; stage operation IDs distinguish retries and are passed as
immutable evidence into detached native work. Logs cover start/generation/load/prefill/decode/first
output/first usable/finish/publication, outcomes and cache hits. Cancellation UUIDs remain independent
stale guards. Ordinary events contain counts, types and timings, not source/prompt/output/server/key.
Debug-only full model input/output uses the original `llmIO` sink; transient debug strings are cleared
at operation completion. `LearningDisplayReporting` reports only a visible, current panel. Analysis
publication is observed when usable chunks are expanded, so its display time can include the user's
wait before opening details; first-usable time measures when the first validated chunk was ready.

`PerformanceMetricEntry` retains its original fields/key and decodes old JSON as completion/completed
with unobserved timings nil. Completion's returned/suppressed result still means completed, not a
quality judgment. The existing opt-in ring now records learning and completion failures/cancellations
as well, with cancellation mapped from both Swift and app-specific cancellation errors. Display
updates patch an extant entry once and cannot resurrect cleared/evicted history. The pane defaults to
completion, filters both chart and rows by task, and labels outcome and stages. The cap is 100 across
all tasks. Completion acceptance/suppression quality counters remain completion-only.

Endpoint learning reuses the HTTP client implementation with a dedicated ephemeral session that
rejects redirects. Translation sends the complete target/language direction plus optional budgeted
reference excerpts from the same editable draft; analysis sends that
source plus the fixed displayed translation. Both require complete text responses; analysis streams
valid chunks. No screen OCR, clipboard, history or autocomplete prompt is included.

The coordinator rejects stale request IDs, keyboard edits, changed focus snapshots and a different
frontmost application. Full AX recapture happens before the first translation and at completion,
rather than on every analysis update. `LearningSentencePanel` remains nonactivating, preserves view
selection within a request and dismisses on outside clicks. `LearningSentenceCard` uses the same
read-only TextKit sentence view for compact and expanded translation, and for source correspondence
highlights. Text remains a natural continuous sentence: neutral underlines mark expressions, and
validated correspondence ranges add matching colors. The explicit TextKit 1 ownership graph avoids
migration-time layout graph replacement. Double-click hit testing rejects whitespace/truncated
glyphs and validates the unit against the current document and source view. Single clicks select
a correspondence within the expanded pair; they do not open another window or query a dictionary.

`LearningDetailPanel` owns one `LearningDictionarySession`, whose home page is the clicked unit.
Internal word selection and return-to-expression change the query within the same nonactivating
window. Query revisions, cancellation and a per-open-unit cache reject stale results after word
changes, return or dismissal. `LearningDictionaryCard` separately renders structured offline senses,
one raw system definition, missing entries and unavailable resources. Entry-level source,
English-definition and license labels remain visible. Offline phrase lookup preserves multiple
exact candidates; the system fallback requires the detected term range to cover the entire query,
so a constituent definition cannot masquerade as a phrase entry. The public `DCSCopyTextDefinition`
copy transfers Core Foundation ownership exactly once. No app HTTP dictionary client or additional
model request exists. The older native dictionary presenter remains for compatibility callers,
but the sentence-learning path uses the shared session. Background unit/alignment updates preserve
an open dictionary for the same fixed translation. Esc dismisses this window before the sentence;
typing and changed documents close it; unavailable placement hides it until space returns.
Sentence caches are bounded, memory-only,
and cleared on field or configuration changes.

Learning cards reserve space independently from completion. `OverlayController` publishes its actual
window rectangle after rendering or acceptance, without changing its ghost positioning or the
coordinator's state callback. `LearningSentencePanelLayout` prefers above the caret and searches for
an on-screen rectangle outside both the caret and that completion rectangle. A later completion
repositions an existing learning card; when no space remains, learning waits and reappears when space
is released. Card height follows content, with a bounded scroll viewport for details. Zero geometry
preferences during host-root replacement are ignored so they cannot collapse the details viewport.

Automatic and explicit translation share `LearningSentencePreviewCoordinator`, one nonactivating
`LearningSentencePanel` and the same sentence card. Turning automatic preview off disables the pause
trigger, while the details shortcut can still request a selection or current-sentence preview.
`InlineCommandCoordinator` owns this sibling's start/stop lifetime, and the existing input monitor
routes both learning commands without another event tap. The legacy `LanguageLearningCoordinator`
and translation panel remain compatibility/test surfaces; the composition root no longer starts them.

`LanguageLearningSettings` owns source languages, target language, reference mode and the two separate
shortcuts. The default reference mode translates the current sentence or explicit selection with no
extra draft excerpts; draft mode adds bounded text before/after that exact target. Selecting the whole
draft makes it the target. `LearningTranslationInput` contains only text; the coordinator alone retains
AX handles and the exact replacement range. Model, reference, language or budget changes cancel old
work and clear caches. Translation cache keys include the effective model and bounded reference input.

For explicit previews, one enabled source language is the user's direction preference; with several,
Natural Language must resolve a confident choice excluding the target. Positive marked IME evidence
blocks the request. Missing proof of committed text permits copy-only preview, never replacement.
Learning includes no screen contents, clipboard data or typing history. Each explicitly configured
endpoint retains its own credentials and disclosure and may be local or public HTTPS.

Clicking Replace or pressing its configured shortcut confirms the currently displayed version. The
card identifies current sentence versus selection. Tab, Return and ordinary typing stay with the host.
Details expand independently; a complete translation can be replaced before alignment finishes.
`LearningSelectionReplacement` revalidates field/session, UTF-16 text, selection and IME capability,
then performs one native selected-text write or target-PID Paste with final selection validation.
It never derives a range from model-output length, retries an uncertain write or rolls back user edits.
A failed write expands source/translation copy recovery and disables repeat replacement. A document-ID
transaction gate survives cancellation until verification ends; an older write cannot label a new
preview as committing or dispatch concurrently. Explicit capture failures show an error-only card
without an editable range. Shortcut label changes repaint the existing card without regenerating.

`LearningTextScopePolicy` resolves complete grapheme-safe selections/sentences, with a separate 256 KiB
acquisition ceiling and a bounded 32K UTF-16 neighborhood for sentence detection. A sentence touching
an artificial boundary is rejected rather than shortened. `LearningTranslationBudget` counts the full
model-specific task and complete target first, reserves output, and crops only reference excerpts.
The output reserve scales with a larger model budget (up to 32K tokens), so a fixed old output
ceiling does not reject a larger complete target unnecessarily. The generic, Hy-MT and TranslateGemma
adapters share this target/reference contract; TranslateGemma's
2K input limit applies to both native and endpoint transports. Output ending at the token limit is
rejected as incomplete and never becomes replaceable. Native post-write verification accepts the
retained field's exact expected value despite a dirty-document title; web fields retain session checks.

### Model context budgets and shortcut ownership

`ModelContextSettings` stores independent task-specific maps keyed by backend, model and normalized
endpoint destination/API mode. Completion resolves its active local filename from the one runtime
model, while translation resolves its power profile. Flat legacy preference keys remain stable.
`SuggestionSettingsSnapshot` freezes both the numeric window and model identities so switching equal
budgets still invalidates requests and anchor caches. Completion defaults to its existing 4K policy;
translation retains its existing 8K default. Apple capacity remains system managed.

`LearningLocalModelConfiguration` freezes the model file, adapter and capacity together for each
native operation. The controller supplies this value across its detached planning/decode boundary,
rather than widening every executor method with separate mutable settings inputs.

`ModelContextBudget` owns pure limits and the disclosed endpoint estimator/margin. Native translation
planning executes inside the role's serialized native boundary off MainActor and counts literal tokens
plus trusted template framing against actual allocated capacity. Endpoint planning also runs off
MainActor, with cancellation checks. Local completion retains estimated section allocation followed
by native tokenizer enforcement; default on-device prompt bytes stay unchanged. A configured local
window reallocates its existing runtime on the next use; startup identities reject obsolete loads.

An explicit completion override expands the existing AX range/provider and bounded snapshot together,
up to a fixed acquisition ceiling. Default polling remains 4096 UTF-16 units per side. Snapshots and
optimistic copies carry their actual capture window for geometry truncation checks. Marker captures
use the same window. Block-break alignment remains independently bounded, and history recording keeps
its original 4K-per-side scope even when completion reads more. Prompt allocation still prioritizes
caret-nearest text; accepting a completion inserts only continuation text at the caret.

All editable keybindings live in Settings → Shortcuts: global acceptance/toggle, translation replace
and details, and per-app overrides. `LearningShortcutRows` and `AppShortcutSection` reuse `KeybindRow`,
`KeyRecorderView` and `PerAppShortcutRowsView`. A pane-owned `ShortcutRecordingState` makes recording
exclusive across all three areas, and late cleanup from an old row cannot retire a newer recorder.
Writing and app detail pages present summaries/navigation;
resetting app behavior preserves shortcut overrides. Onboarding demonstrates read-only current
keycaps and directs later editing to Settings. `ModelContextSection` is a shared presentation-only
budget control owned by each task's parent model page, not another settings/runtime owner.

Focus snapshots keep `documentSelection` and known `documentLength` separately from the bounded
prompt-window `selection`. Native coordinates come from raw AX ranges; marker coordinates derive
from full pre-selection text. Unknown after-caret reads never prove a document end. Editing uses
`AXHelper.exactEditableTextSelection`, whose `AXEditableTextSelection` receipt requires exact UTF-16
field/fragment agreement and complete graphemes. Opaque marker objects live only within one synchronous
read, never across model awaits. Marker-only existing selections use verified Paste, while marker-only
sentence previews have no replacement callback because no offset-to-marker mapping is guessed.
