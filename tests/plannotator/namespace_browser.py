"""The tests' browser command (PLANNOTATOR_BROWSER), which Plannotator runs inside its namespace with the session URL.

It records its arguments and forwards a Unix socket in the session's state directory (PLANNOTATOR_TEST_STATE) to the server's port,
which the test cannot reach directly. Then, as the session asks:
- PLANNOTATOR_TEST_PROBE: runs namespace_probe.py's checks inside the namespace and writes probe.json;
- PLANNOTATOR_TEST_LAUNCHER: execs the package's review-window launcher in its own place,
  so the launcher's parent is Plannotator, as in real use, with its output in launcher.log;
  the forwarder lives on in a forked child, until Plannotator exits, since a launcher that hands the URL to a window
  started ahead of the server (prelaunch.sh) exits at once.
  PLANNOTATOR_TEST_HANDOFF_AFTER: the start of a window log line to wait for before the launcher runs,
  so a test can watch that early window act before the server's URL reaches it.
"""

import ctypes
import json
import os
import pathlib
import select
import signal
import socket
import sys
import threading
import time
import urllib.parse

import namespace_probe

PR_SET_PDEATHSIG = 1
HANDOFF_WAIT_SECONDS = 90


def die_with_parent():
    """Asks the kernel to kill this process when its parent exits, as the launcher does for itself with setpriv."""
    parent_id = os.getppid()
    ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGKILL)
    if os.getppid() != parent_id:
        os._exit(0)


def die_with(process_id):
    """Ends this process when another one exits, which need not be its parent."""
    try:
        process_descriptor = os.pidfd_open(process_id)
    except ProcessLookupError:
        os._exit(0)

    def watch():
        select.select([process_descriptor], [], [])
        os._exit(0)

    threading.Thread(target=watch, daemon=True).start()


def wait_for_window_log_line(line_start):
    log_file = pathlib.Path(os.environ["PLANNOTATOR_WINDOW_LOG"])
    deadline = time.monotonic() + HANDOFF_WAIT_SECONDS
    while time.monotonic() < deadline:
        if log_file.exists() and any(
            line.startswith(line_start) for line in log_file.read_text().splitlines()
        ):
            return
        time.sleep(0.1)


def write_json(file, value):
    """Atomically, because the test reads the file as soon as it appears."""
    partial_file = file.with_name(file.name + ".partial")
    partial_file.write_text(json.dumps(value))
    partial_file.replace(file)


def copy(source, destination):
    try:
        while chunk := source.recv(65536):
            destination.sendall(chunk)
    except OSError:
        pass
    try:
        destination.shutdown(socket.SHUT_WR)
    except OSError:
        pass


def relay(client, port):
    with client, socket.create_connection(("127.0.0.1", port)) as server:
        upstream = threading.Thread(target=copy, args=(client, server))
        upstream.start()
        copy(server, client)
        upstream.join()


def forward(listener, port):
    while True:
        client, _ = listener.accept()
        threading.Thread(target=relay, args=(client, port), daemon=True).start()


def main():
    state_path = pathlib.Path(os.environ["PLANNOTATOR_TEST_STATE"])
    arguments = sys.argv[1:]
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(state_path / "server.sock"))
    listener.listen()
    # Written once the socket listens: the test starts sending requests when it sees this file.
    write_json(state_path / "arguments.json", arguments)
    if len(arguments) != 1:
        return 2
    port = urllib.parse.urlsplit(arguments[0]).port

    launcher = os.environ.get("PLANNOTATOR_TEST_LAUNCHER")
    if launcher:
        # The parent is the Plannotator server: Bun runs the browser command as its direct child.
        server_process_id = os.getppid()
        if os.fork() == 0:
            die_with(server_process_id)
            forward(listener, port)
        listener.close()
        line_start = os.environ.get("PLANNOTATOR_TEST_HANDOFF_AFTER")
        if line_start:
            wait_for_window_log_line(line_start)
        log = os.open(
            state_path / "launcher.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644
        )
        os.dup2(log, 1)
        os.dup2(log, 2)
        os.execv(launcher, [launcher, *arguments])

    die_with_parent()
    probe = os.environ.get("PLANNOTATOR_TEST_PROBE")
    if probe:
        # The parent is the Plannotator server: Bun runs the browser command as its direct child.
        write_json(
            state_path / "probe.json",
            namespace_probe.run(json.loads(probe), os.getppid()),
        )
    forward(listener, port)


if __name__ == "__main__":
    sys.exit(main())
