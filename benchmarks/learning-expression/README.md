# Cross-language expression evaluation

This is a local, headless evaluation of the independent learning feature. It does not start the
app, read editor text or settings, change the selected model, or use the autocomplete runtime.
`cases-v1.json` contains synthetic examples with reviewer expectations. The model receives only
the source and language direction, never those expectations.

`scripts/learning_eval_bridge.swift` compiles the actual production prompts, OpenAI-compatible
client, output policy and sentence stream parser. The standalone CLI owns a single result
collector per request; Python schedules models and preserves evidence. The bridge's nominal
settings declaration is unused and merely lets shared model contracts compile without app UI.

## Run

Requires Swift and a local Ollama server at `127.0.0.1:11434`. Downloads/imports happen separately;
the runner accepts no hosted endpoint. Main comparison aliases are `cotabby-eval-qwen35:chat` and
`cotabby-eval-gemma4:chat`, with explicit vendor text-only, nonthinking conversation framing.
Initial GGUF imports `cotabby-eval-qwen35:4b` and `cotabby-eval-gemma4:e4b` remain as framing
controls. They are separate from the user's selected Cotabby model. The Hy profile
uses `cotabby-eval-hymt:1.8b`, an evaluation alias for official Tencent Q4_K_M weights with
the vendor's user-only chat template and top-k/repetition defaults. The automatically imported
HF alias had a malformed template; its initial smoke output is a configuration failure, excluded
from model-quality comparisons. General aliases are text-only imports: no vision projector or
speculative draft model is loaded. These are exact local inference configurations, not a claim
about the performance of every official runtime distribution of those models.

```sh
python3 scripts/learning_model_eval.py build
python3 -m unittest discover -s scripts/tests -p test_learning_model_eval.py
python3 scripts/learning_model_eval.py run --profile qwen-chat-joint
python3 scripts/learning_model_eval.py run --profile gemma-chat-joint
python3 scripts/learning_model_eval.py run --profile qwen-chat-plain
python3 scripts/learning_model_eval.py run --profile gemma-chat-plain
python3 scripts/learning_model_eval.py run --profile hy-translation
```

`--purpose smoke --cases ability,double-negation,korean-call` runs a smoke subset. `--repeats 3` records repeated
samples separately. Qwen2.5-14B and Ministral are excluded from this comparison. A resident model
blocks the run so the evaluator never evicts another application's work. Runs are sequential and
use an exclusive scheduler lock. Remove `build/DerivedData` after compilation/validation.

## Evidence and interpretation

Each run creates a unique folder below `build/LanguageLearning/ModelEval` containing model
digest, quantization, runner metadata, hardware, source/prompt provenance, fixed sampling,
raw stream packets with monotonic timestamps, resolved UTF-16 quotes and ranges, and failures.
The script verifies the compiled bridge still matches its recorded sources before running.
The seed is not controlled by the production client. Token generation statistics are unavailable
from its callback; no tokens-per-second claim is inferred from character counts.

Cold calibration and warmup use the same synthetic sentence and are excluded from scored warm
cases. The model must be resident before those cases. Only the evaluation model is unloaded on
exit. Background workload can still affect the Mac; record that context using `--note` when comparing runs.
An application must not share the evaluation aliases during testing; residency has no per-client owner.
Metadata explicitly records selected IDs, expected trial count, and smoke/formal purpose. A formal
run requires the full corpus. Summary includes missing and failed trials, including partial translation.

The first visible content token is **not** the finished translation. For the joint request,
`translationAcceptedMilliseconds` marks the first complete translation JSON record accepted by
the real parser. `firstChunkMilliseconds` marks its first usable chunk. Completion includes all
analysis. Missing values stay missing; aborted requests do not enter completion percentiles.
Language directions are summarized separately; one or two examples only establish a smoke check,
not multilingual accuracy. Timings exclude AX, debounce, layout and rendering; these are not
end-to-end editor latency measurements.

