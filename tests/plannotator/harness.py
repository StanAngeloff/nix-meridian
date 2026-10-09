"""Helpers shared by tests/plannotator: starting a plannotator session,
reaching its server from outside its network namespace, and telling whether anything of it is still running.
conftest.py turns them into fixtures.

The package runs Plannotator in a network namespace that has only loopback, with /tmp and /run masked (isolate.sh),
so a test can neither connect to the server's port nor hand Plannotator files under /tmp.
Each session therefore runs namespace_browser.py as its browser command, inside the namespace,
and it forwards a Unix socket in the session's state directory to that port; Session.request_json speaks HTTP over it.
"""

import dataclasses
import http.client
import json
import os
import pathlib
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid

import pytest

TESTS_PATH = pathlib.Path(__file__).resolve().parent
ADVERTISED_URL_PATTERN = re.compile(r"http://localhost:(\d+)/?")
WAYLAND_SOCKET_NAME = "wayland-plannotator-test"
# The review page asks GitHub for the latest release on every load, so its cancellation in the window log means the page ran.
# If a release drops the check, wait for another request the page makes on load instead.
UPDATE_CHECK_URL = (
    "https://api.github.com/repos/backnotprop/plannotator/releases/latest"
)


def wait_for(condition, timeout, description):
    """Polls condition until it returns something true, and returns that."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = condition()
        if result:
            return result
        time.sleep(0.2)
    pytest.fail(f"timed out after {timeout} seconds waiting for {description}")


def make_environment(work_path, wayland_runtime_path):
    """Built from scratch so nothing from the test runner's PLANNOTATOR_*, SSH_* or display variables leaks in."""
    home_path = work_path / "home"
    data_path = work_path / "data"
    home_path.mkdir()
    data_path.mkdir()
    return {
        "PATH": os.environ["PATH"],
        "HOME": str(home_path),
        "LANG": "C.UTF-8",
        "XDG_RUNTIME_DIR": str(wayland_runtime_path),
        "WAYLAND_DISPLAY": WAYLAND_SOCKET_NAME,
        "PLANNOTATOR_DATA_DIR": str(data_path),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Probe",
        "GIT_AUTHOR_EMAIL": "probe@example.invalid",
        "GIT_COMMITTER_NAME": "Probe",
        "GIT_COMMITTER_EMAIL": "probe@example.invalid",
    }


def process_table():
    """Every live process: id → (parent id, start time, command line).

    Arguments are joined with spaces, because Chromium rewrites its child processes' command lines as one string.
    """
    table = {}
    for process_path in pathlib.Path("/proc").iterdir():
        if not process_path.name.isdigit():
            continue
        try:
            stat_fields = (process_path / "stat").read_text().rsplit(")", 1)[1].split()
            command_line = (process_path / "cmdline").read_bytes()
        except OSError:
            continue
        if stat_fields[0] == "Z":
            continue
        table[int(process_path.name)] = (
            int(stat_fields[1]),
            int(stat_fields[19]),
            command_line.replace(b"\0", b" ").decode(errors="replace").strip(),
        )
    return table


def processes_carrying(marker):
    """Process id → command line for every process whose environment holds this session's marker.

    Chromium overwrites its child processes' environment with their command lines,
    so this finds Electron's main process but not its renderers; Session.snapshot covers those.
    """
    needle = f"PLANNOTATOR_TEST_MARKER={marker}".encode()
    found = {}
    for process_id, (_, _, command_line) in process_table().items():
        try:
            environment = pathlib.Path(f"/proc/{process_id}/environ").read_bytes()
        except OSError:
            continue
        if needle in environment.split(b"\0"):
            found[process_id] = command_line
    return found


def descendants(root_process_id):
    """The root and every live process below it: id → (parent id, start time, command line)."""
    table = process_table()
    children = {}
    for process_id, (parent_id, _, _) in table.items():
        children.setdefault(parent_id, []).append(process_id)
    found, pending = {}, [root_process_id]
    while pending:
        process_id = pending.pop()
        if process_id in table and process_id not in found:
            found[process_id] = table[process_id]
            pending.extend(children.get(process_id, []))
    return found


def electron_main_process_ids(marker):
    """Electron's browser process, whose exit is the window closing; its children carry --type= switches."""
    return [
        process_id
        for process_id, command_line in processes_carrying(marker).items()
        if pathlib.PurePath(command_line.split(" ")[0]).name == "electron"
        and "--type=" not in command_line
    ]


class UnixHTTPConnection(http.client.HTTPConnection):
    """HTTP over the session's forwarder socket, with the Host header the server would see from the window."""

    def __init__(self, socket_file, host):
        super().__init__(host, timeout=60)
        self.socket_file = socket_file

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(str(self.socket_file))


