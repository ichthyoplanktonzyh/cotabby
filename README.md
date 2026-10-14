# Lingrove · 拾语

Inline autocomplete and language learning, wherever you write. Get continuations beside your
cursor, translate sentences, and learn useful expressions without leaving your editor.

Lingrove is an open-source macOS menu bar app maintained by
[ichthyoplanktonzyh](https://github.com/ichthyoplanktonzyh), derived from
[FuJacob/Cotabby](https://github.com/FuJacob/cotabby) and its contributors. Inline autocomplete and
language learning are its two core capabilities, developed together.

> **In development.** Work is on `codex/language-learning` until reviewed and validated for `main`.
> Independent releases and automatic updates are not yet available. The existing cat artwork is
> inherited from Cotabby while Lingrove's visual identity is being designed.

[Source](https://github.com/ichthyoplanktonzyh/cotabby) ·
[Feedback](https://github.com/ichthyoplanktonzyh/cotabby/issues) ·
[Releases](https://github.com/ichthyoplanktonzyh/cotabby/releases) ·
[FAQ](FAQ.md) · [AGPLv3 license](LICENSE)

## Two core capabilities

### Inline autocomplete

- **Ghost-text continuations:** receive suggestions beside the cursor in supported macOS fields;
  accept a word, phrase, or whole suggestion with your configured shortcuts.
- **Choice of backend:** use Apple Intelligence, in-process local GGUF inference, or an
  OpenAI-compatible endpoint you configure.
- **Context and control:** choose suggestion length, within-word prediction, streaming, and
  optional screen/clipboard context. Pause globally or disable it for specific apps.

### Language learning

- **Translation beside your text:** translate a completed sentence or a paused draft into your
  chosen language while continuing to write in the same field.
- **Sentence understanding:** inspect source/target correspondences and identify reusable phrases
  and grammatical constructions through optional learning-unit recognition and chunk alignment.
- **Expression and word lookup:** inspect an expression or word using the bundled expression
  lexicon and the dictionaries enabled on your Mac.
- **Independent learning models:** configure translation, learning-unit recognition, and chunk
  alignment separately, using local models or endpoints you explicitly choose.

### Additional writing tools

Autocorrect, emoji insertion, and slash macros for calculations/conversions complement both core
capabilities.

The menu bar controls global pause and opens Settings. Configure source/target languages and
learning models in Settings before enabling language learning. Tab and Return keep their ordinary
behavior in the learning card; Escape dismisses it. Autocomplete's acceptance keys are configurable.

## Privacy and local storage

- Apple Intelligence and local GGUF inference run on your Mac. Translation and analysis can also
  run locally once their models are installed.
- An explicitly configured endpoint receives the request for its task, which can include typed
  text and enabled context. Autocomplete and learning tasks have their own model/server settings;
  use the local path when you want that task to remain on-device.
- Screenshots and OCR run on-device. If screen context is enabled for endpoint autocomplete, its
  bounded text excerpt can be included in that endpoint request.
- Input-history recording is off by default. When enabled, the recorded text is stored in an
  encrypted archive on this Mac with its key in Keychain. You can clear the history in Settings.
- Developer mode (`-cotabby-debug`) can write full model inputs/outputs to local diagnostic logs.
  Model download/search uses the network. Automatic app updates remain disabled during migration;
  the manual update action opens this project's Releases page.
- There is no hosted account requirement, analytics, or remote crash reporting built into the app.

Lingrove and Lingrove Dev use separate preferences, Keychain services, model/history folders, and
logs. Existing Cotabby data is preserved and is not imported automatically. See [FORK.md](FORK.md).

## Install and develop

Requires macOS 14 or later. Apple Silicon is recommended for local inference. Autocomplete can use
Apple Intelligence on supported Macs with macOS 26 or later, an installed local GGUF model, or an
OpenAI-compatible endpoint. Translation and analysis use their separately configured learning models.

There is no Lingrove Homebrew cask or independent production download established yet. Follow
[this repository's Releases](https://github.com/ichthyoplanktonzyh/cotabby/releases) for future builds.
For now, build from source:

```sh
git clone https://github.com/ichthyoplanktonzyh/cotabby.git
cd cotabby
git switch codex/language-learning
scripts/dev-setup.sh
scripts/prepare_cotabby_workspace.sh
open build/cotabby-dependencies/Cotabby.xcworkspace
```

Select **Cotabby Dev** in Xcode; this internal scheme builds **Lingrove Dev.app**. Production uses
the **Cotabby** scheme and produces **Lingrove.app**. Internal module and source-folder names stay
unchanged during the product migration. Local signing uses your own team in the gitignored xcconfig.
See [CONTRIBUTING.md](CONTRIBUTING.md) for build/test instructions and [RELEASING.md](RELEASING.md)
for the independent update plan.

## Permissions

Grant Accessibility and Input Monitoring for text access, typing detection, and insertion.
Screen Recording is optional for screenshot-based context. Generation and insertion remain blocked
in secure fields. Follow the permission guidance using the installed app's actual name in System
Settings.

## Interface language

Choose Settings → General → Interface Language. English and 14 translated locales are available.
Simplified Chinese displays 拾语, Traditional Chinese displays 拾語, and other locales use Lingrove.
Restart to apply an interface-language change; this setting is separate from autocomplete languages
and learning source/target languages. The stable English bundle names keep storage paths unchanged.

## Learning behavior and model details

<details>
<summary>Translation, correspondence, dictionaries, models, and request metrics</summary>


Language learning can be enabled independently of inline autocomplete. In **Settings → Writing**,
choose one or more source languages, a target
language and a detail shortcut (default **Option+T**). Model summaries link to their configuration
in **Settings → Engine & Model**.
The master feature is off by default; enabling it enables automatic sentence preview.

Use your input method as usual: confirm the candidate and pause briefly. A read-only target-language
expression appears beside the caret without stealing focus. A dedicated translation model delivers the
expression first. When optional analysis is enabled, its independently configured model prepares
meaning chunks for that exact expression. Option+T or the expand
button reveals the source and target as matching colored meaning units, with small gaps between target
units. Clicking a chunk outlines both sides and opens a separate, nonactivating correspondence window.
Word buttons open the native macOS dictionary popover beside the clicked word, preserving the
dictionary's own formatting without a model request. Available contents depend on the Mac's enabled
dictionaries. Compact translation also supports double-click word lookup. Esc closes lookup first,
then correspondence details; continuing to type closes both. Alignment generates quoted pairs only;
explanations are deferred to a future independent feature.
Tab and Return retain their ordinary behavior; Escape dismisses the learning card.

Pauses trigger previews without ending a sentence. Extending an unfinished sentence updates that
sentence; punctuation and newlines distinguish a new sentence. The preceding sentence's translation
can remain visible while the new one arrives. An older version is labelled while typing continues.
Focus entry alone never sends existing text: automatic requests require a new edit in the same field.
No particular input-method brand or switch to ABC is required. Known active marked composition blocks
generation; unavailable composition evidence permits only the read-only preview.

Turning off automatic sentence preview restores the explicit selected-text/current-sentence preview,
including its verified click-to-replace operation. Customized shortcuts are preserved; the old default
Control+Command+T migrates to Option+T.

In Writing, enable cross-language translation. In Engine & Model, use the fixed **补全 / 翻译 /
语块对应** tabs to select a task; each page uses the existing grouped settings layout. Writing
provides direct links to the translation and analysis pages. Switching tabs changes navigation only,
and the page shows the actual configured model or an explicit unconfigured state. Translation and
optional meaning-chunk analysis each support **in-process GGUF** or an independent OpenAI-compatible
**Endpoint**, with separate model/address/API-key settings. Local GGUF execution needs no Ollama
service. Both pages mirror completion: recommended downloads, Hugging Face import, models folder,
LM Studio source, installed model management, connection/key controls and power-source settings.
The translation catalog offers Hy-MT2 1.8B (1.13 GB), Hy-MT2 7B (4.62 GB) and
TranslateGemma 4B (2.49 GB), all Q4_K_M. Tencent supplies the Hy-MT GGUFs;
bullerwins supplies TranslateGemma's text-only GGUF. These are download sizes, not runtime memory
requirements. TranslateGemma 12B is not included. Gemma 4 E4B / Qwen3.5 4B remain alignment candidates.
Gemma uses the experiment's pinned 5.49 GB Q4_K_M text weights; E4B is not its total parameter count.
These recommendations do not override existing selections. Both tasks
also accept imported GGUFs or configured endpoints. Battery/AC selections belong to each task, and
shared-file deletion protects all tasks’ saved model references. Original autocomplete model settings remain
independent. Analysis defaults off: expansion still shows the source and translation. Changing or
failing analysis keeps the displayed translation.

The full translation appears first. An offline expression lexicon independently adds learning-unit
boundaries: fixed expressions use a neutral underline, while ordinary words remain directly
queryable. Double-click an expression in either the compact preview or expanded translation to
query the whole expression. Its dictionary window offers internal words and a return-to-expression
action in the same window. Missing expression entries are stated explicitly; constituent word
definitions are never combined into a phrase definition. Copy always returns the original sentence.

The bundled Wiktionary / Kaikki expression subset is about 11.5 MB and contains entries for all
configured target languages, with uneven coverage and English definitions. Recognition uses exact
headwords, recorded forms and conservative one-word slots in explicitly recorded expression
patterns; it is not a comprehensive grammatical phrase detector. The data has separate
[CC BY-SA attribution and provenance](Cotabby/Resources/learning-expressions.NOTICE.md).
Expression lookup uses the offline resource; word fallback uses the public Dictionary Services
API and the system's enabled dictionaries. No extra model request or app-managed hosted dictionary
lookup is added.

A sentence preview sends only the selected text or current sentence, up to 6 KB; larger scopes are
rejected without truncation. Analysis additionally receives the exact displayed translation. Learning requests do not include screen contents, clipboard data or typing
history. The settings disclose transmission to a configured LAN/HTTPS service, and the learning
session rejects HTTP redirects. Existing learning endpoint selection migrates once into translation;
analysis never inherits it. Missing configuration and failed requests remain recoverable, and model
capability determines translation and alignment quality. Alignment preserves the displayed wording,
uses the restored GE prompt for reusable phrases/grammar constructions and clause-level long-sentence
splits, with a suggested 3–6 pairs and exceptions for short fixed expressions or longer sentences.
This is model guidance, not a required UI block count. Colors appear only after complete output
validation and learning-unit boundary checks.
One correspondence can combine several units; one fixed expression cannot be split into conflicting
colors. Single-click a colored range to inspect its source/target correspondence. Failed recognition
leaves the sentence readable and word lookup available; failed alignment leaves neutral units usable.

`LearningTranslationPrompt` selects the specialist's translation instructions independently of
chat framing. Hy-MT retains its existing vendor prompt; GGUF template metadata distinguishes the
different 1.8B and 7B turn tokens. TranslateGemma uses the
[Ollama plaintext guide](https://ollama.com/library/translategemma:4b), explicit source/target language
codes (including zh-Hans / zh-Hant), and a user-only Gemma turn. Its Traditional Chinese label is
explicit rather than relying on the script code alone. This is not Google's structured HF
processor request: endpoints requiring that processor need a separate server adapter. Recognizable
Endpoint model IDs select the plaintext guide; opaque aliases retain the generic prompt. Native
TranslateGemma rejects input above 2,048 actual tokens, including instructions and framing, without
truncation. Endpoint token limits are enforced by the selected server. Native sampling is model-specific;
the shared OpenAI-compatible transport forwards only temperature and top_p.

Performance tracking uses the existing opt-in switch. Its request-type picker separates autocomplete,
translation and analysis; old history remains autocomplete history. The shared ring retains the most
recent 100 requests across all tasks. Learning rows show completed/failed/cancelled outcomes and
observed load, first-output, first-usable and panel-publication durations. No text or credentials are
stored in these metrics. Full model inputs/outputs use the existing `-cotabby-debug` LLM I/O sink.

Learning follows the existing global pause and Low Power Mode setting: pausing releases its native
contexts, and resuming keeps the eligible local translator warm. Local analysis loads on demand and
releases after 60 seconds idle. Endpoint tasks keep their separate server/key configuration. The
redundant passive word-hint workflow has been removed; legacy hint preferences are ignored.

</details>

## Contribute

[Report an issue or share an idea](https://github.com/ichthyoplanktonzyh/cotabby/issues).
See [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md),
[ARCHITECTURE.md](ARCHITECTURE.md), and [SOURCE_LAYOUT.md](SOURCE_LAYOUT.md) for development guidance.

## Maintainer and origins

Lingrove is maintained by [ichthyoplanktonzyh](https://github.com/ichthyoplanktonzyh).
The original Cotabby project was created by [FuJacob](https://github.com/FuJacob) and developed with
[jam-cai](https://github.com/jam-cai), [akramj13](https://github.com/akramj13), McHamster, and other
contributors. Their authorship and contributions remain credited.

Dependencies and data retain their own attribution and licenses, including
[CotabbyInference](https://github.com/FuJacob/cotabbyinference),
[llama.cpp](https://github.com/ggml-org/llama.cpp), [Sparkle](https://github.com/sparkle-project/Sparkle),
[swift-log](https://github.com/apple/swift-log),
[LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern),
[SymSpell](https://github.com/wolfgarbe/SymSpell), and [GitHub gemoji](https://github.com/github/gemoji).
Bundled dictionaries and expression data are documented in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)
and [learning-expression notices](Cotabby/Resources/learning-expressions.NOTICE.md).

## License

Lingrove retains the [GNU Affero General Public License v3.0](LICENSE). See the license for
redistribution and corresponding-source requirements. Third-party code, dictionaries, and model
weights retain their own terms.
