"""Offline data import regressions: explicit forms, provenance and non-destructive reproduction."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_learning_expression_lexicon as lexicon


class LearningLexiconImportTests(unittest.TestCase):
    def test_single_word_forms_and_example_quotes_are_not_expression_data(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.jsonl"
            records = [
                {"lang_code": "en", "word": "look forward to", "pos": "verb",
                 "forms": [{"form": "look"}, {"form": "looking forward to"}],
                 "senses": [{"glosses": ["To anticipate."], "examples": [{"text": "A quotation."}]}]},
                {"lang_code": "en", "word": "looked forward to", "pos": "verb",
                 "senses": [{"form_of": [{"word": "look forward to"}]}]},
            ]
            path.write_text("\n".join(json.dumps(record) for record in records))
            entries = lexicon.build([{"file": str(path)}])
            self.assertEqual(len(entries), 1)
            self.assertEqual(entries[0]["forms"], ["looked forward to", "looking forward to"])
            self.assertNotIn("quotation", json.dumps(entries).lower())
            self.assertEqual(entries[0]["senses"][0]["definitions"], ["To anticipate."])

    def test_changed_pinned_source_is_rejected(self):
        pinned = {"sources": [{"url": "https://example.invalid/source", "sha256": "old", "bytes": 1}]}
        with mock.patch.object(lexicon, "download", return_value={"sha256": "new", "bytes": 1}):
            with self.assertRaisesRegex(ValueError, "Pinned data changed"):
                lexicon.restore_pinned(pinned, Path("unused"))

    def test_changed_transformation_leaves_destination_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "cache"
            cache.mkdir()
            (cache / "sources.json").write_text("[]")
            destination = Path(directory) / "expressions.json"
            destination.write_text("existing resource")
            with mock.patch.object(sys, "argv", ["lexicon", "--cache", str(cache), "--output", str(destination)]), \
                 mock.patch.object(lexicon, "build", return_value=[]):
                with self.assertRaisesRegex(ValueError, "destination was not changed"):
                    lexicon.main()
            self.assertEqual(destination.read_text(), "existing resource")

    def test_updating_cannot_silently_reuse_the_old_version(self):
        with mock.patch.object(sys, "argv", ["lexicon", "--fetch"]), \
             mock.patch.object(lexicon, "fetch") as fetch, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as failure:
                lexicon.main()
            self.assertEqual(failure.exception.code, 2)
            fetch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
