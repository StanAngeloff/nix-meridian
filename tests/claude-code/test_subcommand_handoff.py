"""Behavior tests for the cc subcommand handoff in home/apps/claude-code/initialize.zsh.

The launcher (bubble/bubble.sh) hands `<subcommand> <arguments…>` to a handler before any session starts;
_claude_is_subcommand_handoff mirrors that rule so cc's session checks (strict mode, the tmux window rename) stay out
of the way. Each case runs once per option that has broken zsh functions in this repository before.
"""

import os
import pathlib
import subprocess

import pytest

INITIALIZE_FILE = (
    pathlib.Path(__file__).resolve().parents[2]
    / "home"
    / "apps"
    / "claude-code"
    / "initialize.zsh"
)
HOSTILE_OPTIONS = [
    "",
    "ksh_arrays",
    "no_bare_glob_qual",
    "sh_word_split",
    "no_nomatch",
    "glob_subst",
    "nullglob",
    "ksh_glob",
]


def run_zsh(body, option="", environment=None):
    script = "\n".join(
        [
            f"setopt {option}" if option else "",
            "typeset -ga _claude_subcommand_names=( profiles remote )",
            f"source {INITIALIZE_FILE}",
            body,
        ]
    )
    full_environment = {
        "PATH": os.environ["PATH"],
        "HOME": os.environ.get("HOME", "/tmp"),
    }
    full_environment.update(environment or {})
    return subprocess.run(
        ["zsh", "-f", "-c", script],
        capture_output=True,
        text=True,
        env=full_environment,
        check=False,
    )


@pytest.mark.parametrize("option", HOSTILE_OPTIONS)
@pytest.mark.parametrize(
    "arguments, expected_status",
    [
        ("remote -h", 0),
        ("remote setup", 0),
        ("profiles list", 0),
        # _claude_expand_model_aliases prepends --effort; the launcher drops everything before the subcommand word.
        ("--effort max remote setup", 0),
        ("-v /tmp remote -h", 0),
        # A trailing bare word stays a prompt.
        ("remote", 1),
        ("-p remote", 1),
        # -m consumes its value, so "remote" here is a model name.
        ("-m remote -h", 1),
        ("", 1),
    ],
)
def test_handoff_rule(option, arguments, expected_status):
    result = run_zsh(
        f"_claude_is_subcommand_handoff {arguments}; print -r -- status=$?", option
    )
    # The whole last line: a substring check would let status=127 (command not found) pass as status=1.
    assert result.stdout.splitlines()[-1:] == [
        f"status={expected_status}"
    ], result.stderr
    assert result.stderr == ""


@pytest.mark.parametrize("strict_value", ["1", "/^feat/"])
@pytest.mark.parametrize("arguments", ["remote -h", "remote setup", "profiles list"])
def test_strict_mode_lets_subcommands_through(strict_value, arguments):
    result = run_zsh(
        f"_claude_bubble_initialize {arguments}; print -r -- status=$?",
        environment={"CLAUDE_BUBBLE_STRICT": strict_value},
    )
    assert result.stdout.splitlines()[-1:] == ["status=0"], result.stderr
    assert result.stderr == ""


@pytest.mark.parametrize("strict_value", ["1", "/^feat/"])
def test_strict_mode_still_refuses_a_plain_session(strict_value):
    result = run_zsh(
        "_claude_bubble_initialize; print -r -- status=$?",
        environment={"CLAUDE_BUBBLE_STRICT": strict_value},
    )
    assert result.stdout.splitlines()[-1:] == ["status=1"]
    assert "pass -n/--name or -r/--resume" in result.stderr
