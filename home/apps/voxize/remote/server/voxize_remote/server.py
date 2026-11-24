"""voxize-remote, the server: dictate on the client (the Voxize Remote app), get the text in the tmux pane its
Termux is looking at.

    voxize-remote serve [--mock] [--debug-adb]   run the server (foreground)
    voxize-remote pair                           pair a client (asks for the code the client shows)
    voxize-remote devices | unpair DEVICE_ID     list or forget paired clients
    voxize-remote status | cancel                the dictation in progress

One paired client at a time keeps a TCP connection open (frames.py). Only a tap on the client starts a dictation: the
server picks the target pane, spawns ``python -m voxize.backend --audio-fd FD`` (Voxize's backend, reading the
client's audio from a pipe instead of the microphone) and tells the client to capture. The next tap stops capture; once the client has sent its last frame the
backend transcribes and cleans up, and the result goes into the target pane as a bracketed paste, without Enter. This
machine can see and cancel a dictation, never start one.

Who may connect, checked in this order:

- the address: the Tailscale address of another node owned by this machine's Tailscale user (``tailscale whois``);
  loopback (``adb reverse``) only with ``--debug-adb``. Run by hand, the server listens on the Tailscale address (and
  loopback with ``--debug-adb``); under systemd on every address, and the firewall opens the port on tailscale0 only.
- the pairing: the node a client paired from, and proof of that client's secret (pairing.py); the server proves its own
  first.
"""

from __future__ import annotations

import argparse
import array
import asyncio
import contextlib
import dataclasses
import ipaddress
import json
import math
import os
import signal
import socket
import subprocess
import sys
import time

from voxize_remote import frames, pairing

PROTOCOL_VERSION = 2
DEFAULT_PORT = 7223
# How often, while a client is connected, the server checks whether its Termux has a tmux session open.
SESSION_POLL_SECONDS = 1.0
# The hub's tmux session (home/apps/claude-code/remote/hub.sh); its attached client is the client.
DEFAULT_SESSION = "remote"
# The client acknowledges a halt with "captured" once its last frame is out; past this the server stops anyway.
CAPTURED_TIMEOUT_SECONDS = 5.0
BACKEND_EXIT_TIMEOUT_SECONDS = 10.0
# A dictation nobody stops: the client's screen died, or the toggle went to the wrong place.
MAXIMUM_RECORDING_SECONDS = 600.0
# The client pings every 25 seconds; a connection silent for longer than this went away without a FIN (Doze, a
# dropped Wi-Fi), and the next client connection would otherwise wait behind it.
CLIENT_SILENCE_SECONDS = 90.0
# Until a client has proved itself: how long it may take, and how big a frame it may send.
HANDSHAKE_SECONDS = 10.0
UNAUTHENTICATED_FRAME_BYTES = 4096
# How long ``voxize-remote pair`` keeps a pairing window open.
PAIRING_WINDOW_SECONDS = 120.0
# Connections being identified at once (each runs `tailscale status` and `tailscale whois`) and how long that may take.
IDENTIFYING_AT_ONCE = 8
IDENTIFY_SECONDS = 15.0


def stderr_is_the_journal() -> bool:
    """systemd's own test: JOURNAL_STREAM names the journal's stream as device:inode, which stderr still is."""
    device, _, inode = os.environ.get("JOURNAL_STREAM", "").partition(":")
    try:
        status = os.fstat(sys.stderr.fileno())
        return (status.st_dev, status.st_ino) == (int(device), int(inode))
    except (OSError, ValueError):
        return False


# The journal stamps every line with the time and the unit already; a terminal gets both from the line itself.
LOG_PREFIX = None if stderr_is_the_journal() else "voxize-remote: "


def log(message: str) -> None:
    prefix = "" if LOG_PREFIX is None else f"{time.strftime('%H:%M:%S')} {LOG_PREFIX}"
    print(f"{prefix}{message}", file=sys.stderr, flush=True)


def control_socket_path() -> str:
    runtime_directory = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(runtime_directory, "voxize-remote.sock")


# ── tmux ──


