"""Google streaming boundary tests; no credentials, provider calls or app runtime."""
import io
import json
import sys
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import learning_alignment_cloud_pair_eval as experiment

CASE = dict(id="fixture", sourceLanguage="zh-Hans", targetLanguage="en", source="你好", translation="Hello.")


def stream(*packets):
    return io.BytesIO("".join("data: " + json.dumps(packet) + "\n\n" for packet in packets).encode())


class GoogleBoundaryTests(unittest.TestCase):
    def query(self, response):
        with patch.object(experiment.CLOUD.base.OPENER, "open", return_value=response):
            return experiment.google_query(CASE, experiment.PROMPTS["v2"], "fake-secret")

    def test_incremental_parts_end_on_stop_and_eof(self):
        row, packets, body = self.query(stream(
            {"candidates": [{"content": {"parts": [{"text": '[["你好",'}]}}]},
            {"candidates": [{"content": {"parts": [{"text": '"Hello."]]'}]}, "finishReason": "STOP"}],
             "usageMetadata": {"totalTokenCount": 12}, "modelVersion": "gemma-4-31b-it"}))
        self.assertEqual(row["rawOutput"], '[["你好","Hello."]]')
        self.assertTrue(row["streamDone"])
        self.assertIsNone(row["error"])
        self.assertIsNotNone(row["firstContentMs"])
        self.assertEqual(row["usage"]["totalTokenCount"], 12)
        self.assertEqual(body["generationConfig"]["thinkingConfig"], {"thinkingLevel": "minimal"})

    def test_partial_array_does_not_pass_finish_check(self):
        row, _, _ = self.query(stream({"candidates": [{"content": {"parts": [{"text": '[['}]},
                                                      "finishReason": "MAX_TOKENS"}]}))
        self.assertTrue(row["streamDone"])
        self.assertIn("Incomplete finish", row["error"])

    def test_eof_without_terminal_finish_is_incomplete(self):
        row, _, _ = self.query(stream({"candidates": [{"content": {"parts": [{"text": '[["你好","Hello."]]'}]}}]}))
        self.assertIsNotNone(row["error"])

    def test_thought_parts_do_not_become_final_alignment(self):
        row, _, _ = self.query(stream({"candidates": [{"content": {"parts": [
            {"text": "private intermediate", "thought": True}, {"text": '[["你好","Hello."]]'}]},
            "finishReason": "STOP"}]}))
        self.assertNotIn("private intermediate", row["rawOutput"])
        self.assertEqual(row["thoughtPartCount"], 1)
        self.assertIn("Unexpected thinking", row["error"])

    def test_echoed_secret_is_redacted_from_text_and_packets(self):
        row, packets, _ = self.query(stream({"candidates": [{"content": {"parts": [{"text": "fake-secret"}]},
                                                               "finishReason": "STOP"}]}))
        self.assertNotIn("fake-secret", json.dumps([row, packets]))

    def test_quota_error_is_observed_without_retry(self):
        payload = {"error": {"status": "RESOURCE_EXHAUSTED", "message": "quota fake-secret"}}
        failure = urllib.error.HTTPError("https://generativelanguage.googleapis.com", 429, "quota", {},
                                         io.BytesIO(json.dumps(payload).encode()))
        with patch.object(experiment.CLOUD.base.OPENER, "open", side_effect=failure) as opened:
            row, _, _ = experiment.google_query(CASE, experiment.PROMPTS["v2"], "fake-secret")
        self.assertEqual(opened.call_count, 1)
        self.assertEqual(row["httpStatus"], 429)
        self.assertFalse(row["streamDone"])
        self.assertNotIn("fake-secret", json.dumps(row))

    def test_api_key_is_header_only_and_host_is_fixed(self):
        request = experiment.google_request(":streamGenerateContent?alt=sse", "fake-secret", {})
        self.assertNotIn("fake-secret", request.full_url)
        self.assertEqual(request.get_header("X-goog-api-key"), "fake-secret")
        with self.assertRaises(AssertionError):
            experiment.google_request("https://unrelated.example", "fake-secret")

    def test_prompt_change_is_only_the_two_guard_lines(self):
        self.assertEqual(experiment.PROMPTS["v2"].replace(experiment.GUARDS, ""), experiment.PROMPTS["v1"])
        self.assertEqual(experiment.PROMPTS["v2"].count(experiment.GUARDS), 1)


if __name__ == "__main__":
    unittest.main()
