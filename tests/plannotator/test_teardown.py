"""Each way a review ends, with the review window open; afterwards nothing of the session may still run.
Plannotator's parentage mimics Claude Code's: a detached Bash shell, and above it Claude.
"""

import fcntl
import os
import pathlib
import signal
import sys

import pytest

from harness import TESTS_PATH, electron_main_process_ids, wait_for

# Claude's Bash shell: plannotator runs as its child, never exec'd in its place.
SHELL_PREFIX = ("bash", "-c", '"$0" "$@"; exit $?')
# Claude above the shell: starts it detached, in a session of its own, and holds the only reader of its output.
CLAUDE_SOURCE = (
    "import subprocess, sys, time\n"
    "subprocess.Popen(sys.argv[1:], start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)\n"
    "time.sleep(3600)\n"
)
CLAUDE_PREFIX = (sys.executable, "-c", CLAUDE_SOURCE, *SHELL_PREFIX)

WINDOW_CLOSED_NOTICE = "Plannotator review window: the window was closed without sending feedback; the draft is kept"
FRESH_PROFILE_NOTICE = "Plannotator review window: another review window is open, so this one starts with a fresh profile"
NO_DISPLAY_NOTICE = "Plannotator review window: no Wayland socket at "


@pytest.fixture(autouse=True)
def probe_file(tmp_path):
    probe_file = tmp_path / "probe.md"
    probe_file.write_text("# Probe\n\nA line to annotate.\n")
    return probe_file


def open_review(start_session, environment, tmp_path, file_name="probe.md", **options):
    session = start_session(
        ["annotate", file_name], environment, tmp_path, window=True, **options
    )
    session.wait_until_the_page_ran()
    session.snapshot()
    return session


def close_window(session):
    """What the window's close button amounts to: Electron's browser process ends."""
    process_ids = wait_for(
        lambda: electron_main_process_ids(session.marker),
        30,
        "the review window's Electron",
    )
    assert len(process_ids) == 1, process_ids
    os.kill(process_ids[0], signal.SIGTERM)


def window_profile(session):
    """The profile directory the session's window runs on, from its Electron main process's environment."""
    process_ids = wait_for(
        lambda: electron_main_process_ids(session.marker),
        30,
        "the review window's Electron",
    )
    assert len(process_ids) == 1, process_ids
    for entry in (
        pathlib.Path(f"/proc/{process_ids[0]}/environ").read_bytes().split(b"\0")
    ):
        if entry.startswith(b"PLANNOTATOR_WINDOW_PROFILE="):
            return entry.split(b"=", 1)[1].decode()
    pytest.fail("the review window's Electron has no PLANNOTATOR_WINDOW_PROFILE")


def page_script_environment(script):
    """Runs script in the review page once it has loaded, as the page's own code would (page_script.js)."""
    return {
        "NODE_OPTIONS": f"--require={TESTS_PATH / 'page_script.js'}",
        "PLANNOTATOR_TEST_PAGE_SCRIPT": script,
    }


def test_sending_feedback_closes_the_window(tmp_path, environment, start_session):
    session = open_review(start_session, environment, tmp_path)
    status, _ = session.request_json(
        "/api/feedback",
        "POST",
        {"feedback": "Probe feedback from the test.", "annotations": []},
    )
    assert status == 200
    stdout, stderr = session.process.communicate(timeout=60)
    assert session.process.returncode == 0, stderr
    assert "Probe feedback from the test." in stdout
    session.wait_until_nothing_remains()


def test_feedback_survives_the_window_closing_right_after_it(
    tmp_path, environment, start_session
):
    # What the page's setting to close immediately does: it sends the feedback and closes the window at once,
    # while Plannotator prints the feedback only 1.5 seconds later.
    send_feedback = (
        'fetch("/api/feedback", {method: "POST", headers: {"Content-Type": "application/json"}, '
        'body: JSON.stringify({feedback: "Probe feedback from the test.", annotations: []})})'
        ".then((response) => response.text())"
        ".then(() => window.close())"
    )
    session = start_session(
        ["annotate", "probe.md"],
        {**environment, **page_script_environment(send_feedback)},
        tmp_path,
        window=True,
    )
    stdout, stderr = session.process.communicate(timeout=90)
    assert session.process.returncode == 0, stderr
    assert "Probe feedback from the test." in stdout
    assert WINDOW_CLOSED_NOTICE not in stderr
    assert any(
        line.startswith("review-decided ") for line in session.window_log()
    ), session.window_log()
    session.wait_until_nothing_remains()


def test_closing_the_window_without_a_decision_ends_the_review(
    tmp_path, environment, start_session
):
    session = start_session(
        ["annotate", "probe.md"],
        {**environment, **page_script_environment("window.close()")},
        tmp_path,
        window=True,
    )
    _, stderr = session.process.communicate(timeout=60)
    assert session.process.returncode == 143, stderr
    assert WINDOW_CLOSED_NOTICE in stderr
    session.wait_until_nothing_remains()


def test_the_pages_close_button_closes_the_window(tmp_path, environment, start_session):
    session = open_review(start_session, environment, tmp_path)
    # The page's Close posts /api/exit: the review ends without feedback, and the draft goes.
    status, _ = session.request_json("/api/exit", "POST", {})
    assert status == 200
    _, stderr = session.process.communicate(timeout=60)
    assert session.process.returncode == 0, stderr
    session.wait_until_nothing_remains()


