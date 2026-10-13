> **Independent fork in development:** This repository is maintained by
> [ichthyoplanktonzyh](https://github.com/ichthyoplanktonzyh/cotabby) and derives from
> [FuJacob/Cotabby](https://github.com/FuJacob/cotabby). Its direction is translation and
> expression learning during everyday writing, while retaining the existing autocomplete.
> The current milestone is a mature macOS experience in Swift; cross-platform work is planned
> for later. The product name is provisional. Existing website, download, donation, and release
> links below refer to the upstream project, not a release of this fork.
>
> Active work lives on `codex/language-learning` until reviewed and validated for the fork's
> `main` branch. See [FORK.md](FORK.md) for repository ownership and release preparation.

<p align="center">
  <a href="https://cotabby.app" target="_blank">
    <img height="150" alt="Cotabby logo" src=".github/assets/readme/logo.png" />
  </a>
</p>

<h1 align="center">Cotabby [beta]</h1>

<p align="center"><em>Open-source, local-first AI autocomplete for macOS.</em></p>

<p align="center">
  <a href="https://cotabby.app">
  <img width="200" alt="landing-page" src="https://github.com/user-attachments/assets/c28fbb4b-6dfb-4403-a040-1df61daf4df2" /></a>


<a href="https://github.com/FuJacob/cotabby/releases/latest/download/Cotabby.dmg">
<img width="200" alt="download" src="https://github.com/user-attachments/assets/d5cb4454-d2ab-41d3-9d36-171d44ebfc52" /></a>


<a href="https://ko-fi.com/cotabby" target="_blank">
<img width="200" alt="support" src=".github/assets/readme/support-cotabby.png" />
</a></p>

<p align="center">
  <a href="https://github.com/FuJacob/cotabby/actions/workflows/build.yml"><img alt="Build" src="https://img.shields.io/github/actions/workflow/status/FuJacob/cotabby/build.yml?branch=main" /></a>
  <a href="LICENSE"><img alt="License: AGPL v3" src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" /></a>
  <a href="https://github.com/FuJacob/cotabby/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/FuJacob/cotabby" /></a>
  <a href="https://github.com/FuJacob/cotabby/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/FuJacob/cotabby/total" /></a>
  <a href="https://github.com/FuJacob/cotabby/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/FuJacob/cotabby?style=flat" /></a>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-F05138?logo=swift&amp;logoColor=white" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" />
</p>

<p align="center">
  <sub>Cotabby is free and open-source — maintained by two students. If it's useful to you, please consider supporting Cotabby's future.</sub>
</p>

---

## What It Does

Cotabby adds AI autocomplete to almost any text field on your Mac. As you type, a gray suggestion appears inline next to your cursor. Press `Tab` to accept it a word at a time, or keep typing to ignore it.

The default Apple Intelligence and Open Source engines run on your Mac. No account or telemetry is
required. An optional OpenAI-compatible engine can connect to a server you configure.

## Demo

<p align="center">
  <a href="https://www.youtube.com/watch?v=p3TIgxQFQGE"><strong>Watch on YouTube →</strong></a>
</p>

<div align="center">

|  |  |
|:---:|:---:|
| <img src="gifs/slack.gif" alt="Cotabby emoji autocomplete demo" width="400" height="225" /> | <img src="gifs/imessage.gif" alt="Cotabby autocomplete demo" width="400" height="225" /> |
| <img src="gifs/autocorrect.gif" alt="Cotabby autocorrect demo" width="400" height="225" /> | <img src="gifs/macros.gif" alt="Cotabby inline macros demo" width="400" height="225" /> |

</div>

## Features

- **Ghost-text autocomplete** — AI suggestions inline in almost any macOS text field; `Tab` accepts a word at a time
- **Emoji autocomplete** — type `:rocket:` and accept it without leaving the field
- **Inline macros** — type `/` for quick math, unit and currency conversion, dates, and random values
- **One-key autocorrect** — fix a likely typo with a single keystroke
- **Prediction controls** — choose whether to predict ahead, suggest within words, and show following words
- **Optional screen context** — control visual context independently of the local prediction settings

## Privacy

Privacy is the whole point, so Cotabby's default engines keep generation on your Mac:

- Apple Intelligence and Open Source generation run on-device.
- The optional OpenAI-compatible engine sends a bounded request only to the endpoint you configure;
  that endpoint can be loopback, on your local network, or a public HTTPS service.
- No analytics, no telemetry, no crash reporting.
- A normal install never writes what you type to disk.
- Apart from a configured endpoint, the network is used for model downloads and update checks, not
  suggestion generation.

## Engines

Cotabby generates suggestions in three ways. You choose which in Settings → Engine:

- **Apple Intelligence** — Apple's model, built into macOS 26 or later on supported Macs. Nothing to download.
- **Open Source** — a small AI model you download that runs entirely on your Mac. Works on any supported Mac (macOS 14+), with or without Apple Intelligence.
- **OpenAI-compatible** — a completion or chat endpoint you configure, including local Ollama,
  another LAN host, or a public HTTPS service. Endpoint credentials are stored in Keychain.

If your Mac supports Apple Intelligence, that's the easiest place to start. Otherwise, use the Open Source engine and pick one of the built-in models:

| Model          | Size    | Good for                          |
| -------------- | ------- | --------------------------------- |
| `tabby-2-nano` | ~0.8 GB | Older or low-memory Macs; fastest |
| `tabby-2-mini` | ~1.4 GB | A solid everyday balance          |
| `tabby-2-base` | ~4.5 GB | Higher-quality suggestions        |
| `tabby-2-pro`  | ~5.0 GB | Best quality                      |

Download any of them straight from Cotabby's menu bar.

<details>
<summary><strong>Advanced:</strong> model files, custom models, and how generation works</summary>

<br />

Under the hood, the Open Source engine runs local GGUF *base* models in-process through [llama.cpp](https://github.com/ggerganov/llama.cpp) (via [CotabbyInference](https://github.com/FuJacob/cotabbyinference)). Instead of prompting an instruction-tuned chat model, Cotabby treats the model as a pure text continuer and conditions it on your name, writing style, language, and on-screen context.

| Model          | File                             | Size    | Source                                                                       |
| -------------- | -------------------------------- | ------- | ---------------------------------------------------------------------------- |
| `tabby-2-nano` | `Qwen3.5-0.8B-Base.i1-Q6_K.gguf` | ~0.8 GB | [Hugging Face](https://huggingface.co/mradermacher/Qwen3.5-0.8B-Base-i1-GGUF) |
| `tabby-2-mini` | `Qwen3.5-2B-Base.i1-Q4_K_M.gguf` | ~1.4 GB | [Hugging Face](https://huggingface.co/mradermacher/Qwen3.5-2B-Base-i1-GGUF)   |
| `tabby-2-base` | `gemma-4-E2B.i1-Q6_K.gguf`       | ~4.5 GB | [Hugging Face](https://huggingface.co/mradermacher/gemma-4-E2B-i1-GGUF)       |
| `tabby-2-pro`  | `gemma-4-E4B.i1-Q4_K_M.gguf`     | ~5.0 GB | [Hugging Face](https://huggingface.co/mradermacher/gemma-4-E4B-i1-GGUF)       |

**Bring your own model.** Any GGUF small enough to run on-device works. Drop a `.gguf` file into Cotabby's models folder and refresh the model list from the menu bar. Browse the [unsloth GGUF collection](https://huggingface.co/unsloth) for more variants — smaller quants (`Q3_K_M`, `Q4_K_S`) trade quality for size; larger models give better completions at the cost of memory and per-token latency.

For the full suggestion pipeline, see [ARCHITECTURE.md](ARCHITECTURE.md).

</details>

## Install

**Compatibility:** macOS 14.0 or later. The Apple Intelligence engine needs macOS 26 or later on a supported Mac; on older systems, use the Open Source engine.

### Homebrew

```sh
brew tap FuJacob/cotabby
brew install --cask cotabby
```

Upgrade later with `brew upgrade --cask cotabby`. The tap lives at [FuJacob/homebrew-cotabby](https://github.com/FuJacob/homebrew-cotabby).

### Manual download

Grab the latest release from [cotabby.app](https://cotabby.app) and drag Cotabby into your Applications folder.

## Using Cotabby

Start typing in almost any text field. When a gray suggestion appears:

- **`Tab`** — accept the next word. (Prefer whole phrases? Switch this in Settings → Acceptance Mode.)
- **`` ` `` (backtick)** — accept the entire suggestion at once.
- **`Esc`**, or just keep typing — dismiss it.

Every shortcut is rebindable under Settings → Shortcuts.

## Permissions

Cotabby works inside other apps, so macOS asks for a few permissions. Each one maps to a specific feature, and Cotabby walks you through them on first launch:

- **Accessibility** — read the text and cursor position in the field you're typing in, and insert what you accept.
- **Input Monitoring** — notice your typing so it knows when to suggest, and detect the accept keys.
- **Screen Recording** *(optional)* — capture the area around your cursor for visual context, and to match the ghost text's font, size, and position to the app's own text where the app doesn't report them. Leave it off and everything else still works.

Cotabby blocks generation, presentation, and insertion in password and other secure fields.

## Local Development

Requires Xcode and Command Line Tools. Apple Silicon is strongly recommended for local model performance. For setup, build, test, and contribution workflow details, start with [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
git clone https://github.com/FuJacob/cotabby.git Cotabby
cd Cotabby
scripts/prepare_cotabby_workspace.sh
open build/cotabby-dependencies/Cotabby.xcworkspace
```

Use the **Cotabby Dev** scheme for local work. The workspace temporarily supplies the native
APIs in our pending CotabbyInference patch; preparation is automatic in CI and release builds.

If you want to understand the runtime and suggestion pipeline before contributing, read [ARCHITECTURE.md](ARCHITECTURE.md).

## Cross-language expression learning

Cotabby keeps its existing inline autocomplete and offers cross-language expression learning as a
separate, opt-in feature. In **Settings → Writing**, choose one or more source languages, a target
language and a detail shortcut (default **Option+T**). Model summaries link to their configuration
in **Settings → Engine & Model**.
The master feature is off by default; enabling it enables automatic sentence preview.

Use your input method as usual: confirm the candidate and pause briefly. A read-only target-language
expression appears beside the caret without stealing focus. A dedicated translation model delivers the
expression first. When optional analysis is enabled, its independently configured model prepares
meaning chunks for that exact expression. Option+T or the expand
button reveals the source and target as matching colored meaning units, with small gaps between target
units. Clicking a chunk outlines both sides and opens a separate, nonactivating explanation window.
Word buttons open the native macOS dictionary popover beside the clicked word, preserving the
dictionary's own formatting without a model request. Available contents depend on the Mac's enabled
dictionaries. Esc closes lookup first, then the explanation; continuing to type closes both.
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
学习分析** tabs to select a task; each page uses the existing grouped settings layout. Writing
provides direct links to the translation and analysis pages. Switching tabs changes navigation only,
and the page shows the actual configured model or an explicit unconfigured state. Translation and
optional meaning-chunk analysis each support **in-process GGUF** or an independent OpenAI-compatible
**Endpoint**, with separate model/address/API-key settings. Local GGUF execution needs no Ollama
service. Both pages mirror completion: recommended downloads, Hugging Face import, models folder,
LM Studio source, installed model management, connection/key controls and power-source settings.
The catalogs offer Hy-MT2 1.8B for translation and Qwen3.5 4B as an analysis candidate; both tasks
also accept imported GGUFs or configured endpoints. Battery/AC selections belong to each task, and
shared-file deletion protects all tasks’ saved model references. Original autocomplete model settings remain
independent. Analysis defaults off: expansion still shows the source and translation, with direct
native dictionary lookup. Changing or failing analysis keeps the displayed translation.

A sentence preview sends only the selected text or current sentence, up to 6 KB; larger scopes are
rejected without truncation. Analysis additionally receives the exact displayed translation. Learning requests do not include screen contents, clipboard data or typing
history. The settings disclose transmission to a configured LAN/HTTPS service, and the learning
session rejects HTTP redirects. Existing learning endpoint selection migrates once into translation;
analysis never inherits it. Missing configuration and failed requests remain recoverable, and model
capability determines translation and explanation quality.

Performance tracking uses the existing opt-in switch. Its request-type picker separates autocomplete,
translation and analysis; old history remains autocomplete history. The shared ring retains the most
recent 100 requests across all tasks. Learning rows show completed/failed/cancelled outcomes and
observed load, first-output, first-usable and panel-publication durations. No text or credentials are
stored in these metrics. Full model inputs/outputs use the existing `-cotabby-debug` LLM I/O sink.

Learning follows the existing global pause and Low Power Mode setting: pausing releases its native
contexts, and resuming keeps the eligible local translator warm. Local analysis loads on demand and
releases after 60 seconds idle. Endpoint tasks keep their separate server/key configuration. The
redundant passive word-hint workflow has been removed; legacy hint preferences are ignored.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, build, and PR guidelines, and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community expectations. For a tour of the runtime and suggestion pipeline, read [ARCHITECTURE.md](ARCHITECTURE.md).

## Acknowledgments

- [llama.cpp](https://github.com/ggerganov/llama.cpp), [CotabbyInference](https://github.com/FuJacob/cotabbyinference), [Sparkle](https://github.com/sparkle-project/Sparkle), and [swift-log](https://github.com/apple/swift-log) for runtime, updates, and logging.
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) for macOS login-item integration.
- Apple's FoundationModels, Accessibility, SwiftUI, and AppKit for on-device generation and macOS integration.
- [GitHub gemoji](https://github.com/github/gemoji) and Hugging Face for the emoji data and downloadable models.
- [SymSpell](https://github.com/wolfgarbe/SymSpell) by Wolf Garbe (MIT) for multilingual autocorrect; frequency dictionaries derive from [Google Ngrams](https://books.google.com/ngrams) (CC BY 3.0) and licensed SCOWL/Hunspell word lists.
- Everyone who filed issues, tested prereleases, and sent pull requests.

## Created by

Originally created by <a href="https://github.com/FuJacob">@FuJacob</a>, now developed and maintained by <a href="https://github.com/FuJacob">@FuJacob</a>, <a href="https://github.com/jam-cai">@jam-cai</a>. and <a href="https://github.com/akramj13">@akramj13</a>

## License

Cotabby is licensed under the [GNU Affero General Public License v3.0](LICENSE). You can use, study, modify, and redistribute the app, but if you distribute a modified version or make one available to users over a network, you must provide the corresponding source code under the same license.

Third-party dependencies, emoji data, and downloadable model weights keep their own licenses and usage terms. Bundled third-party notices (SymSpell and the autocorrect frequency dictionary) are reproduced in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
