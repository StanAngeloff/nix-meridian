"""Behaviour tests for home/apps/voxize/launch/voxize-launch.sh against private tmux servers.

The launcher drives an "inner" tmux server through $TMUX. An "outer" tmux server plays the Ghostty window: its pane runs a script
named ghostty, given the tmux path as an argument, which attaches a client to the inner server. That gives the focused window a
command line holding /ghostty and /tmux, and a tmux client descended from it. Stubs for busctl, voxize and voxize-tui come first on
PATH: busctl reports a chosen process as the focused window, voxize records that the window was opened, voxize-tui just stays alive.
"""

import os
import shutil
import subprocess
import tempfile
import time

import pytest

SCRIPT_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "home",
    "apps",
    "voxize",
    "launch",
    "voxize-launch.sh",
)
TMUX_PATH = shutil.which("tmux")
BASH_PATH = shutil.which("bash")


def wait_for(predicate, timeout_seconds=5.0):
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError("condition not met within %.1f s" % timeout_seconds)


class Rig:
    def __init__(self, directory_path):
        self.directory_path = directory_path
        self.stub_path = os.path.join(directory_path, "stubs")
        self.inner_socket_path = os.path.join(directory_path, "inner")
        self.outer_socket_path = os.path.join(directory_path, "outer")
        self.gui_marker_file = os.path.join(directory_path, "gui-opened")
        self.window_pid_file = os.path.join(directory_path, "window-pid")
        self.background_file = os.path.join(directory_path, "background")
        self.ghostty_file = os.path.join(directory_path, "bin", "ghostty")
        os.makedirs(self.stub_path)
        os.makedirs(os.path.dirname(self.ghostty_file))
        self._write_executable(
            os.path.join(self.stub_path, "busctl"),
            "#!%s\n"
            'pid=$(cat "%s")\n'
            'printf \'{"type":"s","data":[%%s]}\' "$(printf \'[{"pid":%%s,"focus":true,"wm_class":"x"}]\' "$pid" | %s)"\n'
            % (BASH_PATH, self.window_pid_file, "jq -Rs ."),
        )
        self._write_executable(
            os.path.join(self.stub_path, "voxize"),
            "#!%s\necho opened > '%s'\n" % (BASH_PATH, self.gui_marker_file),
        )
        self._write_executable(
            os.path.join(self.stub_path, "voxize-tui"),
            '#!%s\nprintf %%s "$VOXIZE_TUI_BACKGROUND" > "%s"\nexec sleep 600\n'
            % (BASH_PATH, self.background_file),
        )
        # Not exec: the script stays the client's parent, as the Ghostty process is.
        self._write_executable(
            self.ghostty_file,
            '#!%s\n"$1" -S "$2" attach-session -t inner\n' % BASH_PATH,
        )

    @staticmethod
    def _write_executable(file_path, content):
        with open(file_path, "w") as handle:
            handle.write(content)
        os.chmod(file_path, 0o755)

    def inner(self, *arguments):
        return self._tmux(self.inner_socket_path, *arguments)

    def outer(self, *arguments):
        return self._tmux(self.outer_socket_path, *arguments)

    @staticmethod
    def _tmux(socket_path, *arguments):
        completed = subprocess.run(
            [TMUX_PATH, "-S", socket_path, *arguments],
            capture_output=True,
            text=True,
            timeout=10,
            env=_clean_env(),
        )
        assert completed.returncode == 0, completed.stderr
        return completed.stdout

    def start(self, width, height):
        self.inner(
            "-f",
            "/dev/null",
            "new-session",
            "-d",
            "-s",
            "inner",
            "-x",
            str(width),
            "-y",
            str(height),
            "-c",
            "/etc",
        )
        self.inner("set-option", "-g", "status", "off")
        self.inner("set-option", "-g", "focus-events", "on")
        self.inner("set-option", "-g", "window-size", "latest")
        self.outer(
            "-f",
            "/dev/null",
            "new-session",
            "-d",
            "-s",
            "outer",
            "-x",
            str(width),
            "-y",
            str(height),
            "%s %s %s" % (self.ghostty_file, TMUX_PATH, self.inner_socket_path),
        )
        self.outer("set-option", "-g", "status", "off")
        wait_for(lambda: self.inner("list-clients", "-F", "#{client_pid}").strip())
        wait_for(
            lambda: self.inner(
                "display-message", "-p", "#{window_width}x#{window_height}"
            ).strip()
            == "%dx%d" % (width, height)
        )
        self.set_window_pid(
            int(self.outer("display-message", "-p", "#{pane_pid}").strip())
        )

    def set_window_pid(self, pid):
        with open(self.window_pid_file, "w") as handle:
            handle.write(str(pid))

    def launch(self):
        env = _clean_env()
        env["PATH"] = self.stub_path + os.pathsep + env["PATH"]
        env["TMUX"] = "%s,0,0" % self.inner_socket_path
        # The options writeShellApplication puts in front of the script.
        command = [
            BASH_PATH,
            "-o",
            "errexit",
            "-o",
            "nounset",
            "-o",
            "pipefail",
            SCRIPT_PATH,
        ]
        completed = subprocess.run(
            command, capture_output=True, text=True, timeout=10, env=env
        )
        assert completed.returncode == 0, completed.stderr
        return completed

    def panes(self):
        rows = self.inner(
            "list-panes",
            "-F",
            "#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height} #{pane_active} #{pane_floating_flag} #{pane_current_path}",
        )
        panes = []
        for row in rows.splitlines():
            pane_id, left, top, width, height, active, floating, path = row.split(
                " ", 7
            )
            panes.append(
                {
                    "id": pane_id,
                    "left": int(left),
                    "top": int(top),
                    "width": int(width),
                    "height": int(height),
                    "active": active == "1",
                    "floating": floating == "1",
                    "path": path,
                }
            )
        return panes

    def floating_panes(self):
        return [pane for pane in self.panes() if pane["floating"]]

    def gui_opened(self):
        return os.path.exists(self.gui_marker_file)

    def stop(self):
        for socket_path in (self.outer_socket_path, self.inner_socket_path):
            subprocess.run(
                [TMUX_PATH, "-S", socket_path, "kill-server"],
                capture_output=True,
                timeout=10,
                env=_clean_env(),
            )