def test_closing_the_window_ends_the_review_and_keeps_the_draft(
    tmp_path, environment, data_path, start_session
):
    session = open_review(start_session, environment, tmp_path)
    # A high generation, so that no save the page makes itself can replace this draft.
    status, _ = session.request_json(
        "/api/draft",
        "POST",
        {"annotations": [], "draftGeneration": 1000, "probe": session.marker},
    )
    assert status == 200
    close_window(session)
    _, stderr = session.process.communicate(timeout=60)
    assert session.process.returncode == 143, stderr
    assert WINDOW_CLOSED_NOTICE in stderr
    drafts = [
        path
        for path in (data_path / "drafts").glob("*.json")
        if not path.name.endswith(".deleted.json")
    ]
    assert any(session.marker in path.read_text() for path in drafts), drafts
    session.wait_until_nothing_remains()


def test_a_crashed_window_ends_the_review_with_its_exit_status(
    tmp_path, environment, start_session
):
    session = open_review(start_session, environment, tmp_path)
    process_ids = wait_for(
        lambda: electron_main_process_ids(session.marker),
        30,
        "the review window's Electron",
    )
    os.kill(process_ids[0], signal.SIGKILL)
    _, stderr = session.process.communicate(timeout=60)
    assert session.process.returncode == 143, stderr
    assert (
        "Plannotator review window: the window failed (Electron exit status " in stderr
    )
    session.wait_until_nothing_remains()


def test_esc_in_claude_takes_everything_down(tmp_path, environment, start_session):
    session = open_review(
        start_session, environment, tmp_path, command_prefix=SHELL_PREFIX
    )
    # Models Claude Code ending a command by killing the shell's process group; SIGKILL leaves nothing a chance to clean up.
    os.killpg(session.process.pid, signal.SIGKILL)
    session.process.wait(timeout=60)
    session.wait_until_nothing_remains()


def test_a_killed_shell_takes_everything_down(tmp_path, environment, start_session):
    session = open_review(
        start_session, environment, tmp_path, command_prefix=SHELL_PREFIX
    )
    session.process.kill()
    session.process.wait(timeout=60)
    session.wait_until_nothing_remains()


def test_a_killed_claude_leaves_the_review_open_until_its_window_closes(
    tmp_path, environment, start_session
):
    """The accepted gap: the detached shell outlives Claude, and so does the review, until the window closes."""
    session = open_review(
        start_session, environment, tmp_path, command_prefix=CLAUDE_PREFIX
    )
    session.process.kill()
    session.process.wait(timeout=60)
    status, _ = session.request_json("/api/plan")
    assert status == 200, "the review should still be open"
    assert electron_main_process_ids(session.marker), "the window should still be open"
    # Plannotator's stderr has no reader left, so the launcher's line fails to arrive; ending the review must not.
    close_window(session)
    session.wait_until_nothing_remains()


def test_a_second_review_at_the_same_time_gets_a_fresh_profile(
    tmp_path, environment, data_path, start_session
):
    # Two files, so the second review is a session of its own whatever Plannotator does about a file already open.
    (tmp_path / "second.md").write_text("# Second\n\nAnother line to annotate.\n")
    first = open_review(start_session, environment, tmp_path)
    second = open_review(start_session, environment, tmp_path, file_name="second.md")
    # Read while both windows are open: the second runs on a throwaway profile in the namespace's /tmp.
    assert window_profile(first) == str(data_path / "review-window")
    assert window_profile(second).startswith("/tmp/review-window.")
    for session in (first, second):
        status, _ = session.request_json("/api/exit", "POST", {})
        assert status == 200
    _, first_stderr = first.process.communicate(timeout=60)
    _, second_stderr = second.process.communicate(timeout=60)
    assert FRESH_PROFILE_NOTICE not in first_stderr
    assert FRESH_PROFILE_NOTICE in second_stderr
    assert any(
        (data_path / "review-window").iterdir()
    ), "the first window keeps its profile"
    for session in (first, second):
        session.wait_until_nothing_remains()
    with (data_path / "review-window.lock").open("a") as lock:
        # Raises BlockingIOError if anything still holds the lock.
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)


def test_without_a_display_the_review_ends_with_its_reason(
    tmp_path, environment, start_session
):
    session = start_session(
        ["annotate", "probe.md"],
        {**environment, "WAYLAND_DISPLAY": "wayland-missing"},
        tmp_path,
        window=True,
    )
    _, stderr = session.process.communicate(timeout=60)
    assert session.process.returncode == 143, stderr
    assert NO_DISPLAY_NOTICE in stderr
    session.wait_until_nothing_remains()


def test_the_notice_keeps_what_the_command_printed_before(
    tmp_path, environment, start_session
):
    # Claude Code's Bash tool collects a command's output in one file opened for appending: the notice adds to it.
    stderr_file = tmp_path / "stderr"
    stderr_file.write_text("earlier output\n")
    session = start_session(
        ["annotate", "probe.md"],
        {
            **environment,
            "WAYLAND_DISPLAY": "wayland-missing",
            "PLANNOTATOR_TEST_STDERR_FILE": str(stderr_file),
        },
        tmp_path,
        window=True,
        command_prefix=(
            "bash",
            "-c",
            'exec "$0" "$@" 2>>"$PLANNOTATOR_TEST_STDERR_FILE"',
        ),
    )
    session.process.communicate(timeout=60)
    assert session.process.returncode == 143
    lines = stderr_file.read_text().splitlines()
    assert lines[0] == "earlier output", lines
    assert any(line.startswith(NO_DISPLAY_NOTICE) for line in lines), lines
    session.wait_until_nothing_remains()
