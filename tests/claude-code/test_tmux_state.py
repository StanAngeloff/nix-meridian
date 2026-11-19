"""Behavior tests for which sessions drive the tmux traffic light.

claude-tmux-state.sh runs from every Claude Code hook, including the hooks of a headless session started inside an interactive one.
That headless session inherits TMUX_PANE or the bubble event channel, so it must stay silent, or its SessionEnd clears the parent's light.
The script runs from source along the bubble path, appending to an event file under tmp_path, so tmux is never touched.
Run after changing the script, from the repository root:

    nix shell --inputs-from "path:$PWD" nixpkgs#python3Packages.pytest \
      --command pytest -p no:cacheprovider tests/claude-code/test_tmux_state.py
"""

import json
import os
import pathlib
import subprocess

import pytest

STATE_FILE = (
    pathlib.Path(__file__).resolve().parents[2]
    / "home"
    / "apps"
    / "claude-code"
    / "hooks"
    / "claude-tmux-state.sh"
)

# One payload per event that resolves to an action, with the action an interactive session gets.
PAYLOADS = [
    ({"hook_event_name": "SessionStart", "source": "startup"}, "session-start"),
    ({"hook_event_name": "UserPromptSubmit", "prompt": "ok"}, "turn-start"),
    ({"hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion"}, "blocked"),
    ({"hook_event_name": "PermissionRequest", "tool_name": "Bash"}, "blocked"),
    ({"hook_event_name": "Stop"}, "turn-end"),
    ({"hook_event_name": "SessionEnd", "reason": "other"}, "session-end"),
]
PAYLOAD_IDS = [payload["hook_event_name"] for payload, _ in PAYLOADS]

# Claude Code reports a terminal session as "cli"; unset reads the same way.
INTERACTIVE_ENTRYPOINTS = ["cli", None]
# `claude -p` turns an inherited "cli" into "sdk-cli"; the Agent SDK sets "sdk-ts" or "sdk-py".
HEADLESS_ENTRYPOINTS = ["sdk-cli", "sdk-ts", "sdk-py"]


def run_hook(tmp_path, payload, entrypoint):
    event_file = tmp_path / "events"
    environment = {
        "PATH": os.environ["PATH"],
        "HOME": str(tmp_path),
        "CLAUDE_BUBBLE_EVENT_FILE": str(event_file),
    }
    if entrypoint is not None:
        environment["CLAUDE_CODE_ENTRYPOINT"] = entrypoint
    result = subprocess.run(
        ["bash", str(STATE_FILE)],
        input=json.dumps({"session_id": "test", **payload}),
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return event_file.read_text() if event_file.exists() else ""


@pytest.mark.parametrize("entrypoint", INTERACTIVE_ENTRYPOINTS)
@pytest.mark.parametrize(("payload", "action"), PAYLOADS, ids=PAYLOAD_IDS)
def test_interactive_session_drives_the_light(tmp_path, payload, action, entrypoint):
    assert run_hook(tmp_path, payload, entrypoint) == f"{action}\n"


@pytest.mark.parametrize("entrypoint", HEADLESS_ENTRYPOINTS)
@pytest.mark.parametrize(("payload", "action"), PAYLOADS, ids=PAYLOAD_IDS)
def test_headless_session_leaves_the_light_alone(tmp_path, payload, action, entrypoint):
    assert run_hook(tmp_path, payload, entrypoint) == ""
