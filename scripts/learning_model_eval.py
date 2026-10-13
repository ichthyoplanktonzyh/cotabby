#!/usr/bin/env python3
"""Schedule local learning benchmarks while Swift owns prompts, transport and parsing.

This CLI never reads Cotabby preferences or editor content. Each run owns an evidence directory;
the bridge compiles the production learning boundary in Release mode. Structural success is
reported separately from the human judgement of translation and chunk semantics.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import math
import platform
from pathlib import Path
import subprocess
import threading
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/LanguageLearning/ModelEval"
CORPUS = ROOT / "benchmarks/learning-expression/cases-v1.json"
BRIDGE = OUTPUT / "bridge/learning-eval"
SOURCES = [
    "scripts/learning_eval_bridge.swift",
    "Cotabby/Models/LanguageLearning/LearningSentenceModels.swift",
    "Cotabby/Models/LanguageLearning/LearningLanguage.swift",
    "Cotabby/Models/Context/LanguageCatalog.swift",
    "Cotabby/Models/Runtime/OpenAICompatibleEndpointModels.swift",
    "Cotabby/Services/Runtime/OpenAICompatible/OpenAICompatibleAPIClient.swift",
    "Cotabby/Support/LanguageLearning/LearningSentencePrompt.swift",
    "Cotabby/Support/LanguageLearning/LearningExpressionPrompt.swift",
    "Cotabby/Support/LanguageLearning/LearningExpressionOutputPolicy.swift",
    "Cotabby/Support/LanguageLearning/LearningSentenceStreamParser.swift",
    "Cotabby/Support/LanguageLearning/LearningFailure.swift",
    "Cotabby/Support/Suggestion/Acceptance/InsertionSafetyGate.swift",
]
# Both general models use the same app sampling and prompt. Hy's vendor instruction is a
# separate translation-only experiment, not a competitor for chunk analysis.
PROFILES = {
    "qwen-joint": ("cotabby-eval-qwen35:4b", "joint", .3, .9, 4096),
    "gemma-joint": ("cotabby-eval-gemma4:e4b", "joint", .3, .9, 4096),
    "qwen-plain": ("cotabby-eval-qwen35:4b", "plain", .3, .9, 2048),
    "gemma-plain": ("cotabby-eval-gemma4:e4b", "plain", .3, .9, 2048),
    "hy-translation": ("cotabby-eval-hymt:1.8b", "hy-official", .7, .6, 4096),
    "qwen-chat-joint": ("cotabby-eval-qwen35:chat", "joint", .3, .9, 4096),
    "gemma-chat-joint": ("cotabby-eval-gemma4:chat", "joint", .3, .9, 4096),
    "qwen-chat-plain": ("cotabby-eval-qwen35:chat", "plain", .3, .9, 2048),
    "gemma-chat-plain": ("cotabby-eval-gemma4:chat", "plain", .3, .9, 2048),
    "gemma-forensic": ("cotabby-eval-gemma4:chat", "joint-forensic", .3, .9, 4096),
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """A local management request must never follow a redirect to another host."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError("Local benchmark HTTP redirect refused")


def api(route, payload=None):
    # Deliberately fixed numeric loopback; no proxy or public endpoint option is exposed.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request("http://127.0.0.1:11434/api/" + route,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with opener.open(request, timeout=180) as response:
        return json.load(response)


def build():
    BRIDGE.parent.mkdir(parents=True, exist_ok=True)
    log = OUTPUT / "bridge-build.log"
    with log.open("w") as stream:
        subprocess.run(["swiftc", "-O", "-parse-as-library", "-module-cache-path",
            str(ROOT / "build/DerivedData/ModuleCache.noindex"), "-o", str(BRIDGE),
            *[str(ROOT / p) for p in SOURCES]], check=True, stdout=stream, stderr=stream)
    save(OUTPUT / "bridge-provenance.json", {"sources": {p: digest(ROOT / p) for p in SOURCES},
        "binary": digest(BRIDGE), "optimization": "-O"})


def wire_case(case):
    # Keep reviewer expectations and any future reference translation out of HTTP payloads.
    return {key: case[key] for key in ("id", "category", "sourceLanguage", "targetLanguage", "source")}


def job(profile, cases):
    model, mode, temperature, top_p, tokens = PROFILES[profile]
    return {"model": model, "mode": mode, "temperature": temperature, "topP": top_p,
        "maxTokens": tokens, "baseURL": "http://127.0.0.1:11434/v1", "cases": cases}