Joint profiles share production prompt, system message, nonthinking request, temperature 0.3,
top-p 0.9 and a 4096 output budget. Plain profiles use the production translation prompt and
nonstreaming `generateInstruction` transport with a 2048 output budget. Hy uses its vendor user-only prompt,
temperature 0.7 and top-p 0.6. Its top-k/repetition-penalty defaults come from model metadata, not
the shared OpenAI client. Different vendor sampling and quantization are disclosed, not treated
as an identical-configuration model comparison.

Structural protocol success and character-span coverage do **not** establish semantic quality.
Review translation meaning, tense, negation, numbers and tone separately from chunk quality:
phrases/constructions should express the original meaning, explanations should teach the actual
displayed wording, and a whole sentence in one chunk may parse yet be unhelpful. `review.json`
provides rubric fields and full evidence for independent review. Several translations can be
acceptable; no single reference string is an exact-match gold answer. Model names should be
hidden when reviewing competing outputs for a formal quality comparison. Review packets contain an
opaque packet ID and omit model labels; copy them outside the profile-named evidence directory for
blind review. Suggested judgement: 0 = critical error/unusable, 1 = substantial correction needed,
2 = usable with minor issue, 3 = correct/useful. Score translation meaning and naturalness separately
from alignment, semantic coverage, segmentation usefulness and explanation accuracy. These are
reviewer judgements, not benchmark-ground-truth accuracy percentages. Multilingual fluency claims
need a reviewer competent in that particular language.

`gemma-forensic` is a smoke-only diagnostic: it captures the remaining raw stream after parser
failure, records when parsing stopped, and never treats that content as a successful UI result.
Final-line errors and missing chunks also record a parser-stop time. It is excluded from formal
latency comparison. Explicit turn framing alone did not resolve the observed joint-task failures.

The first translation-only measurements and all 28 source/translation triples are recorded in
[`translation-results-2026-10-12.json`](translation-results-2026-10-12.json). Each model completed
all output-policy checks, but specific meaning and grammar errors remain. Different prompt and
sampling profiles mean these timings compare the tested configurations, not architecture speed
under identical vendor settings. The report makes no overall translation-accuracy claim.

## Fixed-translation alignment prompt experiment

`alignment-cases-v1.json` freezes 28 manually checked source/translation pairs. The translation is
input, not an output being scored. Its reviewer expectations are never sent to the models.
`scripts/alignment_prompt_export.swift` freezes checkpoint 636af328's historical prompt as A, removes
only explanation responsibility for B, and exports the continuous two-string-array proposal as C.
C changes both instructions and schema (including discontinuous-span expressiveness); it is a
compound proposal, not a format-only ablation. Production prompts and application settings remain
unchanged by this experiment.

```sh
python3 scripts/learning_alignment_eval.py prepare
python3 -m unittest discover -s scripts/tests -p test_learning_alignment_eval.py
python3 scripts/learning_alignment_eval.py run --purpose smoke
python3 scripts/learning_alignment_eval.py run --purpose formal
python3 scripts/learning_alignment_review.py packets build/LanguageLearning/AlignmentEval/RUN --shards 3
# Independent reviewers write blind-review/ratings-*.json.
python3 scripts/learning_alignment_review.py aggregate build/LanguageLearning/AlignmentEval/RUN
```

The Python scheduler owns loopback requests and immutable raw evidence; it never builds, installs,
launches or reads settings from Cotabby. The Swift exporter owns prompt snapshots so A cannot drift
away from production by hand copying. The offline review script owns deduplication, blind packets
and aggregation; it cannot contact models. Identical outputs for a case are reviewed once and their
rating is mapped back to every repetition. Explanations and model/arm labels are omitted from review.

The formal run contains 28 cases × 3 models × 3 arms × seeds 42, 43, 44 = 756 scored requests.
Within each model, all arms share sampling, 8192 context, 4096 output budget and disabled thinking.
Models are scheduled sequentially, with two excluded calibration requests before scored trials.
The first calibration may include cold load; the second is warm. Each request checks residency
before and after; only the experiment's own alias is unloaded. The shared scheduler lock prevents
other evaluator scripts from running simultaneously, but cannot prevent another application using
the same alias. No hosted endpoint is accepted.

