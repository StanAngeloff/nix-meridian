"""Behavior tests for the cc subcommand handoff in home/apps/claude-code/initialize.zsh.

The launcher (bubble/bubble.sh) hands `<subcommand> <arguments…>` to a handler before any session starts;
_claude_is_subcommand_handoff mirrors that rule so cc's session checks (strict mode, the tmux window rename) stay out
of the way. Each case runs once per option that has broken zsh functions in this repository before.
"""

import os
import pathlib
import shlex
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
        # -P and --profile consume their value, like -m.
        ("-P personal profiles list", 0),
        ("--profile personal remote setup", 0),
        ("--profile=personal profiles list", 0),
        ("-P profiles list", 1),
        ("--profile remote -h", 1),
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


# Stand in for tmux and git, so the window rename prints the commands it would run.
# The tmux stand-in holds one window, @7, named $WINDOW_NAME until a rename-window gives it another name.
RENAME_STUBS = """
typeset -g stub_window_name="$WINDOW_NAME"
function tmux() {
  emulate -L zsh
  case $1 in
    display-message)
      [[ "$*" == *window_id* ]] && print -rn -- "@7 "
      print -r -- "$stub_window_name"
      ;;
    rename-window)
      stub_window_name="${@[-1]}"
      print -r -- "tmux $*"
      ;;
  esac
}
function git() { print -r -- /projects/nix-meridian/.git }
"""
TMUX_ENVIRONMENT = {
    "CLAUDE_BUBBLE_TMUX": "1",
    "TMUX": "/tmp/tmux-test,1,0",
    "TMUX_PANE": "%3",
    "WINDOW_NAME": "zsh",
    "XDG_STATE_HOME": "/nonexistent",
}


@pytest.mark.parametrize("option", HOSTILE_OPTIONS)
@pytest.mark.parametrize(
    "arguments, expected_window",
    [
        ("-r feature-x", "nix-meridian@feature-x"),
        ("--resume=feature-x", "nix-meridian@feature-x"),
        ("-P work -r feature-x", "nix-meridian@feature-x"),
        # A flag after -r means the resume picker: there is no name to put in the window.
        ("-r -P work", None),
        ("-r --profile work", None),
        ("-n -m opus", None),
    ],
)
def test_window_rename_takes_only_a_session_name(option, arguments, expected_window):
    result = run_zsh(
        RENAME_STUBS + f"_claude_bubble_initialize {arguments}",
        option,
        environment=TMUX_ENVIRONMENT,
    )
    expected_lines = (
        [f"tmux rename-window -t @7 {expected_window}"] if expected_window else []
    )
    assert result.stdout.splitlines() == expected_lines, result.stderr


@pytest.mark.parametrize("option", HOSTILE_OPTIONS)
@pytest.mark.parametrize(
    "window_name, is_renamed",
    [
        ("zsh", True),
        ("nix-meridian@feature-x", False),
        # A manual name around the session name stays, in any letter case.
        ("nix-meridian@feature-x [DOCS]", False),
        ("NIX-MERIDIAN@Feature-X [DOCS]", False),
        ("[DOCS] nix-meridian@feature-x", False),
        # The session name has to stand as a whole word.
        ("nix-meridian@feature-x2 [DOCS]", True),
        ("old-nix-meridian@feature-x", True),
    ],
)
def test_window_rename_leaves_a_window_that_shows_the_name(
    option, window_name, is_renamed
):
    result = run_zsh(
        RENAME_STUBS + "_claude_bubble_initialize -n feature-x/v2",
        option,
        environment={**TMUX_ENVIRONMENT, "WINDOW_NAME": window_name},
    )
    expected_lines = (
        ["tmux rename-window -t @7 nix-meridian@feature-x"] if is_renamed else []
    )
    assert result.stdout.splitlines() == expected_lines, result.stderr


@pytest.mark.parametrize("option", HOSTILE_OPTIONS)
@pytest.mark.parametrize(
    "window_name, name_given_during_session, expected_lines",
    [
        (
            "zsh",
            None,
            [
                "tmux rename-window -t @7 nix-meridian@feature-x",
                "tmux rename-window -t @7 zsh",
            ],
        ),
        # cc left the window alone, so it has nothing to put back.
        ("nix-meridian@feature-x [DOCS]", None, []),
        # A manual rename during the session stays.
        (
            "zsh",
            "nix-meridian@feature-x [DOCS]",
            [
                "tmux rename-window -t @7 nix-meridian@feature-x",
                "tmux rename-window -t @7 nix-meridian@feature-x [DOCS]",
            ],
        ),
    ],
)
def test_window_restore_puts_back_only_a_name_cc_replaced(
    option, window_name, name_given_during_session, expected_lines
):
    during_session = (
        f"tmux rename-window -t @7 {shlex.quote(name_given_during_session)}"
        if name_given_during_session
        else ""
    )
    result = run_zsh(
        RENAME_STUBS
        + "\n".join(
            [
                "_claude_bubble_initialize -n feature-x",
                during_session,
                "_claude_restore_window_name",
            ]
        ),
        option,
        environment={**TMUX_ENVIRONMENT, "WINDOW_NAME": window_name},
    )
    assert result.stdout.splitlines() == expected_lines, result.stderr


def read_window_keywords(state_path):
    keywords_path = state_path / "claude-cc" / "keywords"
    if not keywords_path.exists():
        return {}
    return {path.name: path.read_text().strip() for path in keywords_path.iterdir()}


@pytest.mark.parametrize("option", HOSTILE_OPTIONS)
@pytest.mark.parametrize(
    "window_name, expected_keywords",
    [
        ("nix-meridian@feature-x[DOCS]", {"feature-x": "DOCS"}),
        ("nix-meridian@feature-x [DOCS]", {"feature-x": "DOCS"}),
        ("nix-meridian@feature-x", {}),
        ("bold-owl", {}),
        # cc never names a window after feature/x, so the keyword has no session name to belong to.
        ("nix-meridian@feature/x[DOCS]", {}),
        # The keyword closes the name.
        ("nix-meridian@feature-x[DOCS] draft", {}),
    ],
)
def test_window_keyword_is_saved_from_a_rename(
    option, window_name, expected_keywords, tmp_path
):
    result = run_zsh(
        f"_claude_save_window_keyword {shlex.quote(window_name)}",
        option,
        environment={"XDG_STATE_HOME": str(tmp_path)},
    )
    assert read_window_keywords(tmp_path) == expected_keywords, result.stderr
    assert result.stderr == ""


@pytest.mark.parametrize("option", HOSTILE_OPTIONS)
@pytest.mark.parametrize(
    "window_name, expected_lines",
    [
        ("zsh", ["tmux rename-window -t @7 nix-meridian@feature-x[DOCS]"]),
        # A window named by hand keeps its own keyword.
        ("nix-meridian@feature-x[WIP]", []),
    ],
)
def test_window_rename_adds_the_saved_keyword(
    option, window_name, expected_lines, tmp_path
):
    run_zsh(
        "_claude_save_window_keyword 'bold-owl@feature-x[DOCS]'",
        option,
        environment={"XDG_STATE_HOME": str(tmp_path)},
    )
    result = run_zsh(
        RENAME_STUBS + "_claude_bubble_initialize -n feature-x/v2",
        option,
        environment={
            **TMUX_ENVIRONMENT,
            "WINDOW_NAME": window_name,
            "XDG_STATE_HOME": str(tmp_path),
        },
    )
    assert result.stdout.splitlines() == expected_lines, result.stderr
