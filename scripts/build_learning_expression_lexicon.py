#!/usr/bin/env python3
"""Build an offline expression subset from Kaikki/Wiktextract JSONL, preserving provenance.

This development-only fetch never runs in the app. Offline expression recognition and lookup
have no app-managed HTTP transport. Definitions retain CC BY-SA attribution; quotations/audio
are intentionally not copied. Word fallback belongs to the system's configured dictionaries.
"""
import argparse
import concurrent.futures
import hashlib
import html
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request

LANGUAGES = {"English": "en", "Spanish": "es", "French": "fr", "German": "de", "Italian": "it",
             "Portuguese": "pt", "Dutch": "nl", "Russian": "ru", "Chinese": "zh", "Japanese": "ja",
             "Korean": "ko", "Hindi": "hi", "Arabic": "ar"}
LICENSE = "https://creativecommons.org/licenses/by-sa/4.0/"

def links(url):
    data = urllib.request.urlopen(url, timeout=60).read().decode()
    return [(urllib.parse.urljoin(url, u), html.unescape(re.sub("<[^>]+>", "", t)))
            for u, t in re.findall(r'<a[^>]+href="([^"]+)"[^>]*>(.*?)</a>', data, re.S)]

def download(url, cache):
    path = cache / (hashlib.sha256(url.encode()).hexdigest()[:16] + ".jsonl")
    if not path.exists():
        with urllib.request.urlopen(url, timeout=90) as source, path.with_suffix(".part").open("wb") as dest:
            while data := source.read(1024 * 1024):
                dest.write(data)
        path.with_suffix(".part").replace(path)
    return {"url": url, "file": str(path), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

def restore_pinned(provenance, cache):
    """Recover the tracked version; a changed upstream file is a failure, never an update."""
    recovered = []
    for source in provenance["sources"]:
        current = download(source["url"], cache)
        if current["sha256"] != source["sha256"] or current["bytes"] != source["bytes"]:
            raise ValueError("Pinned data changed: " + source["url"])
        recovered.append(current)
    return recovered

def fetch(cache):
    urls = []
    for name in LANGUAGES:
        root = "https://kaikki.org/dictionary/" + name + "/index.html"
        pages = [u for u, label in links(root) if any("part-of-speech " + pos in label for pos in ["Phrase", "Prepositional phrase", "Conjunction", "Preposition"])]
        for page in pages:
            urls.extend(u for u, label in links(page) if label.strip() == "Download")
    # English phrasal verbs are filed as Verb, not Phrase. Walk the category index rather than
    # silently missing this important class or downloading several GB of unrelated verb entries.
    root = "https://kaikki.org/dictionary/English/categories-other/index.html"
    parents = [(u, label) for u, label in links(root) if "English oaths" in label]
    for parent, _ in parents:
        for group, label in links(parent):
            if "phrasal verbs" not in label:
                continue
            if re.search(r"\(\d+ senses\)$", label):
                leaves = [(group, label)]
            else:
                leaves = [(u, l) for u, l in links(group)
                          if "phrasal verbs" in l and re.search(r"\(\d+ senses\)$", l)]
            for leaf, _ in leaves:
                urls.extend(u for u, label in links(leaf) if label.strip() == "Download")
    # Idioms are frequently Verb or Noun senses, not Phrase entries. The tag index is
    # partitioned alphabetically; inspect each small index rather than guessing a page range.
    groups = [u for u, _ in links("https://kaikki.org/dictionary/English/tags/index.html")
              if "/tags/" in u and u.endswith(".html") and not u.endswith("index.html")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        partitions = list(pool.map(links, groups))
    for partition in partitions:
        for page, tag in partition:
            if tag.startswith("idiomatic ("):
                urls.extend(u for u, label in links(page) if label.strip() == "Download")
    # A small reviewed supplement covers common collocations absent from those categories.
    # These are data sources, not special cases in the runtime recognition algorithm.
    for term in ["take care of", "make a decision", "keep in mind"]:
        page = ("https://kaikki.org/dictionary/English/meaning/" + term[0] + "/" + term[:2] + "/"
                + urllib.parse.quote(term) + ".html")
        urls.extend(u for u, label in links(page) if label.strip() == "Download")
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        return list(pool.map(lambda u: download(u, cache), sorted(set(urls))))

def key(text):
    return " ".join(text.lower().replace("’", "'").split())

def build(sources):
    entries = {}
    redirects = []
    for source in sources:
        with open(source["file"], encoding="utf-8") as stream:
            for line in stream:
                record = json.loads(line)
                language = record.get("lang_code")
                word = record.get("word", "").strip()
                if language not in LANGUAGES.values() or not word or len(word.encode()) > 256:
                    continue
                # English and other spaced scripts need multiword heads. CJK phrase heads can
                # be unspaced, but their source is the Phrase category, not a whole word lexicon.
                if " " not in word and not (language in {"zh", "ja", "ko"} and record.get("pos") == "phrase" and len(word) > 1):
                    continue
                if any(ord(c) < 32 for c in word) or len(word.split()) > 12:
                    continue
                senses = []
                for sense in record.get("senses", []):
                    if sense.get("form_of") or sense.get("alt_of"):
                        for target in sense.get("form_of", []) + sense.get("alt_of", []):
                            if target.get("word"):
                                redirects.append(((language, target["word"]), word))
                        continue
                    glosses = [s.strip() for s in sense.get("glosses", []) if isinstance(s, str) and s.strip()]
                    if glosses:
                        senses.append({"partOfSpeech": record.get("pos", "expression"),
                                       "definitions": glosses[:5], "labels": sense.get("tags", [])[:8]})
                if not senses:
                    continue
                identifier = hashlib.sha256((language + ":" + word).encode()).hexdigest()[:16]
                entry = entries.setdefault((language, word), {"id": identifier, "language": language,
                    "headword": word, "forms": [], "senses": [],
                    "sourceURL": "https://en.wiktionary.org/wiki/" + urllib.parse.quote(word.replace(" ", "_"), safe="_")})
                for form in record.get("forms", []):
                    text = form.get("form", "").strip()
                    if (text and len(text.encode()) <= 256 and text != word and text not in entry["forms"]
                            and not any(ord(c) < 32 for c in text)
                            and (" " not in word or len(text.split()) >= 2)
                            and (language not in {"zh", "ja", "ko"} or len(text) >= 2)):
                        entry["forms"].append(text)
                for sense in senses:
                    if sense not in entry["senses"]:
                        entry["senses"].append(sense)
    for target, alias in redirects:
        if (target in entries and alias not in entries[target]["forms"]
                and (" " not in target[1] or len(alias.split()) >= 2)):
            entries[target]["forms"].append(alias)
    for entry in entries.values():
        entry["forms"] = sorted(set(entry["forms"]))
    return sorted(entries.values(), key=lambda e: (e["language"], e["headword"]))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--fetch", action="store_true", help="Discover current upstream data for a reviewed update")
    source.add_argument("--restore-pinned", action="store_true", help="Restore exact tracked source URLs/checksums")
    parser.add_argument("--cache", type=Path, default=Path("build/LanguageLearning/LearningUnitStudy/kaikki"))
    parser.add_argument("--output", type=Path, default=Path("Cotabby/Resources/learning-expressions.json"))
    parser.add_argument("--version", help="New resource version, required for --fetch")
    parser.add_argument("--extraction", help="Reviewed upstream extraction/dump dates, required for --fetch")
    args = parser.parse_args()
    pinned = json.loads(Path("Cotabby/Resources/learning-expressions.provenance.json").read_text())
    if args.fetch and (not args.version or not args.extraction or args.version == pinned["version"]):
        parser.error("--fetch requires a new --version and reviewed --extraction dates")
    args.cache.mkdir(parents=True, exist_ok=True)
    manifest = args.cache / "sources.json"
    if args.restore_pinned:
        manifest.write_text(json.dumps(restore_pinned(pinned, args.cache), indent=2) + "\n")
    if args.fetch:
        manifest.write_text(json.dumps(fetch(args.cache), indent=2) + "\n")
    if not manifest.exists():
        parser.error("Missing source cache: use --restore-pinned for the tracked version, or --fetch for an update")
    sources = json.loads(manifest.read_text())
    for source in sources:
        if hashlib.sha256(Path(source["file"]).read_bytes()).hexdigest() != source["sha256"]:
            raise ValueError("Cached data changed: " + source["url"])
    entries = build(sources)
    resource = {"version": args.version if args.fetch else pinned["version"], "attribution": "Wiktionary contributors; extracted by Wiktextract / Kaikki; expression subset prepared by Cotabby.",
                "licenseURL": LICENSE, "entries": entries}
    encoded = (json.dumps(resource, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    digest = hashlib.sha256(encoded).hexdigest()
    if not args.fetch and (len(encoded) != pinned["bytes"] or digest != pinned["sha256"]):
        raise ValueError("Rebuilt resource differs from the pinned version; destination was not changed")
    temporary = args.output.with_name("." + args.output.name + ".tmp")
    temporary.write_bytes(encoded)
    temporary.replace(args.output)
    counts = {code: sum(e["language"] == code for e in entries) for code in LANGUAGES.values()}
    provenance = {"version": resource["version"], "licenseURL": LICENSE, "sourceEdition": "English Wiktionary",
                  "extraction": args.extraction if args.fetch else pinned["extraction"], "sources": [{k: v for k, v in s.items() if k != "file"} for s in sources],
                  "entriesByLanguage": counts, "bytes": args.output.stat().st_size,
                  "sha256": digest,
                  "transformation": "Subset of Phrase, Prepositional phrase, multiword Conjunction/Preposition, English phrasal-verb and idiomatic categories, plus reviewed collocation supplements. Retain glosses, POS, labels, explicit forms and source URL; omit citations, examples and media."}
    args.output.with_suffix(".provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"counts": counts, "bytes": provenance["bytes"], "sources": len(sources)}))

if __name__ == "__main__":
    main()