def _clean_env():
    env = dict(os.environ)
    env.pop("TMUX", None)
    env.pop("TMUX_PANE", None)
    return env


@pytest.fixture
def rig():
    # Socket paths must stay under the 108-byte AF_UNIX limit, which pytest's tmp_path can exceed.
    directory_path = tempfile.mkdtemp(prefix="voxize-launch-", dir="/tmp")
    rig = Rig(directory_path)
    yield rig
    rig.stop()
    shutil.rmtree(directory_path, ignore_errors=True)


def test_wide_and_tall_pane_gets_a_centred_card_in_its_directory(rig):
    rig.start(200, 50)
    rig.inner("split-window", "-h", "-l", "60", "-c", "/tmp")
    rig.inner("select-pane", "-t", ":.0")
    rig.launch()
    [card] = rig.floating_panes()
    assert (card["left"], card["top"], card["width"], card["height"]) == (
        25,
        13,
        88,
        24,
    )
    assert card["active"]
    assert card["path"] == "/etc"
    assert not rig.gui_opened()


def test_card_is_titled_voxize_and_its_directory(rig):
    rig.start(200, 50)
    rig.launch()
    [card] = rig.floating_panes()
    title = rig.inner(
        "display-message",
        "-p",
        "-t",
        card["id"],
        "#{@float-title-bold}|#{@float-title-rest}",
    )
    assert title.strip() == "voxize|/etc"


def test_card_asks_voxize_for_the_amber_background(rig):
    rig.start(200, 50)
    rig.launch()
    wait_for(lambda: os.path.exists(rig.background_file))
    with open(rig.background_file) as handle:
        assert handle.read() == "#100b06"


def test_narrow_pane_is_covered_across_and_centred_down(rig):
    rig.start(200, 50)
    rig.inner("split-window", "-h", "-l", "60", "-c", "/tmp")
    rig.launch()
    [card] = rig.floating_panes()
    assert (card["left"], card["top"], card["width"], card["height"]) == (
        140,
        13,
        60,
        24,
    )
    assert card["path"] == "/tmp"


def test_pane_filling_the_window_is_covered_exactly(rig):
    rig.start(80, 20)
    rig.launch()
    [card] = rig.floating_panes()
    assert (card["left"], card["top"], card["width"], card["height"]) == (0, 0, 80, 20)


def test_second_press_focuses_the_open_card(rig):
    rig.start(200, 50)
    rig.launch()
    [card] = rig.floating_panes()
    rig.inner("select-pane", "-t", "%0")
    rig.launch()
    [again] = rig.floating_panes()
    assert again["id"] == card["id"]
    assert again["active"]
    assert not rig.gui_opened()


def test_window_other_than_ghostty_opens_the_gui(rig):
    rig.start(200, 50)
    rig.set_window_pid(os.getpid())
    rig.launch()
    assert rig.gui_opened()
    assert rig.floating_panes() == []


def test_unfocused_client_opens_the_gui(rig):
    rig.start(200, 50)
    # A focus-out report from the outer terminal, as Ghostty sends when its window loses focus.
    rig.outer("send-keys", "-H", "1b", "5b", "4f")
    wait_for(
        lambda: "focused" not in rig.inner("list-clients", "-F", "#{client_flags}")
    )
    rig.launch()
    assert rig.gui_opened()
    assert rig.floating_panes() == []


def test_ghostty_window_that_is_not_the_clients_opens_the_gui(rig):
    rig.start(200, 50)
    other_window = subprocess.Popen(
        ["/fake/ghostty", "-c", "sleep 600; : /tmux"], executable=BASH_PATH
    )
    try:
        rig.set_window_pid(other_window.pid)
        rig.launch()
    finally:
        other_window.kill()
        other_window.wait()
    assert rig.gui_opened()
    assert rig.floating_panes() == []
