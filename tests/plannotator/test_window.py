"""The review window (pkgs/plannotator/review-window/), tested two ways:
- inside the namespace, with Plannotator's real review page;
- with its own filters alone, outside any namespace, against a page that tries the ways out those filters cover:
  requests, a popup, a scripted click and WebRTC's STUN packets. They are a second layer, not a boundary:
  WebRTC over TCP (TURN) and WebTransport get past them to the review host's other ports.

Clicks come from trusted_click.js, which NODE_OPTIONS loads into Electron's main process:
it clicks through Chromium's input pipeline, so the page sees a trusted click, as from a user's mouse.
spell_check.js types and right-clicks the same way.
The package must be built with spellcheckLanguage = "en-GB" (the command in test_package.py's docstring).
"""

import http.server
import os
import signal
import socket
import subprocess
import threading
import uuid

from harness import TESTS_PATH, Session, electron_main_process_ids, finish, wait_for

SECOND_LAYER_PAGE = """<!doctype html><title>second layer</title>
<a id="trusted" href="https://example.com/trusted" style="position:absolute;left:10px;top:10px;font-size:40px">trusted</a>
<a id="scripted" href="https://example.com/scripted" style="position:absolute;left:10px;top:200px">scripted</a>
<img src="http://127.0.0.1:{beacon_port}/beacon.png">
<script>
  const connection = new RTCPeerConnection({{ iceServers: [{{ urls: "stun:127.0.0.1:{stun_port}" }}] }});
  connection.createDataChannel("probe");
  connection.createOffer().then((offer) => connection.setLocalDescription(offer));
  fetch("http://127.0.0.1:{beacon_port}/fetch").catch(() => {{}});
  const opened = window.open("https://example.com/window-open");
  document.getElementById("scripted").click();
  setTimeout(() => fetch("/done?window-open=" + (opened === null ? "denied" : "opened")), 3000);
</script>
"""


def write_recording_browser(browser_file, opened_file, exit_code):
    browser_file.write_text(
        f"#!/bin/sh\nprintf '%s\\n' \"$1\" >> '{opened_file}'\nexit {exit_code}\n"
    )
    browser_file.chmod(0o755)
    return browser_file


def trusted_click_environment(selector):
    return {
        "NODE_OPTIONS": f"--require={TESTS_PATH / 'trusted_click.js'}",
        "PLANNOTATOR_TEST_CLICK_SELECTOR": selector,
    }


def cancelled(url):
    return lambda line: line.startswith("cancel ") and line.endswith(" " + url)


class ProbePage:
    """Serves one page on the test's loopback and records the paths it is asked for."""

    def __init__(self, body):
        self.paths = []
        page = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                page.paths.append(self.path)
                content = body.encode() if self.path == "/" else b""
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)

            def log_message(self, *arguments):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class StunListener:
    """A UDP listener on the test's loopback that counts packets: WebRTC sends STUN there without any request."""

    def __init__(self):
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(("127.0.0.1", 0))
        self.port = self.socket.getsockname()[1]
        self.packet_count = 0
        threading.Thread(target=self._receive, daemon=True).start()

    def _receive(self):
        while True:
            try:
                self.socket.recv(2048)
            except OSError:
                return
            self.packet_count += 1

    def close(self):
        try:
            self.socket.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.socket.close()


def test_inside_the_namespace_the_window_reaches_only_its_server(
    tmp_path, environment, start_session, beacon
):
    opened_file = tmp_path / "opened"
    # The browser command fails, so the window also falls back to copying the link.
    browser_file = write_recording_browser(
        tmp_path / "browser", opened_file, exit_code=1
    )
    (tmp_path / "probe.md").write_text(
        "# Probe\n\n"
        "[A link out](https://example.com/clicked)\n\n"
        "![remote](https://example.com/remote.png)\n\n"
        f"![beacon](http://127.0.0.1:{beacon.port}/beacon.png)\n"
    )
    session = start_session(
        ["annotate", "probe.md"],
        {
            **environment,
            **trusted_click_environment('a[href="https://example.com/clicked"]'),
            "PLANNOTATOR_WINDOW_BROWSER": str(browser_file),
            "WAYLAND_DEBUG": "1",
        },
        tmp_path,
        window=True,
    )

    session.wait_until_the_page_ran()
    session.wait_for_window_log(
        lambda line: line.startswith(
            f"allow mainFrame http://localhost:{session.port}"
        ),
        "the review page's own request",
    )
    session.wait_for_window_log(
        cancelled("https://example.com/remote.png"), "the remote image to be cancelled"
    )
    session.wait_for_window_log(
        cancelled(f"http://127.0.0.1:{beacon.port}/beacon.png"),
        "the beacon image to be cancelled",
    )
    session.wait_for_window_log(
        lambda line: line == "clipboard https://example.com/clicked",
        "the clicked link to reach the browser command and fall back to the clipboard",
    )
    assert opened_file.read_text().splitlines() == ["https://example.com/clicked"]
    assert beacon.connection_count == 0
    # GNOME finds the desktop entry, and with it the name and icon, through this app_id.
    assert (
        '.set_app_id("plannotator")'
        in (session.state_path / "launcher.log").read_text()
    )
    # The control for every "nothing remains" check: the snapshot sees into Chromium's own sandbox.
    assert any(
        "--type=renderer" in command_line
        for _, _, command_line in session.snapshot().values()
    )

    status, _ = session.request_json("/api/exit", "POST", {})
    assert status == 200
    session.process.communicate(timeout=60)
    session.wait_until_nothing_remains()


