# Lingrove · 拾语 FAQ

## What is Lingrove?

Lingrove is a macOS menu bar app with two equally core capabilities: inline autocomplete and
language learning during everyday writing. Autocomplete offers continuations beside your cursor;
language learning translates sentences, shows source/target correspondences, identifies reusable
expressions, and offers word lookup. Autocorrect, emoji, and slash macros are additional writing
tools. It derives from Cotabby and is independently maintained by
[ichthyoplanktonzyh](https://github.com/ichthyoplanktonzyh).

## How do I install it?

Lingrove is still in development. Build from source using [CONTRIBUTING.md](CONTRIBUTING.md), selecting
the internal **Cotabby Dev** scheme to produce **Lingrove Dev.app**. The production **Cotabby**
scheme produces **Lingrove.app**. Watch
[this repository's Releases](https://github.com/ichthyoplanktonzyh/lingrove/releases) for future builds.
There is no independent Homebrew cask or production download established yet.

## How do I start learning?

Open Settings from the menu bar. Configure the learning source and target languages, then select
the translation model or endpoint. Learning-unit recognition and chunk alignment have their own
optional models. Enable language learning and write in a supported text field; pauses can preview
an unfinished sentence, and punctuation/newlines distinguish completed sentences.

Inspect a colored correspondence or use the word/expression lookup. Available word definitions
depend on the dictionaries enabled on your Mac. Escape dismisses the learning card; Tab and Return
retain their ordinary behavior there. See [README.md](README.md#learning-behavior-and-model-details)
for model and interaction details.

## Does everything run offline?

Local GGUF translation/analysis works offline after the required models are installed. Autocomplete
can use local GGUF inference or Apple Intelligence on a supported Mac. Each task can instead use
an OpenAI-compatible endpoint you explicitly configure, whose connectivity depends on that server.
Autocomplete's backend choice does not automatically select the learning backend.

## What text is sent to a server or saved?

A configured endpoint receives that task's request, which can include typed text and enabled
context. Screenshots and OCR remain local; bounded OCR text can be included in endpoint autocomplete
when screen context is enabled. Use the local backend for a task you want to keep on-device.

Input-history recording is off by default. Enabling it stores an encrypted archive on this Mac,
with its key in Keychain; you can clear it in Settings. Developer mode (`-cotabby-debug`) can write
full model inputs/outputs to local diagnostic logs. Model downloads and searches use the network.
There is no built-in hosted account requirement, analytics, or remote crash reporting.

## Why are macOS permissions needed?

- Accessibility reads text/caret information and inserts accepted text.
- Input Monitoring observes typing and the acceptance shortcut.
- Screen Recording is optional for screenshot-based context.

Follow the app's guided setup in System Settings using its installed name, **Lingrove** or
**Lingrove Dev**. Secure fields remain blocked. The new Bundle IDs have separate permissions from
Cotabby; old grants should not be assumed to apply to Lingrove.

## What are the system requirements?

macOS 14 or later. Apple Silicon is recommended for local models; model memory/storage requirements
vary by selection. Apple Intelligence autocomplete additionally requires macOS 26 or later on a
supported Mac with Apple Intelligence enabled. Use local GGUF inference or your configured endpoint
where Apple Intelligence is unavailable.

## How do I use autocomplete?

When ghost text appears, Tab accepts a word or phrase according to Acceptance Mode. The
accept-entire-suggestion key takes the whole continuation; continuing to type ignores it and Escape
dismisses it. Shortcuts are configurable in Settings. Global pause also pauses language learning.

## How do I change the interface language?

Use Settings → General → Interface Language and restart. Simplified Chinese displays 拾语,
Traditional Chinese displays 拾語, and other supported locales use Lingrove. This preference is
separate from autocomplete languages and learning source/target languages.

## What happens to my Cotabby data?

It remains in its original locations. Lingrove uses separate preferences, Keychain services, model
and encrypted-history folders, and logs. There is no automatic import yet. Encrypted history needs
its original encryption key for a future migration; copying only its archive is insufficient.
See [FORK.md](FORK.md).

## How do updates work?

Automatic updates are disabled until Lingrove's independent feed, signing, and distribution setup
are ready. Check for Updates currently opens this repository's Releases page. See
[RELEASING.md](RELEASING.md) for the Sparkle plan; there is no connection to Cotabby's update feed.

## Where should I report a problem or contribute?

Use [Lingrove's Issues](https://github.com/ichthyoplanktonzyh/lingrove/issues) and
[contributor guide](CONTRIBUTING.md). The repository's README and app acknowledgements retain the
original Cotabby authors and third-party credits. Lingrove retains [AGPLv3](LICENSE); dependencies,
dictionaries, and model weights keep their own terms. A configured third-party endpoint may charge
for its service.
