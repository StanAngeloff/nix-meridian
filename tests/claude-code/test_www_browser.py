"""Behavior tests for the loopback URL opener.

relay.sh's www-browser case runs host-side and is the boundary, because anything inside the bubble can write the event
file directly; www-browser.sh (claude-bubble-www-browser) runs inside the bubble and appends the request.
Both run from source with stub xdg-open and logger commands first on PATH. Run after changing either file, from the
repository root:

    nix shell --inputs-from "path:$PWD" nixpkgs#python3Packages.pytest \
      --command pytest -p no:cacheprovider tests/claude-code/test_www_browser.py
"""

import os
import pathlib
import signal
import subprocess
import time

import pytest

NOTIFICATIONS_PATH = (
    pathlib.Path(__file__).resolve().parents[2]
    / "home"
    / "apps"
    / "claude-code"
    / "bubble"
    / "modules"
    / "notifications"
)
RELAY_FILE = NOTIFICATIONS_PATH / "relay.sh"
OPENER_FILE = NOTIFICATIONS_PATH / "www-browser.sh"

ACCEPTED_URLS = [
    "http://localhost:19432",
    "http://localhost:19432/",
    "http://127.0.0.1:41234/review?diff=staged#file-3",
]
REFUSED_URLS = [
    "https://localhost:19432/",
    "http://example.com/",
    "http://127.0.0.1.evil.com/",
    "http://localhost.evil.com:80/",
    "http://localhost:80@evil.com/",
    "http://evil.com/?http://localhost:80/",
    "http://localhost/",
    "http://localhost:80/a b",
    "http://localhost:123456/",
    "javascript:alert(1)",
    "file:///etc/passwd",
    "",
]


def write_stub(stub_file, body):
    stub_file.write_text(f"#!/bin/sh\n{body}\n")
    stub_file.chmod(0o755)


def read_lines(file):
    return file.read_text().splitlines() if file.exists() else []


def wait_for_lines(file, count, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if len(read_lines(file)) >= count:
            return read_lines(file)
        time.sleep(0.1)
    pytest.fail(f"{file.name} has {len(read_lines(file))} lines, expected {count}")


@pytest.fixture
def opened_file(tmp_path):
    return tmp_path / "opened"


@pytest.fixture
def logged_file(tmp_path):
    return tmp_path / "logged"


@pytest.fixture
def environment(tmp_path, opened_file, logged_file):
    stub_path = tmp_path / "bin"
    stub_path.mkdir()
    write_stub(
        stub_path / "xdg-open", f"printf '%s\\t%s\\n' \"$#\" \"$1\" >> '{opened_file}'"
    )
    write_stub(stub_path / "logger", f"printf '%s\\n' \"$*\" >> '{logged_file}'")
    return {"PATH": f"{stub_path}:{os.environ['PATH']}", "HOME": str(tmp_path)}


def run_opener(arguments, environment):
    return subprocess.run(
        ["bash", str(OPENER_FILE), *arguments],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )


def test_relay_opens_only_loopback_urls(
    tmp_path, environment, opened_file, logged_file
):
    event_file = tmp_path / "events"
    # Refused requests go first: by the time every accepted one has opened, every refused one has been handled.
    event_file.write_text(
        "".join(f"www-browser:{url}\n" for url in REFUSED_URLS + ACCEPTED_URLS)
    )
    relay = subprocess.Popen(
        ["bash", str(RELAY_FILE), str(event_file), "", str(tmp_path / "chime.mp3")],
        env=environment,
        start_new_session=True,
    )
    try:
        wait_for_lines(opened_file, len(ACCEPTED_URLS))
        logged = wait_for_lines(logged_file, len(REFUSED_URLS))
        # xdg-open is forked; a late extra opening would land in this window.
        time.sleep(0.5)
        opened = read_lines(opened_file)
    finally:
        os.killpg(relay.pid, signal.SIGTERM)
        relay.wait(timeout=10)
    assert sorted(opened) == sorted(f"1\t{url}" for url in ACCEPTED_URLS)
    assert len(logged) == len(REFUSED_URLS)
    assert all(line.startswith("-t claude-bubble-relay ") for line in logged)


@pytest.mark.parametrize("url", ACCEPTED_URLS)
def test_opener_appends_one_request_inside_the_bubble(
    tmp_path, environment, opened_file, url
):
    event_file = tmp_path / "events"
    result = run_opener(
        [url], {**environment, "CLAUDE_BUBBLE_EVENT_FILE": str(event_file)}
    )
    assert result.returncode == 0, result.stderr
    assert event_file.read_text() == f"www-browser:{url}\n"
    assert read_lines(opened_file) == []


@pytest.mark.parametrize("url", ACCEPTED_URLS)
def test_opener_runs_xdg_open_outside_the_bubble(environment, opened_file, url):
    result = run_opener([url], environment)
    assert result.returncode == 0, result.stderr
    assert read_lines(opened_file) == [f"1\t{url}"]


@pytest.mark.parametrize(
    "url", REFUSED_URLS + ["http://localhost:80/\nwww-browser:https://example.com/"]
)
def test_opener_refuses_everything_else(tmp_path, environment, opened_file, url):
    event_file = tmp_path / "events"
    inside = run_opener(
        [url], {**environment, "CLAUDE_BUBBLE_EVENT_FILE": str(event_file)}
    )
    outside = run_opener([url], environment)
    assert inside.returncode == 1
    assert outside.returncode == 1
    assert not event_file.exists()
    assert read_lines(opened_file) == []


@pytest.mark.parametrize(
    "arguments", [[], ["http://localhost:80/", "http://localhost:81/"]]
)
def test_opener_takes_exactly_one_argument(environment, opened_file, arguments):
    assert run_opener(arguments, environment).returncode == 2
    assert read_lines(opened_file) == []