@dataclasses.dataclass
class Session:
    """One plannotator command a test started, and what its browser command (namespace_browser.py) left behind."""

    process: subprocess.Popen
    state_path: pathlib.Path
    marker: str
    tree: dict = dataclasses.field(default_factory=dict)

    def wait_for_file(self, file, timeout, description):
        """Waits for a file the browser command writes; fails at once, with Plannotator's stderr, if the session ends first."""
        wait_for(
            lambda: file.exists() or self.process.poll() is not None,
            timeout,
            description,
        )
        if not file.exists():
            _, stderr = self.process.communicate(timeout=10)
            pytest.fail(
                f"plannotator exited {self.process.returncode} before {description}: {stderr}"
            )

    def browser_arguments(self, timeout=60):
        arguments_file = self.state_path / "arguments.json"
        self.wait_for_file(
            arguments_file, timeout, "Plannotator to run its browser command"
        )
        return json.loads(arguments_file.read_text())

    @property
    def port(self):
        arguments = self.browser_arguments()
        assert len(arguments) == 1, f"the browser command got {arguments!r}"
        match = ADVERTISED_URL_PATTERN.fullmatch(arguments[0])
        assert match, f"unexpected session URL {arguments[0]!r}"
        return int(match.group(1))

    @property
    def base_url(self):
        """The advertised URL says localhost; requests name 127.0.0.1, so the Host header is predictable."""
        return f"http://127.0.0.1:{self.port}"

    def request_json(self, path, method="GET", body=None, headers=None):
        connection = UnixHTTPConnection(
            self.state_path / "server.sock", f"127.0.0.1:{self.port}"
        )
        try:
            connection.request(
                method,
                path,
                body=None if body is None else json.dumps(body).encode(),
                headers={"Content-Type": "application/json", **(headers or {})},
            )
            response = connection.getresponse()
            return response.status, json.loads(response.read() or b"null")
        finally:
            connection.close()

    def request_bytes(self, path):
        """GET path uncompressed (http.client asks for no encoding): the status and the body's bytes."""
        connection = UnixHTTPConnection(
            self.state_path / "server.sock", f"127.0.0.1:{self.port}"
        )
        try:
            connection.request("GET", path)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def probe_result(self, timeout=120):
        probe_file = self.state_path / "probe.json"
        self.wait_for_file(probe_file, timeout, "the probe inside the namespace")
        return json.loads(probe_file.read_text())

    def window_log(self):
        log_file = self.state_path / "window.log"
        return log_file.read_text().splitlines() if log_file.exists() else []

    def wait_for_window_log(self, predicate, description, timeout=90):
        return wait_for(
            lambda: [line for line in self.window_log() if predicate(line)],
            timeout,
            description,
        )

    def wait_until_the_page_ran(self):
        self.wait_for_window_log(
            lambda line: line.startswith("cancel ")
            and line.endswith(" " + UPDATE_CHECK_URL),
            "the review page to run in the window",
        )

    def snapshot(self):
        """Records the session's process tree while it runs, Electron's renderers included (see processes_carrying)."""
        self.tree = descendants(self.process.pid)
        return self.tree

    def survivors(self):
        """What still runs: processes carrying the marker, and processes from the snapshot (same id, same start)."""
        table = process_table()
        survivors = processes_carrying(self.marker)
        for process_id, (_, start_time, command_line) in self.tree.items():
            if process_id in table and table[process_id][1] == start_time:
                survivors[process_id] = command_line
        return survivors

    def wait_until_nothing_remains(self, timeout=30):
        deadline = time.monotonic() + timeout
        while (survivors := self.survivors()) and time.monotonic() < deadline:
            time.sleep(0.2)
        assert (
            not survivors
        ), f"still running {timeout} seconds after the end: {survivors}"


def write_browser(state_path):
    """PLANNOTATOR_BROWSER names one executable, so a two-line script runs namespace_browser.py with this Python."""
    browser_file = state_path / "browser"
    browser_file.write_text(
        f"#!/bin/sh\nexec '{sys.executable}' '{TESTS_PATH / 'namespace_browser.py'}' \"$@\"\n"
    )
    browser_file.chmod(0o755)
    return browser_file


def launch(
    package_path,
    environment,
    state_path,
    arguments,
    cwd,
    *,
    window=False,
    probe=None,
    command_prefix=(),
):
    """Starts a plannotator command in a session of its own, with namespace_browser.py as its browser command.

    window: the browser command execs the package's review-window launcher, as Plannotator itself would,
      and the window starts ahead of the server, as with the package's own browser command,
      unless the environment sets PLANNOTATOR_WINDOW_PRELAUNCH otherwise.
    probe: namespace_probe.run's configuration, run inside the namespace before forwarding starts.
    command_prefix: what runs plannotator, to stand in for Claude's Bash shell and Claude (test_teardown.py).
    """
    state_path.mkdir()
    marker = uuid.uuid4().hex
    session_environment = {
        **environment,
        "PLANNOTATOR_BROWSER": str(write_browser(state_path)),
        "PLANNOTATOR_TEST_MARKER": marker,
        "PLANNOTATOR_TEST_STATE": str(state_path),
        "PLANNOTATOR_WINDOW_LOG": str(state_path / "window.log"),
    }
    if window:
        session_environment["PLANNOTATOR_TEST_LAUNCHER"] = str(
            package_path / "libexec" / "plannotator" / "review-window"
        )
        session_environment.setdefault("PLANNOTATOR_WINDOW_PRELAUNCH", "1")
    if probe is not None:
        session_environment["PLANNOTATOR_TEST_PROBE"] = json.dumps(probe)
    process = subprocess.Popen(
        [*command_prefix, str(package_path / "bin" / "plannotator"), *arguments],
        env=session_environment,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    return Session(process, state_path, marker)


def finish(session):
    """Kills whatever of the session still runs, whether or not the test got as far as ending it."""
    for _ in range(50):
        survivors = session.survivors()
        if not survivors:
            break
        for process_id in survivors:
            try:
                os.kill(process_id, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)
    if session.process.poll() is None:
        session.process.kill()
    session.process.wait()


class Beacon:
    """A TCP listener on the test's own loopback that counts connections: reaching it means leaving the namespace."""

    def __init__(self):
        self.listener = socket.create_server(("127.0.0.1", 0))
        self.port = self.listener.getsockname()[1]
        self.connection_count = 0
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while True:
            try:
                connection, _ = self.listener.accept()
            except OSError:
                return
            self.connection_count += 1
            connection.close()

    def close(self):
        try:
            self.listener.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.listener.close()