def bridge(payload, command="run"):
    result = subprocess.run([str(BRIDGE), command], input=json.dumps(payload, ensure_ascii=False),
        text=True, capture_output=True, timeout=180, check=True)
    return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]


def batch(payload):
    """Yield completed rows immediately while one Swift session serves all warm trials."""
    with subprocess.Popen([str(BRIDGE), "run"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True) as process:
        timer = threading.Timer(180 * len(payload["cases"]), process.kill)
        timer.start()
        try:
            process.stdin.write(json.dumps(payload, ensure_ascii=False))
            process.stdin.close()
            for line in process.stdout:
                if line.strip():
                    yield json.loads(line)
            error = process.stderr.read()
            if process.wait() != 0:
                raise RuntimeError("Bridge batch failed: " + error)
        finally:
            timer.cancel()
            if process.poll() is None:
                process.kill()
                process.wait()


def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    index = (len(values) - 1) * fraction
    lo, hi = math.floor(index), math.ceil(index)
    return values[lo] + (values[hi] - values[lo]) * (index - lo)


def summarize(rows, expected=None, repeats=1):
    groups = {}
    for row in rows:
        groups.setdefault(row["sourceLanguage"] + "→" + row["targetLanguage"], []).append(row)
    expected = expected if expected is not None else list({r["id"]: r for r in rows if "id" in r}.values())
    for case in expected:
        groups.setdefault(case["sourceLanguage"] + "→" + case["targetLanguage"], [])
    summary = {}
    for language, group in groups.items():
        wanted = [c for c in expected if c["sourceLanguage"] + "→" + c["targetLanguage"] == language]
        item = {"uniqueCases": len({r.get("id") for r in group}), "observedTrials": len(group),
            "expectedTrials": len(wanted) * repeats, "missingTrials": max(0, len(wanted) * repeats - len(group)),
            "protocolSucceeded": sum(bool(r.get("protocolSucceeded")) for r in group),
            "failedTrials": sum(not r.get("protocolSucceeded", False) for r in group),
            "translationAvailable": sum(bool(r.get("translation")) for r in group),
            "translationOnlyPartial": sum(bool(r.get("translation")) and not r.get("protocolSucceeded") for r in group),
            "finishVerifiedButParserFailed": sum(bool(r.get("finishVerified")) and not r.get("protocolSucceeded") for r in group)}
        for key in ("translationAcceptedMilliseconds", "firstChunkMilliseconds", "completionMilliseconds"):
            values = [r[key] for r in group if isinstance(r.get(key), (int, float)) and math.isfinite(r[key])
                and (key != "completionMilliseconds" or r.get("protocolSucceeded"))]
            item[key] = {"observed": len(values), "p50": percentile(values, .5), "p95": percentile(values, .95)}
        summary[language] = item
    return summary


def run(profile, case_ids, repeats, purpose="formal", note=""):
    corpus = json.loads(CORPUS.read_text())
    cases = corpus["cases"]
    if case_ids:
        selected = set(case_ids.split(","))
        if selected - {case["id"] for case in cases}:
            raise ValueError("Unknown case ID")
        cases = [case for case in cases if case["id"] in selected]
    model = PROFILES[profile][0]
    resident = api("ps")["models"]
    if resident:
        raise RuntimeError("A model is already resident; leave the user's model untouched and retry when idle")
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = OUTPUT / (now + "-" + purpose + "-" + profile + "-" + uuid.uuid4().hex[:6])
    directory.mkdir(parents=True)
    show = api("show", {"model": model})
    manifest = next(row for row in api("tags")["models"] if row["name"] == model)
    metadata = {"profile": profile, "runPurpose": purpose, "workloadNote": note,
        "selectedCaseIDs": [c["id"] for c in cases], "expectedTrials": len(cases) * repeats,
        "job": job(profile, [wire_case(c) for c in cases]), "corpusSHA256": digest(CORPUS),
        "sourceSHA256": {p: digest(ROOT / p) for p in SOURCES}, "bridgeSHA256": digest(BRIDGE),
        "ollama": api("version"), "manifest": manifest, "model": show,
        "hardware": {"platform": platform.platform(), "chip": subprocess.check_output(
            ["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip(), "memoryBytes": int(
            subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True))},
        "repeats": repeats, "seed": None, "initialResident": resident,
        "orchestratorSHA256": digest(__file__),
        "measurement": "Release CLI request and production parser; shared session within warm batch; excludes AX, debounce and rendering",
        "importScope": "Text-only GGUF; no vision projector or speculative draft model loaded",
        "qualityPolicy": corpus["qualityPolicy"], "tokenUsage": "Unavailable from the production stream callback"}
    save(directory / "metadata.json", metadata)
    # One fixed calibration sentence measures cold load without mixing it into warm scored cases.
    calibration = {"id": "calibration", "category": "calibration", "sourceLanguage": "zh-Hans",
        "targetLanguage": "en", "source": "今天下午我想出去走走。"}
    rows = []
    outcome = "completed"
    try:
        api("generate", {"model": model, "prompt": "", "stream": False, "keep_alive": 0})
        if api("ps")["models"]:
            raise RuntimeError("Cold-state confirmation failed")
        save(directory / "cold.json", bridge(job(profile, [calibration]))[0])
        # A second identical request is warmup only, never part of quality or latency statistics.
        save(directory / "warmup.json", bridge(job(profile, [calibration]))[0])
        loaded = api("ps")["models"]
        if len(loaded) != 1 or loaded[0]["name"] != model:
            raise RuntimeError("Model residency unavailable or another model contaminated the run")
        save(directory / "resident.json", loaded)
        with (directory / "results.jsonl").open("x") as stream:
            wire_cases = [wire_case(c) for _ in range(repeats) for c in cases]
            for index, row in enumerate(batch(job(profile, wire_cases))):
                row["repetition"] = index // len(cases)
                stream.write(json.dumps(row, ensure_ascii=False) + "\n")
                stream.flush()
                rows.append(row)
                live = api("ps")["models"]
                if len(live) != 1 or live[0]["name"] != model:
                    raise RuntimeError("Another model loaded during the run; timings may be contaminated")
                print(profile, row["repetition"], row["id"], "OK" if row["protocolSucceeded"] else row.get("failure"),
                    "translation_ms=", row.get("translationAcceptedMilliseconds"), flush=True)
        # Human review sees the expected meaning, exact quotes and explanations, not a single
        # machine-scored reference. The model never receives these expectations.
        packet_id = uuid.uuid4().hex
        metadata["reviewPacketID"] = packet_id
        save(directory / "metadata.json", metadata)
        save(directory / "review.json", {"packetID": packet_id, "runPurpose": purpose, "cases": [
            {"fixture": case, "results": [r for r in rows if r["id"] == case["id"]],
             "humanReview": {"meaning": None, "naturalness": None, "alignment": None,
                 "meaningCoverage": None, "segmentationUsefulness": None, "explanationAccuracy": None,
                 "criticalErrors": [], "notes": ""}}
            for case in cases]})
    except BaseException as error:
        outcome = "failed"
        save(directory / "failed.json", {"error": str(error), "type": type(error).__name__})
        raise
    finally:
        save(directory / "summary.json", {"runPurpose": purpose, "runStatus": outcome,
            "languages": summarize(rows, cases, repeats)})
        # Only the evaluation alias is unloaded. Other apps must not share that alias during
        # the run; a localhost server cannot attribute residency to a particular client.
        api("generate", {"model": model, "prompt": "", "stream": False, "keep_alive": 0})
        save(directory / "final-resident.json", api("ps"))
    print(directory, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "run"])
    parser.add_argument("--profile", choices=PROFILES, default="qwen-joint")
    parser.add_argument("--cases", help="Comma-separated stable fixture IDs; default: all corpus cases")
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--purpose", choices=["formal", "smoke"], default="formal")
    parser.add_argument("--note", default="", help="Background workload or other measurement caveats")
    args = parser.parse_args()
    if not 1 <= args.repeats <= 5:
        parser.error("--repeats must be 1–5")
    if args.cases and args.purpose != "smoke":
        parser.error("A partial case set requires --purpose smoke")
    if args.profile == "gemma-forensic" and args.purpose != "smoke":
        parser.error("Forensic capture is diagnostic only; use --purpose smoke")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # One scheduler owns local residency. Builds use the same repo cache and also stay serial.
    with (OUTPUT / "scheduler.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == "build":
            build()
        else:
            if not BRIDGE.is_file():
                raise RuntimeError("Build the Release bridge first")
            provenance = json.loads((OUTPUT / "bridge-provenance.json").read_text())
            if provenance["sources"] != {p: digest(ROOT / p) for p in SOURCES} or provenance["binary"] != digest(BRIDGE):
                raise RuntimeError("Bridge/source provenance changed; rebuild before measuring")
            run(args.profile, args.cases, args.repeats, args.purpose, args.note)


if __name__ == "__main__":
    main()