def test_the_review_page_is_spell_checked_without_a_download(
    tmp_path, environment, data_path, start_session
):
    # The dictionary comes from the package, linked into the profile; the namespace would stop Electron's download of one.
    (tmp_path / "probe.md").write_text("# Probe\n")
    session = start_session(
        ["annotate", "probe.md"],
        {
            **environment,
            "NODE_OPTIONS": f"--require={TESTS_PATH / 'spell_check.js'}",
        },
        tmp_path,
        window=True,
    )

    [context_menu_line] = session.wait_for_window_log(
        lambda line: line.startswith("test-context-menu "),
        "a right-click on the misspelled word to get suggestions",
    )
    _, misspelled_word, suggestions = context_menu_line.split(" ", 2)
    assert misspelled_word == "Speling"
    assert "Spelling" in suggestions.split(","), suggestions
    log = session.window_log()
    assert "test-spellcheck-dictionary-initialized en-GB" in log, log
    assert not any(
        line.startswith("test-spellcheck-dictionary-download-begin") for line in log
    ), log
    dictionary_files = list((data_path / "review-window" / "Dictionaries").iterdir())
    assert [file.name for file in dictionary_files] == ["en-GB-10-1.bdic"]
    assert dictionary_files[0].resolve().is_relative_to("/nix/store")

    status, _ = session.request_json("/api/exit", "POST", {})
    assert status == 200
    session.process.communicate(timeout=60)
    session.wait_until_nothing_remains()


def test_outside_any_namespace_the_windows_filters_still_apply(
    tmp_path, environment, package_path, beacon
):
    stun_listener = StunListener()
    page = ProbePage(
        SECOND_LAYER_PAGE.format(beacon_port=beacon.port, stun_port=stun_listener.port)
    )
    opened_file = tmp_path / "opened"
    state_path = tmp_path / "outside"
    state_path.mkdir()
    marker = uuid.uuid4().hex
    launcher = package_path / "libexec" / "plannotator" / "review-window"
    with (state_path / "launcher.log").open("w") as launcher_log:
        # A shell stands in for Plannotator as the launcher's parent, which the launcher signals when the window closes.
        process = subprocess.Popen(
            ["bash", "-c", '"$0" "$1"; exit $?', str(launcher), page.url],
            env={
                **environment,
                **trusted_click_environment("#trusted"),
                "PLANNOTATOR_WINDOW_BROWSER": str(
                    write_recording_browser(
                        tmp_path / "browser", opened_file, exit_code=0
                    )
                ),
                "PLANNOTATOR_WINDOW_LOG": str(state_path / "window.log"),
                "PLANNOTATOR_TEST_MARKER": marker,
            },
            stdout=launcher_log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    session = Session(process, state_path, marker)
    try:
        wait_for(
            lambda: any(path.startswith("/done") for path in page.paths),
            90,
            "the test page to try its ways out",
        )
        session.wait_for_window_log(
            lambda line: line == "www-browser https://example.com/trusted",
            "the trusted click to reach the browser command",
        )
        # Without the WebRTC policy, Chromium sends STUN binding requests within a second of setLocalDescription;
        # the page asks for /done three seconds after it.
        assert "/done?window-open=denied" in page.paths, page.paths
        log = session.window_log()
        assert "deny window https://example.com/window-open" in log, log
        assert any(
            cancelled(f"http://127.0.0.1:{beacon.port}/fetch")(line) for line in log
        ), log
        assert any(
            cancelled(f"http://127.0.0.1:{beacon.port}/beacon.png")(line)
            for line in log
        ), log
        assert beacon.connection_count == 0
        assert stun_listener.packet_count == 0
        # The page's scripted click on #scripted never reaches the browser command; the trusted one on #trusted does.
        assert opened_file.read_text().splitlines() == ["https://example.com/trusted"]

        assert any(
            "--type=renderer" in command_line
            for _, _, command_line in session.snapshot().values()
        )
        process_ids = electron_main_process_ids(marker)
        assert len(process_ids) == 1, process_ids
        os.kill(process_ids[0], signal.SIGTERM)
        process.wait(timeout=60)
        session.wait_until_nothing_remains()
    finally:
        finish(session)
        page.close()
        stun_listener.close()
