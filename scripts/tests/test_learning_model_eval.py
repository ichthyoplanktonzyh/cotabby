"""Exercise evidence boundaries, including the real production parser in the Swift CLI."""
import importlib.util
import json
from pathlib import Path
import subprocess
import http.server
import threading
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "learning_model_eval.py"
SPEC = importlib.util.spec_from_file_location("learning_model_eval", SCRIPT)
eval = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(eval)


class EvidenceTests(unittest.TestCase):
    def test_missing_latency_is_not_zero_or_abort_time(self):
        rows = [dict(sourceLanguage="zh-Hans", targetLanguage="en", protocolSucceeded=True,
                     translation="Hello", translationAcceptedMilliseconds=100, completionMilliseconds=200),
                dict(sourceLanguage="zh-Hans", targetLanguage="en", protocolSucceeded=False,
                     completionMilliseconds=900)]
        summary = eval.summarize(rows)["zh-Hans→en"]
        self.assertEqual(summary["translationAcceptedMilliseconds"]["p50"], 100)
        self.assertEqual(summary["completionMilliseconds"]["p50"], 200)
        self.assertEqual(summary["firstChunkMilliseconds"]["observed"], 0)
        self.assertIsNone(summary["firstChunkMilliseconds"]["p50"])

    def test_reviewer_expectations_are_not_sent(self):
        fixture = json.loads(eval.CORPUS.read_text())["cases"][0]
        self.assertIn("expectations", fixture)
        self.assertNotIn("expectations", eval.wire_case(fixture))

    def test_languages_are_separate(self):
        rows = [dict(sourceLanguage="zh-Hans", targetLanguage=t, protocolSucceeded=True,
                     translation="x", translationAcceptedMilliseconds=ms)
                for t, ms in [("en", 100), ("ja", 300)]]
        self.assertEqual(set(eval.summarize(rows)), {"zh-Hans→en", "zh-Hans→ja"})

    def test_missing_trials_and_partial_translation_are_explicit(self):
        fixtures = [dict(id=id, sourceLanguage="zh-Hans", targetLanguage="en") for id in ("a", "b")]
        rows = [dict(**fixtures[0], protocolSucceeded=True, finishVerified=True, translation="A"),
                dict(**fixtures[1], protocolSucceeded=False, finishVerified=True, translation="B")]
        summary = eval.summarize(rows, fixtures, repeats=2)["zh-Hans→en"]
        self.assertEqual(summary["expectedTrials"], 4)
        self.assertEqual(summary["observedTrials"], 2)
        self.assertEqual(summary["missingTrials"], 2)
        self.assertEqual(summary["uniqueCases"], 2)
        self.assertEqual(summary["translationOnlyPartial"], 1)
        self.assertEqual(summary["finishVerifiedButParserFailed"], 1)


class ProductionReplayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not eval.BRIDGE.is_file():
            raise RuntimeError("Compile scripts/learning_model_eval.py build before replay tests")

    def replay(self, pieces, finish="stop", source="你好", mode="joint"):
        fixture = dict(id="test", category="test", sourceLanguage="zh-Hans", targetLanguage="en", source=source)
        payload = dict(example=fixture, finishReason=finish, mode=mode,
                       deltas=[dict(milliseconds=ms, text=text) for ms, text in pieces])
        return eval.bridge(payload, "replay")[0]

    def test_full_translation_line_defines_visible_time(self):
        row = self.replay([(10, '{"type":"translation","text":"Hel'),
                           (100, 'lo"}\n'),
                           (200, '{"type":"chunk","source":["你好"],"target":["Hello"],"explanation":"问候"}\n')])
        self.assertEqual(row["firstContentMilliseconds"], 10)
        self.assertEqual(row["translationAcceptedMilliseconds"], 100)
        self.assertEqual(row["firstChunkMilliseconds"], 200)
        self.assertTrue(row["protocolSucceeded"])
        self.assertEqual(row["sourceLetterCoverage"], 1)

    def test_bad_later_record_keeps_translation(self):
        row = self.replay([(70, '{"type":"translation","text":"Hello"}\nnot-json\n')])
        self.assertEqual(row["translation"], "Hello")
        self.assertEqual(row["translationAcceptedMilliseconds"], 70)
        self.assertFalse(row["protocolSucceeded"])
        self.assertTrue(row["failure"])

    def test_token_limit_does_not_become_complete_success(self):
        row = self.replay([(20, '{"type":"translation","text":"Hello"}\n')], finish="length")
        self.assertEqual(row["translation"], "Hello")
        self.assertFalse(row["protocolSucceeded"])
        self.assertFalse(row["finishVerified"])

    def test_overlap_rejected_instead_of_wrong_highlight(self):
        line = '{"type":"chunk","source":["你好"],"target":["Hello"],"explanation":"问候"}\n'
        row = self.replay([(50, '{"type":"translation","text":"Hello"}\n' + line + line)])
        self.assertFalse(row["protocolSucceeded"])
        self.assertEqual(len(row["chunks"]), 1)

    def test_forensic_capture_never_relabels_invalid_analysis_as_ui_success(self):
        row = self.replay([(30, '{"type":"translation":"Hello"}\n'),
                           (100, '{"type":"chunk","source":["你好"],"target":["Hello"],"explanation":"问候"}\n')],
                          mode="joint-forensic")
        self.assertEqual(row["parserStoppedMilliseconds"], 30)
        self.assertIn('"type":"chunk"', row["rawOutput"])
        self.assertTrue(row["finishVerified"])
        self.assertFalse(row["protocolSucceeded"])
        self.assertNotIn("translation", row)

    def test_forensic_stop_time_includes_invalid_final_line(self):
        row = self.replay([(70, '{"type":"translation":"Hello"}')], mode="joint-forensic")
        self.assertEqual(row["parserStoppedMilliseconds"], 70)
        self.assertFalse(row["protocolSucceeded"])

    def test_forensic_stop_time_includes_missing_chunks(self):
        row = self.replay([(80, '{"type":"translation","text":"Hello"}\n')], mode="joint-forensic")
        self.assertEqual(row["parserStoppedMilliseconds"], 80)
        self.assertEqual(row["translation"], "Hello")
        self.assertFalse(row["protocolSucceeded"])

    def test_redirect_is_refused_before_fixture_reaches_second_server(self):
        received = []

        class Destination(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                received.append(self.path)
                self.send_response(200)
                self.end_headers()

            do_POST = do_GET

            def log_message(self, *args):
                pass

        destination = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Destination)

        class Redirect(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                self.rfile.read(int(self.headers.get("Content-Length", "0")))
                self.send_response(302)
                self.send_header("Location", f"http://127.0.0.1:{destination.server_port}/v1/chat/completions")
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, *args):
                pass

        origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Redirect)
        threads = [threading.Thread(target=server.serve_forever, daemon=True)
                   for server in (destination, origin)]
        for thread in threads:
            thread.start()
        try:
            fixture = eval.wire_case(json.loads(eval.CORPUS.read_text())["cases"][0])
            payload = eval.job("qwen-joint", [fixture])
            payload["baseURL"] = f"http://127.0.0.1:{origin.server_port}/v1"
            row = eval.bridge(payload)[0]
            self.assertFalse(row["protocolSucceeded"])
            self.assertTrue(row["failure"])
            self.assertEqual(received, [])
        finally:
            for server in (origin, destination):
                server.shutdown()
                server.server_close()
            for thread in threads:
                thread.join()


if __name__ == "__main__":
    unittest.main()
