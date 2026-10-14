#!/usr/bin/env python3
"""Same-session v1/v2 comparison on two explicitly authorized cloud providers.

This experiment owns scheduling and Google SSE transport, and reuses the previous fixed-host
DeepSeek transport and standalone production parser. It does not read application/editor state.
Secrets enter through masked getpass and never enter request evidence, command arguments or files.
Each provider stops on transport failure rather than silently substituting a model or retrying.
"""
import datetime
import fcntl
import getpass
import gzip
import json
import random
import shutil
import time
import urllib.error
import urllib.request

import learning_alignment_source_anchor_eval as anchor

ROOT = anchor.ROOT
CLOUD = anchor.cloud
GOOGLE_MODEL = "gemma-4-31b-it"
GOOGLE_HOST = "https://generativelanguage.googleapis.com"
GUARDS = ("每项必须恰好包含两个非空字符串。\n"
          "如果一个意思只能对应不连续文字，优先合并为自然的较大连续片段；无法可靠合并时省略，不得删词或拼接片段。\n")
PROMPTS = {"v1": anchor.SYSTEM,
           "v2": anchor.SYSTEM.replace("只返回 JSON 二维数组", GUARDS + "只返回 JSON 二维数组")}


def google_request(route, credential, body=None):
    """Keep authentication out of URLs; inherited opener refuses redirects and all proxies."""
    assert route in ("", ":streamGenerateContent?alt=sse")
    return urllib.request.Request(GOOGLE_HOST + "/v1beta/models/" + GOOGLE_MODEL + route,
                                  data=None if body is None else json.dumps(body).encode(),
                                  headers={"Content-Type": "application/json", "x-goog-api-key": credential})


def google_query(case, system, credential):
    body = {"systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": json.dumps(
                {key: case[key] for key in ["sourceLanguage", "targetLanguage", "source", "translation"]},
                ensure_ascii=False)}]}],
            "generationConfig": {"temperature": .3, "topP": 1, "maxOutputTokens": 4096,
                                 "thinkingConfig": {"thinkingLevel": "minimal"}}}
    row = dict(caseID=case["id"], rawOutput="", thinking="", firstContentMs=None, completionMs=None,
               finishReason=None, streamDone=False, error=None, usage=None, providerModels=[],
               thoughtPartCount=0, candidateCount=0)
    packets = []
    began = time.monotonic()
    elapsed = lambda: (time.monotonic() - began) * 1000
    try:
        with CLOUD.base.OPENER.open(google_request(":streamGenerateContent?alt=sse", credential, body), timeout=60) as response:
            for event in CLOUD.sse(response):
                stamp = elapsed()
                if stamp > 180000:
                    raise TimeoutError("Google request exceeds total deadline")
                if event is None:
                    continue
                packet = CLOUD.redact(json.loads(event), credential)
                packets.append(dict(ms=stamp, packet=packet))
                if "error" in packet:
                    raise ValueError("Provider stream error")
                if packet.get("modelVersion") and packet["modelVersion"] not in row["providerModels"]:
                    row["providerModels"].append(packet["modelVersion"])
                candidates = packet.get("candidates", [])
                row["candidateCount"] = max(row["candidateCount"], len(candidates))
                for candidate in candidates:
                    if candidate.get("index", 0) != 0:
                        continue
                    if candidate.get("finishReason"):
                        row["finishReason"] = candidate["finishReason"]
                    for part in candidate.get("content", {}).get("parts", []):
                        text = part.get("text", "")
                        if part.get("thought"):
                            row["thoughtPartCount"] += 1
                            row["thinking"] = "unexpected-thought-output"
                            continue
                        if text:
                            if row["firstContentMs"] is None:
                                row["firstContentMs"] = stamp
                            row["rawOutput"] += text
                            if len(row["rawOutput"].encode()) > 96000:
                                raise ValueError("Output exceeds evidence budget")
                if packet.get("usageMetadata") is not None:
                    row["usage"] = packet["usageMetadata"]
                if packet.get("promptFeedback", {}).get("blockReason"):
                    raise ValueError("Prompt blocked: " + packet["promptFeedback"]["blockReason"])
        # Google SSE has no [DONE] marker: normal EOF plus STOP is the completion boundary.
        row["streamDone"] = True
        if row["finishReason"] != "STOP":
            row["error"] = "Incomplete finish: " + str(row["finishReason"])
        if row["thinking"]:
            row["error"] = "Unexpected thinking despite minimal mode"
    except urllib.error.HTTPError as error:
        row["httpStatus"] = error.code
        row["error"] = "HTTP " + str(error.code)
        # Store only sanitized diagnostic fields, never the request URL/headers or arbitrary body.
        try:
            diagnostic = json.loads(error.read()).get("error", {})
            row["providerError"] = CLOUD.redact({key: diagnostic.get(key) for key in ["status", "message"]}, credential)
        except (ValueError, UnicodeError):
            pass
    except Exception as error:
        row["error"] = CLOUD.redact(type(error).__name__ + ": " + str(error)[:200], credential)
    row["completionMs"] = elapsed()
    return row, packets, body


def checked_row(parser, row, case, provider):
    anchor.validate(parser, row, case)
    complete = row["streamDone"] and row["finishReason"] == ("STOP" if provider == "google" else "stop")
    row["productionUsable"] = bool(row["productionParser"]["succeeded"] and complete and not row["thinking"] and not row["error"])
    if provider == "google":
        row["productionUsable"] = row["productionUsable"] and row["candidateCount"] == 1
    return row


