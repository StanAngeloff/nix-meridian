import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import main
import render


class BudgetFrom(unittest.TestCase):
    def test_reserves_four_columns_for_indent_and_margin(self):
        self.assertEqual(main.budget_from({"COLUMNS": "50"}), 46)
        self.assertEqual(main.budget_from({"COLUMNS": "80"}), 76)

    def test_assumes_a_wide_terminal_when_columns_is_absent(self):
        self.assertEqual(main.budget_from({}), 196)

    def test_assumes_a_wide_terminal_when_columns_is_zero(self):
        # A child of Claude Code that is not a status line reports COLUMNS=0.
        self.assertEqual(main.budget_from({"COLUMNS": "0"}), 196)

    def test_ignores_a_value_that_is_not_a_number(self):
        self.assertEqual(main.budget_from({"COLUMNS": "wide"}), 196)

    def test_floors_the_budget_for_absurdly_narrow_terminals(self):
        self.assertEqual(main.budget_from({"COLUMNS": "10"}), 20)


class PublishRateLimits(unittest.TestCase):
    def test_writes_the_limits_object_verbatim(self):
        limits = {
            "five_hour": {"used_percentage": 42.0},
            "seven_day": {"used_percentage": 7.0},
        }
        with tempfile.TemporaryDirectory() as directory:
            main.publish_rate_limits({"rate_limits": limits}, Path(directory))
            written = json.loads((Path(directory) / "usage-activity").read_text())
        self.assertEqual(written, limits)

    def test_leaves_no_scratch_file_behind(self):
        with tempfile.TemporaryDirectory() as directory:
            main.publish_rate_limits(
                {"rate_limits": {"five_hour": {}}}, Path(directory)
            )
            self.assertEqual(sorted(os.listdir(directory)), ["usage-activity"])

    def test_writes_nothing_when_the_payload_has_no_rate_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            main.publish_rate_limits({}, Path(directory))
            self.assertEqual(os.listdir(directory), [])

    def test_survives_an_unwritable_directory(self):
        main.publish_rate_limits(
            {"rate_limits": {"five_hour": {}}}, Path("/nonexistent/nowhere")
        )


class GitBranch(unittest.TestCase):
    def test_reports_the_branch_of_a_repository(self):
        # A throwaway repository rather than this file's own checkout, so the test passes the same
        # way in a Nix build sandbox (no .git in the unpacked source) as on a developer's machine.
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run(
                ["git", "init", "--quiet", "--initial-branch=probe", directory],
                check=True,
            )
            self.assertEqual(main.git_branch(directory), "probe")

    def test_is_empty_outside_a_repository(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(main.git_branch(directory), "")


class LineFor(unittest.TestCase):
    PAYLOAD = {
        "model": {"id": "claude-opus-4-6[1m]", "display_name": "Opus 4.6 (1M context)"},
        "context_window": {"context_window_size": 1_000_000, "used_percentage": 34.0},
        "rate_limits": {
            "five_hour": {"used_percentage": 42.0},
            "seven_day": {"used_percentage": 7.0},
        },
    }

    def test_renders_everything_on_a_wide_terminal(self):
        line = render.ANSI_SEQUENCE.sub(
            "", main.line_for(self.PAYLOAD, "trunk", 0, 196)
        )
        self.assertIn("claude-opus-4-6 (1m)", line)
        self.assertIn("trunk", line)
        self.assertIn("5h:42%", line)
        self.assertIn("7d:7%", line)

    def test_fits_a_narrow_terminal(self):
        line = main.line_for(self.PAYLOAD, "trunk", 0, 41)
        self.assertLessEqual(render.visible_width(line), 41)

    def test_keeps_context_and_the_five_hour_window_when_space_is_scarce(self):
        plain = render.ANSI_SEQUENCE.sub(
            "", main.line_for(self.PAYLOAD, "trunk", 0, 26)
        )
        self.assertIn("34%", plain)
        self.assertIn("5h", plain)

    def test_is_empty_for_a_payload_with_nothing_to_show(self):
        self.assertEqual(main.line_for({}, "", 0, 100), "")