class Tmux:
    def __init__(
        self, socket_path: str | None, session: str, any_pane: bool = False
    ) -> None:
        self._prefix = ["tmux"] + (["-S", socket_path] if socket_path else [])
        self.session = session
        self.any_pane = any_pane

    def run(self, *arguments: str, stdin: str | None = None) -> str:
        try:
            completed = subprocess.run(
                [*self._prefix, *arguments],
                input=stdin,
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as error:
            raise RuntimeError(f"tmux {arguments[0]}: {error}") from None
        if completed.returncode != 0:
            raise RuntimeError(
                f"tmux {arguments[0]}: {completed.stderr.strip() or completed.returncode}"
            )
        return completed.stdout

    def pick_target(self) -> dict:
        """The pane Termux on the client is looking at: the hub session's most recently active tmux client.

        With no client attached the client shows the hub's list, not a pane, so there is nothing to paste into; only
        ``any_pane`` (tests, scratch sessions) falls back to the session's current pane.
        """
        fields = "#{client_activity}\t#{client_session}\t#{pane_id}\t#{pane_current_path}\t#{window_name}"
        clients = []
        for line in self.run("list-clients", "-F", fields).splitlines():
            parts = line.split("\t")
            if len(parts) == 5 and parts[1] == self.session:
                clients.append(parts)
        if clients:
            _, _, pane_id, path, window = max(
                clients, key=lambda parts: int(parts[0] or 0)
            )
        elif not self.any_pane:
            raise RuntimeError(
                f"open a session in Termux first (nothing is attached to tmux session {self.session!r})"
            )
        else:
            line = self.run(
                "display-message", "-p", "-t", f"{self.session}:", fields
            ).rstrip("\n")
            _, _, pane_id, path, window = line.split("\t")
        return {"pane_id": pane_id, "path": path, "window": window}

    def session_attached(self) -> bool:
        """Is any tmux client attached to the hub session (the client's Termux, inside a session)?"""
        try:
            sessions = self.run("list-clients", "-F", "#{client_session}").split()
        except RuntimeError:
            return False
        return self.session in sessions

    def paste(self, pane_id: str, text: str) -> None:
        """Into the pane's prompt, never submitted.

        Claude Code asks for bracketed paste, where newlines stay newlines; anything else would take each one as Enter,
        so there the lines are joined with spaces.
        """
        if (
            self.run(
                "display-message", "-p", "-t", pane_id, "#{bracket_paste_flag}"
            ).strip()
            != "1"
        ):
            text = " ".join(text.split())
        self.run("load-buffer", "-b", "voxize-remote", "-", stdin=text)
        self.run("paste-buffer", "-p", "-d", "-b", "voxize-remote", "-t", pane_id)


# ── who may connect ──


def tailscale_json(subcommand: str, *positional: str) -> dict:
    # Flags go before positional arguments: the CLI stops reading flags at the first one.
    completed = subprocess.run(
        ["tailscale", subcommand, "--json", *positional],
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or f"exit {completed.returncode}")
    return json.loads(completed.stdout)


def tailscale_ipv4() -> str | None:
    try:
        completed = subprocess.run(
            ["tailscale", "ip", "-4"], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    address = completed.stdout.strip().splitlines()
    return address[0] if completed.returncode == 0 and address else None


class Refused(Exception):
    """A connection that may not talk to the server; the message says why, for the log."""


@dataclasses.dataclass(frozen=True)
class Peer:
    node_id: str
    node_name: str
    label: str


def identify_peer(address: str, allow_loopback: bool) -> Peer:
    """Who is connecting, by address alone; Refused unless it may go on to pair or prove its pairing."""
    ip = ipaddress.ip_address(address.split("%")[0])
    # A dual-stack listener (systemd's) sees IPv4 peers as ::ffff:a.b.c.d.
    ip = getattr(ip, "ipv4_mapped", None) or ip
    address = str(ip)
    if ip.is_loopback:
        if not allow_loopback:
            raise Refused("loopback connections need --debug-adb")
        return Peer(pairing.LOOPBACK_NODE, "loopback", "loopback")
    try:
        status = tailscale_json("status")
        peer = tailscale_json("whois", address)
        own_user_id, own_node_id = status["Self"]["UserID"], status["Self"]["ID"]
        own_tags = status["Self"].get("Tags")
    except (
        Exception
    ) as error:  # noqa: BLE001 — any failure to identify the peer refuses it
        raise Refused(f"tailscale could not identify {address}: {error}") from None
    if own_tags:
        # A tagged node's user is the tailnet's shared tagged-devices user: every tagged node would pass as "ours".
        raise Refused(
            "this machine is a tagged Tailscale node; its owner cannot tell Stan's devices apart"
        )
    profile = peer.get("UserProfile") or {}
    node = peer.get("Node") or {}
    node_id = node.get("StableID") or ""
    node_name = pairing.printable(
        node.get("ComputedName") or node.get("Name") or address
    )
    login = pairing.printable(profile.get("LoginName"))
    if not node_id:
        raise Refused(f"{address} has no Tailscale node id")
    if profile.get("ID") != own_user_id:
        raise Refused(f"{node_name} belongs to {login!r}, not this machine's user")
    if node_id == own_node_id:
        # A process on this machine dialling its own Tailscale address.
        raise Refused(f"{node_name} is this machine")
    return Peer(node_id, node_name, f"{node_name} ({login})")


# ── one dictation ──


class Dictation:
    """One backend process, from the first captured frame to the paste."""

    def __init__(self, server: Server, target: dict) -> None:
        self.server = server
        self.target = target
        self.phase = "starting"
        self.backend_state = "INITIALIZING"
        self.texts = {"live": "", "batch": "", "cleaned": ""}
        self.result = ""
        self.detail = ""
        # Voxize's pipeline estimate from 0 to 1 once it has one; None until then, which the client draws as a spinner.
        self.progress: float | None = None
        self.process: asyncio.subprocess.Process | None = None
        self.audio: asyncio.WriteTransport | None = None
        self.audio_bytes = 0
        # Loudness of everything received, for the log: a silenced microphone sends zeros, not an error.
        self.sum_of_squares = 0.0
        self.peak = 0
        self.stop_wanted = False
        self.stop_sent = False
        self.cancelled = False
        self.finished = asyncio.Event()
        self._captured_timer: asyncio.TimerHandle | None = None
        self._recording_timer: asyncio.TimerHandle | None = None

    async def begin(self, mock: bool) -> None:
        read_fd, write_fd = os.pipe()
        environment = dict(os.environ)
        # `python -m` puts the working directory first on sys.path, and the pane's directory may be any cloned
        # repository: a json.py there would run as Stan. The backend starts in / with the safe path; the pane's
        # directory reaches Voxize only as data, the `start` command's cwd (for WHISPER.txt).
        environment["PYTHONSAFEPATH"] = "1"
        if mock:
            environment.update(VOXIZE_MOCK="1", VOXIZE_MOCK_FAST="1")
        try:
            self.process = await asyncio.create_subprocess_exec(
                sys.executable,
                "-P",
                "-m",
                "voxize.backend",
                "--audio-fd",
                str(read_fd),
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                pass_fds=(read_fd,),
                env=environment,
                cwd="/",
            )
        finally:
            os.close(read_fd)
        loop = asyncio.get_running_loop()
        self.audio, _ = await loop.connect_write_pipe(
            asyncio.Protocol, os.fdopen(write_fd, "wb", buffering=0)
        )
        asyncio.create_task(self._read_events())
        self._recording_timer = loop.call_later(
            MAXIMUM_RECORDING_SECONDS, self._recording_too_long
        )
        log(
            f"dictation for {self.target['window']} ({self.target['pane_id']}), backend pid {self.process.pid}"
        )

    # Audio from the client.

    def feed(self, pcm: bytes) -> None:
        samples = array.array("h", pcm[: len(pcm) - len(pcm) % 2])
        if samples:
            self.sum_of_squares += sum(sample * sample for sample in samples)
            self.peak = max(self.peak, max(samples), -min(samples))
        if self.audio is not None and not self.audio.is_closing():
            self.audio.write(pcm)
            self.audio_bytes += len(pcm)

    def loudness(self) -> str:
        samples = self.audio_bytes // 2

        def dbfs(value: float) -> str:
            return (
                f"{20 * math.log10(value / 32768):.0f} dBFS" if value >= 1 else "silent"
            )

        rms = math.sqrt(self.sum_of_squares / samples) if samples else 0.0
        return f"RMS {dbfs(rms)}, peak {dbfs(self.peak)}"

    def _close_audio(self) -> None:
        # close() flushes what is buffered first; the backend's reader then sees end of file.
        if self.audio is not None and not self.audio.is_closing():
            self.audio.close()
        if self._captured_timer is not None:
            self._captured_timer.cancel()
            self._captured_timer = None
        if self._recording_timer is not None:
            self._recording_timer.cancel()
            self._recording_timer = None

    # Commands to the backend.

    def _command(self, message: dict) -> None:
        if (
            self.process is None
            or self.process.stdin is None
            or self.process.stdin.is_closing()
        ):
            return
        self.process.stdin.write((json.dumps(message) + "\n").encode())

    def request_stop(self) -> None:
        """The client was told to halt; stop once it reports its last frame, or after a timeout."""
        if self.phase not in ("starting", "recording"):
            return
        self.phase = "finishing"
        self.server.publish()
        self._captured_timer = asyncio.get_running_loop().call_later(
            CAPTURED_TIMEOUT_SECONDS, self.audio_done
        )

    def audio_done(self) -> None:
        """No more audio is coming: close the pipe, then let the backend stop (now or once it is capturing)."""
        if (
            self.cancelled
            or self.stop_wanted
            or self.phase in ("done", "cancelled", "error")
        ):
            return
        self._close_audio()
        self.stop_wanted = True
        self.phase = "processing"
        log(
            f"audio done: {self.audio_bytes} bytes ({self.audio_bytes / 48000:.1f}s), {self.loudness()}"
        )
        self._send_stop_if_ready()
        self.server.publish()

    def _send_stop_if_ready(self) -> None:
        if (
            self.stop_wanted
            and not self.stop_sent
            and self.backend_state in ("WARMING", "RECORDING")
        ):
            self.stop_sent = True
            self._command({"type": "stop"})

    def cancel(self, reason: str = "cancelled") -> None:
        if self.cancelled or self.finished.is_set():
            return
        self.cancelled = True
        self.detail = reason
        self._close_audio()
        self._command({"type": "cancel"})
        self.phase = "cancelled"
        self.server.publish()

    def _recording_too_long(self) -> None:
        log(f"recording passed {MAXIMUM_RECORDING_SECONDS:.0f}s; stopping")
        self.server.halt_client()
        self.audio_done()

    # Events from the backend.

    def display_text(self) -> str:
        return (
            self.result
            or self.texts["cleaned"]
            or self.texts["batch"]
            or self.texts["live"]
        )

    async def _read_events(self) -> None:
        assert self.process is not None and self.process.stdout is not None
        try:
            while line := await self.process.stdout.readline():
                try:
                    event = json.loads(line)
                except ValueError:
                    log(f"backend: bad line {line[:120]!r}")
                    continue
                self._on_event(event)
        finally:
            await self._wait_for_exit()

    def _on_event(self, event: dict) -> None:
        kind = event.get("type")
        if kind == "hello":
            if event.get("protocol") != 1:
                self.detail = (
                    f"backend speaks protocol {event.get('protocol')}, the server 1"
                )
                self._command({"type": "close", "trash_if_empty": True})
                return
            self._command(
                {"type": "start", "cwd": self.target["path"] or None, "glossaries": []}
            )
        elif kind == "session":
            log(f"session directory {event.get('dir')}")
        elif kind == "state":
            self.backend_state = event.get("state") or ""
            if (
                self.backend_state in ("WARMING", "RECORDING")
                and self.phase == "starting"
            ):
                self.phase = "recording"
            elif self.backend_state in ("TRANSCRIBING", "CLEANING"):
                self.phase = "processing"
            self._send_stop_if_ready()
            if self.backend_state == "READY":
                self._deliver()
            elif self.backend_state == "CANCELLED":
                self.phase = "cancelled"
                self._finish()
            elif self.backend_state == "ERROR":
                self.phase = "error"
                self.detail = event.get("error") or "the backend failed"
                self.server.halt_client()
                self._finish()
            self.server.publish()
        elif kind == "text":
            stage, op, text = (
                event.get("stage"),
                event.get("op"),
                event.get("text") or "",
            )
            if stage in self.texts:
                self.texts[stage] = self.texts[stage] + text if op == "append" else text
                self.server.publish()
        elif kind == "progress":
            fraction = event.get("fraction")
            fraction = float(fraction) if isinstance(fraction, (int, float)) else None
            previous = self.progress
            self.progress = fraction
            # Voxize reports up to 20 times a second; the client needs a step it can see.
            if (fraction is None) != (previous is None) or (
                fraction is not None
                and (abs(fraction - previous) >= 0.01 or (fraction >= 1.0 > previous))
            ):
                self.server.publish()
        elif kind == "result":
            self.result = event.get("text") or ""
        elif kind == "no_speech":
            self.detail = "no speech"
        elif kind == "failure":
            self.detail = event.get("message") or ""
            self.server.publish()
        elif kind == "costs":
            total = event.get("total")
            if total is not None:
                log(f"cost ${total:.4f}")

    def _deliver(self) -> None:
        text = self.result.strip()
        if not text:
            self.phase = "done"
            self.detail = self.detail or "nothing to paste"
        else:
            try:
                self.server.tmux.paste(self.target["pane_id"], text)
                self.phase = "done"
                self.detail = f"pasted into {self.target['window']}"
                log(f"pasted {len(text)} characters into {self.target['pane_id']}")
            except RuntimeError as error:
                self.phase = "error"
                self.detail = f"paste failed: {error}"
                log(self.detail)
        self._finish()

    def _finish(self) -> None:
        self._close_audio()
        self._command({"type": "close", "trash_if_empty": True})

    async def _wait_for_exit(self) -> None:
        assert self.process is not None
        try:
            await asyncio.wait_for(self.process.wait(), BACKEND_EXIT_TIMEOUT_SECONDS)
        except TimeoutError:
            log("backend did not exit; killing it")
            self.process.kill()
            await self.process.wait()
        self._close_audio()
        if self.phase not in ("done", "cancelled", "error"):
            self.phase = "error"
            self.detail = self.detail or f"backend exited ({self.process.returncode})"
        detail = (
            f" ({self.detail})" if self.detail and self.detail != self.phase else ""
        )
        log(f"dictation ended: {self.phase}{detail}")
        self.finished.set()
        self.server.dictation_ended(self)


# ── the server ──


class Client:
    def __init__(self, writer: asyncio.StreamWriter, name: str, device_id: str) -> None:
        self.writer = writer
        self.name = name
        self.device_id = device_id

    def send(self, message: dict) -> None:
        if not self.writer.is_closing():
            self.writer.write(frames.encode_json(message))


class PairingWindow:
    """``voxize-remote pair`` in progress: one client at a time tries to pair through it, until one succeeds."""

    def __init__(self, deadline: float) -> None:
        self.deadline = deadline
        # A client is mid-attempt; a failed attempt frees the window again while time remains.
        self.taken = False
        # Lines for the waiting `voxize-remote pair` (JSON objects).
        self.events: asyncio.Queue[dict] = asyncio.Queue()
        # What Stan typed on this machine, one line per attempt.
        self.typed: asyncio.Queue[str] = asyncio.Queue()

    def remaining(self) -> float:
        return self.deadline - time.monotonic()


class Server:
    def __init__(self, tmux: Tmux, mock: bool, store, debug_adb: bool) -> None:
        self.tmux = tmux
        self.mock = mock
        self.store = store
        self.debug_adb = debug_adb
        self.client: Client | None = None
        self.dictation: Dictation | None = None
        self.pairing_window: PairingWindow | None = None
        self.identify_slots = asyncio.Semaphore(IDENTIFYING_AT_ONCE)
        self.last: dict = {"phase": "idle", "text": "", "detail": ""}
        # Whether the client's Termux has a session open; the client shows its floating button only then.
        self.session = False
        # When the server last had a reason to stay up: a client, a dictation, or a pairing window.
        self.busy_at = time.monotonic()

    def idle_seconds(self) -> float:
        if (
            self.client is not None
            or self.dictation is not None
            or self.pairing_window is not None
        ):
            self.busy_at = time.monotonic()
        return time.monotonic() - self.busy_at

    async def watch_session(self) -> None:
        """While a client is connected, keep its `session` flag current."""
        while True:
            await asyncio.sleep(SESSION_POLL_SECONDS)
            if self.client is None:
                continue
            try:
                attached = await asyncio.to_thread(self.tmux.session_attached)
            except (
                Exception
            ) as error:  # noqa: BLE001 — the watch must outlive any one failure
                log(f"checking the tmux session failed: {error}")
                continue
            if attached != self.session:
                self.session = attached
                self.publish()

    def status(self) -> dict:
        dictation = self.dictation
        if dictation is not None:
            self.last = {
                "phase": dictation.phase,
                "text": dictation.display_text(),
                "detail": dictation.detail or f"for {dictation.target['window']}",
            }
            if dictation.phase in ("finishing", "processing"):
                self.last["progress"] = dictation.progress
        return {
            "type": "status",
            "client": self.client.name if self.client else None,
            "session": self.session,
            **self.last,
        }

    def publish(self) -> None:
        if self.client is not None:
            self.client.send(self.status())

    def drop_device(self, device_id: str, reason: str) -> None:
        """A paired client that lost its pairing: its dictation is dropped (never pasted) and its connection closed."""
        if self.client is not None and self.client.device_id == device_id:
            if self.dictation is not None:
                self.dictation.cancel(reason)
            self.client.writer.close()

    def halt_client(self) -> None:
        if self.client is not None:
            self.client.send({"type": "halt"})

    async def toggle(self) -> str:
        """A tap on the client: start a dictation, or stop the one recording. Only the client may start one."""
        dictation = self.dictation
        if dictation is None:
            if self.client is None:
                return "no client connected"
            try:
                target = self.tmux.pick_target()
            except (RuntimeError, ValueError) as error:
                self.last = {"phase": "error", "text": "", "detail": str(error)}
                self.publish()
                return self.last["detail"]
            dictation = Dictation(self, target)
            self.dictation = dictation
            try:
                await dictation.begin(self.mock)
            except (
                Exception
            ) as error:  # noqa: BLE001 — report any spawn failure to the client
                self.dictation = None
                self.halt_client()
                self.last = {
                    "phase": "error",
                    "text": "",
                    "detail": f"backend did not start: {error}",
                }
                self.publish()
                return self.last["detail"]
            # The client's connection is not read while begin() runs, so its audio waits in the socket until here.
            if self.client is not None:
                self.client.send({"type": "capture"})
            self.publish()
            return f"recording for {target['window']}"
        if dictation.phase in ("starting", "recording"):
            self.halt_client()
            dictation.request_stop()
            return "stopping"
        return f"busy ({dictation.phase})"

    def cancel(self) -> str:
        if self.dictation is None:
            return "nothing to cancel"
        self.halt_client()
        self.dictation.cancel()
        return "cancelled"

    def dictation_ended(self, dictation: Dictation) -> None:
        if self.dictation is dictation:
            self.status()  # keep its last words for the client
            self.dictation = None
            self.publish()

    # The client connection.

    async def serve_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        address = writer.get_extra_info("peername")[0]
        client: Client | None = None
        try:
            async with self.identify_slots:
                peer = await asyncio.wait_for(
                    asyncio.to_thread(identify_peer, address, self.debug_adb),
                    IDENTIFY_SECONDS,
                )
            kind, payload = await asyncio.wait_for(
                frames.read(reader, UNAUTHENTICATED_FRAME_BYTES), HANDSHAKE_SECONDS
            )
            first = frames.decode_json(payload) if kind == frames.JSON else {}
            if first.get("protocol") != PROTOCOL_VERSION:
                writer.write(
                    frames.encode_json(
                        {
                            "type": "error",
                            "message": f"the server speaks protocol {PROTOCOL_VERSION}",
                        }
                    )
                )
                raise Refused(f"{peer.label}: protocol {first.get('protocol')!r}")
            if first.get("type") == "pair":
                await self._pair_client(peer, first, reader, writer)
                return
            if first.get("type") != "hello":
                raise Refused(
                    f"{peer.label}: expected hello, got {first.get('type')!r}"
                )
            device = await self._authenticate(peer, first, reader, writer)
            client = Client(
                writer,
                f"{pairing.printable(device.name)} via {peer.label}",
                device.device_id,
            )
            if self.client is not None:
                log(f"replacing {self.client.name}")
                self.client.writer.close()
            self.client = client
            log(f"client connected: {client.name}")
            self.session = await asyncio.to_thread(self.tmux.session_attached)
            self.publish()
            while True:
                kind, payload = await asyncio.wait_for(
                    frames.read(reader), CLIENT_SILENCE_SECONDS
                )
                if kind == frames.AUDIO:
                    if self.dictation is not None:
                        self.dictation.feed(payload)
                    continue
                message = frames.decode_json(payload)
                await self._on_client_message(message)
        except Refused as refusal:
            log(f"refused {address}: {refusal}")
        except (asyncio.IncompleteReadError, ConnectionError, TimeoutError):
            pass
        except frames.FrameError as error:
            log(f"{address}: {error}")
        finally:
            writer.close()
            if client is not None and self.client is client:
                self.client = None
                log(f"client disconnected: {client.name}")
                # Keep what was said: a dropped connection ends the recording, it does not discard it.
                if self.dictation is not None and self.dictation.phase in (
                    "starting",
                    "recording",
                    "finishing",
                ):
                    self.dictation.audio_done()

    async def _authenticate(
        self,
        peer: Peer,
        hello: dict,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> pairing.Device:
        """The challenge both ways (pairing.py); the paired client, or Refused."""
        device = (await asyncio.to_thread(self.store.load)).get(
            str(hello.get("device_id"))
        )
        client_nonce = pairing.decode_nonce(hello.get("nonce"))
        if device is None:
            writer.write(
                frames.encode_json(
                    {"type": "error", "message": "not paired with this server"}
                )
            )
            raise Refused(f"{peer.label}: unknown device {hello.get('device_id')!r}")
        if client_nonce is None:
            raise Refused(f"{peer.label}: hello without a nonce")
        if device.node_id != peer.node_id:
            # The secret belongs to another Tailscale node (or to loopback): a copied secret is not enough.
            raise Refused(
                f"{peer.label}: {device.name} paired from {device.node_name}, not from here"
            )
        server_nonce = pairing.new_nonce()
        writer.write(
            frames.encode_json(
                {
                    "type": "challenge",
                    "nonce": server_nonce.hex(),
                    "proof": pairing.server_proof(
                        device.secret, client_nonce, server_nonce
                    ),
                }
            )
        )
        kind, payload = await asyncio.wait_for(
            frames.read(reader, UNAUTHENTICATED_FRAME_BYTES), HANDSHAKE_SECONDS
        )
        answer = frames.decode_json(payload) if kind == frames.JSON else {}
        expected = pairing.client_proof(device.secret, client_nonce, server_nonce)
        if answer.get("type") != "answer" or not pairing.proofs_match(
            expected, answer.get("proof")
        ):
            raise Refused(f"{peer.label}: wrong proof for {device.name}")
        return device

    async def _pair_client(
        self,
        peer: Peer,
        request: dict,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        window = self.pairing_window
        if window is None or window.taken or window.remaining() <= 0:
            writer.write(
                frames.encode_json(
                    {
                        "type": "error",
                        "message": "run `voxize-remote pair` on the server first",
                    }
                )
            )
            raise Refused(f"{peer.label}: pairing request with no pairing window open")
        commitment = request.get("commitment")
        if not isinstance(commitment, str) or len(commitment) != 64:
            raise Refused(f"{peer.label}: pairing request without a commitment")
        window.taken = True
        paired = False
        try:
            name = pairing.printable(request.get("device") or "client")
            device = pairing.new_device(name, peer.node_id, peer.node_name)
            writer.write(
                frames.encode_json(
                    {
                        "type": "pairing",
                        "device_id": device.device_id,
                        "secret": device.secret.hex(),
                        "server": pairing.printable(socket.gethostname()),
                    }
                )
            )
            kind, payload = await asyncio.wait_for(
                frames.read(reader, UNAUTHENTICATED_FRAME_BYTES),
                max(window.remaining(), 0.01),
            )
            reveal = frames.decode_json(payload) if kind == frames.JSON else {}
            pairing_nonce = pairing.decode_nonce(reveal.get("nonce"))
            if (
                reveal.get("type") != "reveal"
                or pairing_nonce is None
                or not pairing.proofs_match(
                    pairing.commitment(pairing_nonce), commitment
                )
            ):
                raise Refused(
                    f"{peer.label}: the revealed nonce does not match its commitment"
                )
            code = pairing.confirmation_code(device.secret, pairing_nonce)
            await window.events.put(
                {"event": "code_requested", "device": name, "node": peer.node_name}
            )
            log(
                f"pairing {name} from {peer.label}: waiting for the code to be typed here"
            )

            while not window.typed.empty():
                window.typed.get_nowait()  # typed for an attempt that already ended
            typed_task = asyncio.ensure_future(window.typed.get())
            # Anything more from the client (it cancelled) or the connection closing ends the attempt.
            gone_task = asyncio.ensure_future(
                frames.read(reader, UNAUTHENTICATED_FRAME_BYTES)
            )
            done, pending = await asyncio.wait(
                {typed_task, gone_task},
                timeout=max(window.remaining(), 0.01),
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()
            if gone_task.done() and not gone_task.cancelled():
                gone_task.exception()  # retrieved, so asyncio does not report it
            typed = typed_task.result() if typed_task in done else None
            if typed is None:
                raise Refused(
                    f"{peer.label}: {name} cancelled or no code was typed in time"
                )
            if not pairing.codes_match(code, typed):
                writer.write(
                    frames.encode_json(
                        {
                            "type": "error",
                            "message": "the code typed on the server did not match",
                        }
                    )
                )
                raise Refused(f"{peer.label}: the code typed for {name} did not match")
            try:
                await asyncio.to_thread(self.store.add, device)
            except (
                Exception
            ) as error:  # noqa: BLE001 — a keyring failure must end the attempt, not hang it
                writer.write(
                    frames.encode_json(
                        {
                            "type": "error",
                            "message": "the server could not store the pairing",
                        }
                    )
                )
                raise Refused(
                    f"storing the pairing of {name} failed: {error}"
                ) from None
            # One pairing per Tailscale node: pairing again (a re-run of `cc remote setup`) replaces the earlier one.
            for other in (await asyncio.to_thread(self.store.load)).values():
                if (
                    other.node_id == peer.node_id
                    and other.device_id != device.device_id
                ):
                    await asyncio.to_thread(self.store.remove, other.device_id)
                    self.drop_device(other.device_id, "paired again")
                    log(
                        f"replaced the earlier pairing {other.device_id} from {peer.node_name}"
                    )
            writer.write(frames.encode_json({"type": "paired"}))
            await writer.drain()
            paired = True
            await window.events.put(
                {"event": "paired", "device_id": device.device_id, "device": name}
            )
            log(f"paired {name} ({device.device_id}) from {peer.label}")
        except Refused as refusal:
            await window.events.put(
                {"event": "rejected", "reason": str(refusal).split(": ", 1)[-1]}
            )
            raise
        except (
            TimeoutError,
            asyncio.IncompleteReadError,
            ConnectionError,
            frames.FrameError,
        ) as error:
            await window.events.put(
                {
                    "event": "rejected",
                    "reason": f"the pairing attempt broke off ({type(error).__name__})",
                }
            )
            raise Refused(f"{peer.label}: pairing broke off") from None
        finally:
            if not paired:
                window.taken = False

    async def _on_client_message(self, message: dict) -> None:
        kind = message.get("type")
        if kind == "toggle":
            log(f"client: toggle → {await self.toggle()}")
        elif kind == "cancel":
            log(f"client: cancel → {self.cancel()}")
        elif kind == "capturing":
            log(
                f"client microphone open: {message.get('rate')} Hz, source {message.get('source')}"
            )
        elif kind == "captured":
            if self.dictation is not None:
                self.dictation.audio_done()
        elif kind == "mic_error":
            log(f"client microphone failed: {message.get('message')}")
            if self.dictation is not None:
                self.dictation.cancel(f"client microphone: {message.get('message')}")
        elif kind == "ping":
            if self.client is not None:
                self.client.send({"type": "pong"})

    # The local control socket.

    async def serve_control(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            words = (await asyncio.wait_for(reader.readline(), 5)).decode().split()
            command, arguments = (words[0], words[1:]) if words else ("", [])
            if command == "pair":
                await self._control_pair(reader, writer)
                return
            if command == "cancel":
                reply = {"result": self.cancel()}
            elif command == "status":
                reply = self.status()
            elif command == "devices":
                devices = await asyncio.to_thread(self.store.load)
                reply = {"devices": [device.summary() for device in devices.values()]}
            elif command == "unpair" and len(arguments) == 1:
                removed = await asyncio.to_thread(self.store.remove, arguments[0])
                reply = {"result": "unpaired" if removed else "no such device"}
                if removed:
                    self.drop_device(arguments[0], "unpaired")
            else:
                reply = {"error": f"unknown command {' '.join(words)!r}"}
            writer.write((json.dumps(reply) + "\n").encode())
            await writer.drain()
        except (TimeoutError, ConnectionError):
            pass
        finally:
            writer.close()

    async def _control_pair(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        """Open a pairing window; relay the code to `voxize-remote pair` and its yes or no back."""

        def send(event: dict) -> None:
            writer.write((json.dumps(event) + "\n").encode())

        if self.pairing_window is not None and self.pairing_window.remaining() > 0:
            send({"event": "busy"})
            await writer.drain()
            return
        window = PairingWindow(time.monotonic() + PAIRING_WINDOW_SECONDS)
        self.pairing_window = window
        log("pairing window open")
        # The other end is read all along, so the window closes as soon as it goes, whatever the attempt is doing.
        line_task = asyncio.ensure_future(reader.readline())
        event_task: asyncio.Future | None = None
        awaiting_code = False
        try:
            send({"event": "open", "seconds": PAIRING_WINDOW_SECONDS})
            await writer.drain()
            while True:
                event_task = event_task or asyncio.ensure_future(window.events.get())
                done, _ = await asyncio.wait(
                    {line_task, event_task},
                    timeout=max(window.remaining(), 0.01),
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if not done:
                    raise TimeoutError
                if line_task in done:
                    line = line_task.result()
                    if not line:
                        return  # `voxize-remote pair` went away: the window closes
                    if awaiting_code:
                        awaiting_code = False
                        await window.typed.put(line.decode(errors="replace").strip())
                    line_task = asyncio.ensure_future(reader.readline())
                if event_task in done:
                    event = event_task.result()
                    event_task = None
                    send(event)
                    await writer.drain()
                    awaiting_code = event["event"] == "code_requested"
                    if event["event"] == "paired":
                        return
        except TimeoutError:
            send({"event": "expired"})
            with contextlib.suppress(ConnectionError):
                await writer.drain()
        except ConnectionError:
            pass
        finally:
            for task in (line_task, event_task):
                if task is not None:
                    task.cancel()
            # An attempt still waiting for a typed code gets an empty one, which matches nothing.
            window.typed.put_nowait("")
            if self.pairing_window is window:
                self.pairing_window = None
            log("pairing window closed")


# What to stop before running a server by hand: systemd holds the port and the control socket between runs.
STOP_SERVICE_HINT = "systemctl --user stop voxize-remote.service voxize-remote-clients.socket voxize-remote-control.socket"


def control_answers(path: str) -> bool:
    """Something listens on this control socket (a socket left by a server that died does not)."""
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        probe.settimeout(2)
        probe.connect(path)
        return True
    except OSError:
        return False
    finally:
        probe.close()


def parse_listen(value: str) -> tuple[str, int]:
    host, _, port = value.rpartition(":")
    return host.strip("[]") or "127.0.0.1", int(port or DEFAULT_PORT)


def systemd_sockets() -> dict[str, list[socket.socket]]:
    """Sockets systemd passed (socket activation), by FileDescriptorName: "clients" and "control"."""
    if os.environ.get("LISTEN_PID") != str(os.getpid()):
        return {}
    count = int(os.environ.get("LISTEN_FDS", "0"))
    names = os.environ.get("LISTEN_FDNAMES", "").split(":")
    sockets: dict[str, list[socket.socket]] = {}
    for offset in range(count):
        descriptor = 3 + offset
        name = names[offset] if offset < len(names) else "clients"
        sockets.setdefault(name, []).append(socket.socket(fileno=descriptor))
    for variable in ("LISTEN_PID", "LISTEN_FDS", "LISTEN_FDNAMES"):
        os.environ.pop(variable, None)  # not for the backend processes
    return sockets


async def serve(arguments: argparse.Namespace) -> None:
    store = (
        pairing.FileStore(arguments.pairing_file)
        if arguments.pairing_file
        else pairing.KeyringStore()
    )
    voxize_server = Server(
        Tmux(arguments.tmux_socket, arguments.session, arguments.any_pane),
        arguments.mock,
        store,
        arguments.debug_adb,
    )
    listeners = []
    control_path = None
    if arguments.systemd:
        inherited = systemd_sockets()
        if not inherited.get("clients") or not inherited.get("control"):
            sys.exit(
                "voxize-remote: --systemd needs the sockets named clients and control (voxize-remote.socket)"
            )
        for listener in inherited["clients"]:
            listeners.append(
                await asyncio.start_server(voxize_server.serve_client, sock=listener)
            )
            log(f"listening for clients on {listener.getsockname()[:2]} (from systemd)")
        for listener in inherited["control"]:
            listeners.append(
                await asyncio.start_unix_server(
                    voxize_server.serve_control, sock=listener
                )
            )
            log(f"control socket {listener.getsockname()} (from systemd)")
    else:
        listens = (
            [parse_listen(value) for value in arguments.listen]
            if arguments.listen
            else None
        )
        if listens is None:
            listens = [("127.0.0.1", arguments.port)] if arguments.debug_adb else []
            tailnet = tailscale_ipv4()
            if tailnet:
                listens.append((tailnet, arguments.port))
            if not listens:
                sys.exit(
                    "voxize-remote: no Tailscale address to listen on (and no --debug-adb)"
                )
        control_path = arguments.control_socket or control_socket_path()
        # Unlinking a live socket would cut its server off from every `voxize-remote` command until it restarts.
        if control_answers(control_path):
            sys.exit(
                f"voxize-remote: a server already answers on {control_path}; stop it first: {STOP_SERVICE_HINT}"
            )
        for host, port in listens:
            try:
                listeners.append(
                    await asyncio.start_server(voxize_server.serve_client, host, port)
                )
            except OSError as error:
                # asyncio rewrites strerror into a long sentence of its own; the errno's text is the short one.
                reason = os.strerror(error.errno) if error.errno else str(error)
                sys.exit(
                    f"voxize-remote: cannot listen on {host}:{port} ({reason}); if the service holds it: "
                    f"{STOP_SERVICE_HINT}"
                )
            log(f"listening for clients on {host}:{port}")
        with contextlib.suppress(FileNotFoundError):
            os.unlink(control_path)
        previous_umask = os.umask(0o077)
        try:
            listeners.append(
                await asyncio.start_unix_server(
                    voxize_server.serve_control, control_path
                )
            )
        finally:
            os.umask(previous_umask)
        flags = [
            name
            for name, on in (
                ("mock backend", arguments.mock),
                ("adb loopback allowed", arguments.debug_adb),
            )
            if on
        ]
        suffix = f" ({', '.join(flags)})" if flags else ""
        log(f"control socket {control_path}{suffix}")

    stopping = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signal_number in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signal_number, stopping.set)
    watcher = asyncio.create_task(voxize_server.watch_session())

    async def exit_when_idle() -> None:
        # Started on demand by systemd, the server goes away once nobody needs it; the socket stays.
        while arguments.idle_exit:
            await asyncio.sleep(min(30.0, arguments.idle_exit / 4))
            if voxize_server.idle_seconds() >= arguments.idle_exit:
                log(f"no client for {arguments.idle_exit:.0f}s; exiting")
                stopping.set()
                return

    idler = asyncio.create_task(exit_when_idle())
    await stopping.wait()
    watcher.cancel()
    idler.cancel()
    log("shutting down")
    if voxize_server.dictation is not None:
        voxize_server.cancel()
        with contextlib.suppress(TimeoutError):
            await asyncio.wait_for(
                voxize_server.dictation.finished.wait(), BACKEND_EXIT_TIMEOUT_SECONDS
            )
    for listener_server in listeners:
        listener_server.close()
    if control_path is not None:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(control_path)


def connect_control(socket_path: str | None) -> socket.socket:
    path = socket_path or control_socket_path()
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        connection.connect(path)
    except OSError as error:
        connection.close()
        sys.exit(f"voxize-remote: the server is not running ({path}: {error})")
    return connection


def control_request(command: str, socket_path: str | None) -> dict:
    with connect_control(socket_path) as connection:
        connection.settimeout(10)
        try:
            connection.sendall(f"{command}\n".encode())
            reply = b""
            while chunk := connection.recv(65536):
                reply += chunk
        except OSError as error:
            sys.exit(
                f"voxize-remote: the server did not answer ({error}); see journalctl --user -u voxize-remote"
            )
    try:
        return json.loads(reply)
    except ValueError:
        sys.exit(
            "voxize-remote: the server closed the connection without an answer (it may be exiting); try again"
        )


def describe(command: str, reply: dict) -> str:
    """The control socket's answer, for a person."""
    if "error" in reply:
        return f"voxize-remote: {reply['error']}"
    if command == "devices":
        devices = reply.get("devices") or []
        if not devices:
            return "No client is paired. Pair one with: voxize-remote pair"
        return "\n".join(
            f"{device['name']}  (device {device['device_id']}, Tailscale node {device['node']}, paired {device['paired_at']})"
            for device in devices
        )
    if command == "status":
        lines = [f"Client: {reply.get('client') or 'none connected'}"]
        if reply.get("client"):
            lines.append(
                f"Termux session open: {'yes' if reply.get('session') else 'no'}"
            )
        phase = reply.get("phase", "idle")
        lines.append(
            f"Dictation: {phase}"
            + (f" ({reply['detail']})" if reply.get("detail") else "")
        )
        if reply.get("progress") is not None:
            lines.append(f"Progress: {round(reply['progress'] * 100)}%")
        return "\n".join(lines)
    return str(reply.get("result", reply))


def control(command: str, socket_path: str | None, as_json: bool = False) -> int:
    reply = control_request(command, socket_path)
    print(json.dumps(reply) if as_json else describe(command.split()[0], reply))
    return 1 if "error" in reply else 0


def ask_for_code(prompt: str) -> str:
    """One line from Stan, with anything typed before the prompt thrown away."""
    if sys.stdin.isatty():
        import termios

        termios.tcflush(sys.stdin, termios.TCIFLUSH)
    try:
        return input(prompt)
    except EOFError:
        return ""


def pair(socket_path: str | None) -> int:
    """Open a pairing window; Stan types the code the client shows.

    Every line is flushed: `cc remote setup` and the tests read this through a pipe.
    """
    with connect_control(socket_path) as connection, connection.makefile(
        "rwb", buffering=0
    ) as stream:
        stream.write(b"pair\n")
        for line in stream:
            event = json.loads(line)
            kind = event.get("event")
            if kind == "busy":
                print(
                    "Another `voxize-remote pair` is already waiting.",
                    file=sys.stderr,
                    flush=True,
                )
                return 1
            if kind == "open":
                print(
                    f"In Voxize Remote on the client, tap \"Pair with server\" within {event['seconds']:.0f} seconds.",
                    flush=True,
                )
            elif kind == "code_requested":
                print(
                    f"\n{event['device']} ({event['node']}) asks to pair.", flush=True
                )
                typed = ask_for_code("Type the code the client shows (Enter refuses): ")
                stream.write(f"{typed.strip()}\n".encode())
            elif kind == "paired":
                print(f"Paired {event['device']} ({event['device_id']}).", flush=True)
                return 0
            elif kind == "rejected":
                print(
                    f"Not paired: {event.get('reason', 'refused')}. Waiting for another try.",
                    file=sys.stderr,
                    flush=True,
                )
            elif kind == "expired":
                print("The pairing window closed.", file=sys.stderr, flush=True)
                return 1
    return 1


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="voxize-remote", description=__doc__.split("\n\n")[0]
    )
    parser.add_argument(
        "--control-socket", help="default: $XDG_RUNTIME_DIR/voxize-remote.sock"
    )
    subcommands = parser.add_subparsers(dest="command", required=True)
    serve_parser = subcommands.add_parser("serve", help="run the server")
    serve_parser.add_argument(
        "--listen",
        action="append",
        metavar="HOST:PORT",
        help="default: the Tailscale address (and loopback with --debug-adb)",
    )
    serve_parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    serve_parser.add_argument(
        "--session",
        default=DEFAULT_SESSION,
        help="tmux session the client's Termux attaches to",
    )
    serve_parser.add_argument("--tmux-socket", help="tmux -S socket (tests)")
    serve_parser.add_argument(
        "--any-pane",
        action="store_true",
        help="with no client attached, paste into the session's current pane",
    )
    serve_parser.add_argument(
        "--mock", action="store_true", help="mock backend: no API calls"
    )
    serve_parser.add_argument(
        "--debug-adb",
        action="store_true",
        help="also listen on loopback and accept clients there (adb reverse)",
    )
    serve_parser.add_argument(
        "--pairing-file",
        help="keep paired clients in this JSON file, not the keyring (tests)",
    )
    serve_parser.add_argument(
        "--systemd",
        action="store_true",
        help="take the listening sockets from systemd (voxize-remote.socket)",
    )
    serve_parser.add_argument(
        "--idle-exit",
        type=float,
        default=0,
        metavar="SECONDS",
        help="exit after this long with no client (0: never)",
    )
    subcommands.add_parser("pair", help="pair a client")
    devices_parser = subcommands.add_parser("devices", help="list paired clients")
    devices_parser.add_argument(
        "--json", action="store_true", help="the control socket's JSON"
    )
    unpair_parser = subcommands.add_parser("unpair", help="forget a paired client")
    unpair_parser.add_argument("device_id")
    subcommands.add_parser("cancel", help="cancel the dictation in progress")
    status_parser = subcommands.add_parser(
        "status", help="the connected client and the dictation in progress"
    )
    status_parser.add_argument(
        "--json", action="store_true", help="the control socket's JSON"
    )
    arguments = parser.parse_args()
    if arguments.command == "serve":
        asyncio.run(serve(arguments))
    elif arguments.command == "pair":
        sys.exit(pair(arguments.control_socket))
    elif arguments.command == "unpair":
        sys.exit(control(f"unpair {arguments.device_id}", arguments.control_socket))
    else:
        sys.exit(
            control(
                arguments.command,
                arguments.control_socket,
                getattr(arguments, "json", False),
            )
        )


if __name__ == "__main__":
    main()