def run():
    cases = json.loads((ROOT / "build/LanguageLearning/SourceAnchorCloud/20261014T042408Z/corpus.json").read_text())["cases"]
    parent = ROOT / "build/LanguageLearning/CloudPairEval"
    parent.mkdir(parents=True, exist_ok=True)
    with (parent / "experiment.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        directory = parent / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        directory.mkdir()
        (directory / "packets").mkdir()
        sources = list(dict.fromkeys(anchor.SOURCES + ["scripts/learning_alignment_cloud_pair_eval.py"]))
        for name in sources:
            target = directory / "source-snapshot" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        shutil.copy2(ROOT / "scripts/learning_alignment_parse.swift", directory / "main.swift")
        parser = anchor.prepare_parser(directory)
        CLOUD.base.save(directory / "corpus.json", dict(cases=cases))
        CLOUD.base.save(directory / "prompts.json", PROMPTS)
        credentials = {"deepseek": getpass.getpass("DeepSeek API key (memory only): "),
                       "google": getpass.getpass("Google API key (memory only): ")}
        availability = {}
        for provider in credentials:
            request = CLOUD.cloud_request("/models", credentials[provider]) if provider == "deepseek" else google_request("", credentials[provider])
            with CLOUD.base.OPENER.open(request, timeout=30) as response:
                availability[provider] = CLOUD.redact(json.load(response), credentials[provider])
        assert CLOUD.MODEL in [m["id"] for m in availability["deepseek"]["data"]]
        assert availability["google"]["name"] == "models/" + GOOGLE_MODEL
        metadata = dict(status="running", expectedTrials=120, trialsPerArm=30, repetitions=1,
                        providers=availability, models=dict(deepseek=CLOUD.MODEL, google=GOOGLE_MODEL),
                        settings=dict(temperature=.3, maxOutputTokens=4096, thinking=dict(deepseek="disabled", google="minimal"),
                                      googleTopP=1, schemaEnforcement=False),
                        changeOnly=GUARDS, schedulingSeed=14, samplingSeed=None, googleMinimumStartIntervalSeconds=6.1,
                        sourceHashes={name: CLOUD.base.digest(ROOT / name) for name in sources},
                        transmission="Only fixed synthetic source/translation JSON and frozen system prompts to two fixed official HTTPS hosts",
                        retryPolicy="No automatic retries; stop the affected provider on transport errors")
        CLOUD.base.save(directory / "metadata.json", metadata)
        print("RESULT_DIRECTORY", directory, flush=True)
        schedule = []
        rng = random.Random(14)
        for case in cases:
            arms = [(provider, arm) for provider in credentials for arm in PROMPTS]
            rng.shuffle(arms)
            schedule.extend(dict(caseID=case["id"], provider=provider, arm=arm) for provider, arm in arms)
        CLOUD.base.save(directory / "schedule.json", schedule)
        stopped, rows, google_started = {}, [], 0
        with (directory / "results.jsonl").open("x") as output:
            for job in schedule:
                provider, arm = job["provider"], job["arm"]
                if provider in stopped:
                    continue
                case = next(c for c in cases if c["id"] == job["caseID"])
                if provider == "google":
                    time.sleep(max(0, 6.1 - (time.monotonic() - google_started)))
                    google_started = time.monotonic()
                    row, packets, body = google_query(case, PROMPTS[arm], credentials[provider])
                else:
                    CLOUD.base.SYSTEM = PROMPTS[arm]
                    message = json.dumps({k: case[k] for k in ["sourceLanguage", "targetLanguage", "source", "translation"]}, ensure_ascii=False)
                    row, packets, body = CLOUD.query_cloud(case, "C", message, credentials[provider])
                row.update(provider=provider, model=metadata["models"][provider], arm=arm, repetition=0,
                           trialID=provider + "-" + arm + "-" + case["id"])
                checked_row(parser, row, case, provider)
                evidence = dict(result=row, request=body, packets=packets)
                for credential in credentials.values():
                    evidence = CLOUD.redact(evidence, credential)
                with gzip.open(directory / "packets" / (row["trialID"] + ".json.gz"), "wt", encoding="utf-8") as stream:
                    json.dump(evidence, stream, ensure_ascii=False)
                output.write(json.dumps(evidence["result"], ensure_ascii=False) + "\n")
                output.flush()
                rows.append(evidence["result"])
                print(row["trialID"], "parser=" + str(row["productionUsable"]), "ms=" + str(round(row["completionMs"])),
                      "error=" + str(row["error"]), flush=True)
                if row.get("httpStatus") or not row["streamDone"]:
                    stopped[provider] = row["trialID"]
        metadata.update(status="complete" if len(rows) == 120 else "partial_provider_stopped",
                        completedTrials=len(rows), stoppedProviders=stopped)
        CLOUD.base.save(directory / "metadata.json", metadata)
        for path in directory.rglob("*"):
            if path.is_file() and (path.suffix in [".json", ".jsonl"] or path.suffix == ".gz"):
                text = gzip.open(path, "rt", encoding="utf-8").read() if path.suffix == ".gz" else path.read_text()
                assert all(key not in text for key in credentials.values())
        print("COMPLETED", len(rows), "PRODUCTION_USABLE", sum(r["productionUsable"] for r in rows), flush=True)


if __name__ == "__main__":
    run()
