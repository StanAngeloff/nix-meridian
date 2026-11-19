import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import links

# As home/apps/claude-code/footer-links.nix has it.
FOOTER_LINKS = [
    {
        "type": "regex",
        "pattern": "\\bsc-(?<id>\\d+)\\b",
        "url": "https://app.shortcut.com/story/{id}",
        "label": "sc-{id}",
    }
]
RULES = links.compile_rules(FOOTER_LINKS)
STORY = "https://app.shortcut.com/story/"


class UrlsTest(unittest.TestCase):
    def test_an_issue_links_its_own_characters_only(self):
        urls = links.urls("sc-123/finish", RULES)
        self.assertEqual(urls[:6], [STORY + "123"] * 6)
        self.assertFalse(any(urls[6:]))

    def test_every_issue_in_the_text_links_to_itself(self):
        urls = links.urls("sc-1 and sc-22", RULES)
        self.assertEqual(urls[0], STORY + "1")
        self.assertEqual(urls[-1], STORY + "22")
        self.assertFalse(any(urls[4:9]))

    def test_only_a_whole_word_links(self):
        for text in ("xsc-123", "sc-123a", "sc-", "sc-١٢"):
            self.assertFalse(any(links.urls(text, RULES)), text)


class CompileTest(unittest.TestCase):
    def test_lookbehinds_stay_lookbehinds(self):
        rules = links.compile_rules(
            [{"type": "regex", "pattern": "(?<=#)(?<n>\\d+)", "url": "u/{n}"}]
        )
        self.assertEqual(links.urls("#42", rules), ["", "u/42", "u/42"])

    def test_a_pattern_python_cannot_read_is_left_out(self):
        unreadable = {"type": "regex", "pattern": "\\p{L}+", "url": "u"}
        self.assertEqual(len(links.compile_rules([unreadable] + FOOTER_LINKS)), 1)

    def test_a_captured_value_cannot_end_the_escape_sequence_it_travels_in(self):
        rules = links.compile_rules(
            [{"type": "regex", "pattern": "ref:(?<ref>\\S+)", "url": "u/{ref}"}]
        )
        self.assertEqual(links.urls("ref:a/b\x1b", rules)[0], "u/a%2Fb%1B")


class LoadTest(unittest.TestCase):
    def test_the_rules_come_from_the_file_beside_the_navigator(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "links.json"
            path.write_text(json.dumps(FOOTER_LINKS))
            with mock.patch.object(links, "RULES_PATH", path):
                self.assertEqual(links.urls("sc-7", links.load())[0], STORY + "7")

    def test_without_the_file_nothing_links(self):
        with mock.patch.object(links, "RULES_PATH", Path("/nonexistent/links.json")):
            self.assertEqual(links.load(), [])


if __name__ == "__main__":
    unittest.main()