The strict validator rejects invalid JSON rather than repairing it. Quote validation uses literal
nonoverlapping occurrences. `multipleCandidateQuoteGroups` flags multiple possible literal
positions, not semantic ambiguity. Diagnostic first-unused mapping and character coverage do not
establish correspondence correctness. `protocolSucceeded` requires a clean stop, valid complete
format/quotes, no thinking, at most 40 groups and at least one uniquely locatable paired group;
it does not require every group to be uniquely locatable. C does not explicitly prompt the 40-group
cap; this is disclosed as part of evaluating the complete product proposal.

Only **completed** run directories are eligible for formal aggregation. Success latency is
conditional on protocol success and must be read alongside its sample count. Raw content first
arrival and output-token counts also include format failures; fast invalid output is not a usable
result. Latency comes from optimized standalone CLI inference, excluding editor pause, AX and UI.

Blind review scores alignment, segmentation usefulness and important-meaning coverage separately
from format and exact spans. Ratings are independent AI reviewer judgements, not certified human
accuracy. Whole sentences can be appropriate for short greetings but unhelpful for long learning
examples. Japanese, Korean, German and Spanish cells are small smoke samples and cannot establish
general multilingual quality. Primary semantic ratings include strict-format outputs (including
literal-invalid quotations); strict-format failures remain counted in protocol availability and
are not repaired into semantic successes. This conditional selection must be reported explicitly.

Completed fixed-translation results: [2026-10-13 report](alignment-results-2026-10-13.md)
and [machine-readable summary](alignment-results-2026-10-13.json). The full 756-trial run and
182 deduplicated blind-review items are complete. Removing explanations helped both general
models; the compact-pair proposal improved Qwen availability but caused overly large chunks
in Gemma. Later local follow-ups selected GE as the product baseline. The exporter also emits
the frozen GE renderer. The current product renderer is exported separately as `Learning` (now
restored to the complete GE instructions), so
learning-unit changes do not silently alter historical A/B/C or compact experiment requests.

Learning-unit recognition, same-window expression/word lookup and observed unit/correspondence
paint latency: [2026-10-13 implementation and Release report](learning-units-2026-10-13.md).

Complete GE restored at the user's request, with a native before/after comparison and new painted
latency measurements: [2026-10-13 GE restoration report](ge-restoration-2026-10-13.md).

Quantity-only D and authorized cloud follow-up: [2026-10-13 report](alignment-quantity-results-2026-10-13.md)
and [JSON summary](alignment-quantity-results-2026-10-13.json). It contains 168 local Gemma C/D
and 336 DeepSeek Flash A/B/C/D requests. Run `python3 scripts/learning_alignment_quantity_eval.py local`
or `cloud`; cloud credentials are entered via `getpass` and never saved. Only the frozen synthetic
corpus is sent to the fixed official DeepSeek host; redirects and proxies are refused. Thinking is
disabled. Cloud repetitions have no seed control, and measured time includes network/queue/cache.
D adds only a soft count guideline. The app and production prompts remain unchanged.

Blind review can reuse prior ratings with `--reuse-from RUN` only after exact corpus equality;
identical normalized outputs retain their prior ratings, and new outputs receive independent review.

Compact local prompt follow-up: [2026-10-13 report](alignment-compact-results-2026-10-13.md)
and [JSON summary](alignment-compact-results-2026-10-13.json). Run
`python3 scripts/learning_alignment_compact_eval.py` for the 280-request Gemma-only comparison.
It keeps frozen D and adds four compact factorial arms: S, G, E, GE. Task instruction counts exclude
shared system text and fixture input. The shape-only example has two pairs, so its effect includes
possible quantity priming and must not be interpreted as pure schema clarity. No cloud credentials,
training or application build is involved.

Compact real-example follow-up: [2026-10-13 report](alignment-example-results-2026-10-13.md)
and [JSON summary](alignment-example-results-2026-10-13.json). Run
`python3 scripts/learning_alignment_example_eval.py` for the 168-request local Gemma comparison.
GE is frozen from the compact run; P/R replace abstract grain rules with one short phrase rule and
matched five-pair placeholder/real demonstrations. P-to-R includes language, lexical and length
effects. The real example reduced whole-sentence grouping but introduced target rewriting and
schema failures; it is not adopted. No cloud request or app update is involved.
