"""The server end to end with the mock backend: fake client → server → backend → paste into a private tmux pane.

The refusals are tested by doing the forbidden thing against a running server.
"""

import asyncio
import contextlib
import io
import json
import os
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time
import unittest

from voxize_remote import fake_client, frames, pairing

SERVER = shutil.which("voxize-remote") or sys.exit("run with voxize-remote on PATH")


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix="voxize-remote-test.")
        self.tmux_socket = os.path.join(self.directory, "tmux.sock")
        self.control_socket = os.path.join(self.directory, "control.sock")
        self.pairing_file = os.path.join(self.directory, "paired.json")
        self.port = free_port()
        subprocess.run(
            [
                "tmux",
                "-S",
                self.tmux_socket,
                "-f",
                "/dev/null",
                "new-session",
                "-d",
                "-s",
                "remote",
                "-x",
                "200",
                "-y",
                "40",
                "-c",
                self.directory,
                "cat",
            ],
            check=True,
        )
        self.log = open(os.path.join(self.directory, "server.log"), "w+")
        self.server = None
        self.start_server()

    def start_server(self, *extra: str, debug_adb: bool = True, any_pane: bool = True):
        if self.server is not None:
            self.server.terminate()
            self.server.wait(20)
        if os.path.exists(self.control_socket):
            os.unlink(self.control_socket)
        arguments = [
            SERVER,
            "--control-socket",
            self.control_socket,
            "serve",
            "--mock",
            "--listen",
            f"127.0.0.1:{self.port}",
            "--tmux-socket",
            self.tmux_socket,
            "--pairing-file",
            self.pairing_file,
        ]
        arguments += ["--debug-adb"] if debug_adb else []
        arguments += ["--any-pane"] if any_pane else []
        self.server = subprocess.Popen(
            arguments + list(extra), stdout=subprocess.DEVNULL, stderr=self.log
        )
        deadline = time.monotonic() + 20
        while not os.path.exists(self.control_socket):
            self.assertIsNone(self.server.poll(), self.server_log())
            self.assertLess(
                time.monotonic(), deadline, "the server never opened its control socket"
            )
            time.sleep(0.05)

    def tearDown(self):
        self.server.terminate()
        self.server.wait(20)
        subprocess.run(["tmux", "-S", self.tmux_socket, "kill-server"], check=False)
        self.log.close()
        shutil.rmtree(self.directory, ignore_errors=True)

    def server_log(self) -> str:
        self.log.flush()
        self.log.seek(0)
        return self.log.read()

    def control(self, *command: str) -> dict:
        json_flag = ["--json"] if command[0] in ("status", "devices") else []
        completed = subprocess.run(
            [SERVER, "--control-socket", self.control_socket, *command, *json_flag],
            capture_output=True,
            text=True,
            check=False,
        )
        return (
            json.loads(completed.stdout)
            if json_flag
            else {"result": completed.stdout.strip()}
        )

    def test_status_and_devices_read_well_without_json(self):
        credentials = self.paired_client()
        devices = subprocess.run(
            [SERVER, "--control-socket", self.control_socket, "devices"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertIn(
            f"fake-client  (device {credentials['device_id']}, Tailscale node loopback",
            devices,
        )
        status = subprocess.run(
            [SERVER, "--control-socket", self.control_socket, "status"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertEqual(
            status.splitlines()[:2], ["Client: none connected", "Dictation: idle"]
        )

    def pane_text(self) -> str:
        return subprocess.run(
            [
                "tmux",
                "-S",
                self.tmux_socket,
                "capture-pane",
                "-p",
                "-J",
                "-t",
                "remote:",
            ],
            capture_output=True,
            text=True,
            check=True,
        ).stdout

    # ── pairing ──

    def open_pairing(self) -> subprocess.Popen:
        """`voxize-remote pair`, waiting for its window to open."""
        cli = subprocess.Popen(
            [SERVER, "--control-socket", self.control_socket, "pair"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        first_line = cli.stdout.readline()
        self.assertIn("Pair with server", first_line, self.server_log())
        return cli

    def typist(self, cli: subprocess.Popen, typed=None):
        """on_code for fake_client.pair: types the client's code (or ``typed``) into `voxize-remote pair`."""

        def type_code(code: str) -> None:
            cli.stdin.write(f"{code if typed is None else typed}\n")
            cli.stdin.flush()

        return type_code

    def finish(self, cli: subprocess.Popen) -> str:
        """Ends `voxize-remote pair` if it is still waiting; everything it printed."""
        try:
            out, error = cli.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            cli.terminate()
            out, error = cli.communicate(timeout=10)
        return out + error

    def pair(
        self, typed=None, cancel: bool = False, device: str = "fake-client"
    ) -> tuple[dict | None, str, str]:
        """Pair a fake client; (credentials or None, what `voxize-remote pair` printed, the client's refusal)."""
        cli = self.open_pairing()
        try:
            credentials = asyncio.run(
                fake_client.pair(
                    "127.0.0.1",
                    self.port,
                    device=device,
                    on_code=self.typist(cli, typed),
                    cancel=cancel,
                )
            )
            refusal = ""
        except fake_client.ServerRefused as error:
            credentials, refusal = None, str(error)
        return credentials, self.finish(cli), refusal

    def paired_client(self) -> dict:
        credentials, server_said, refusal = self.pair()
        self.assertIsNotNone(
            credentials, f"{server_said}\n{refusal}\n{self.server_log()}"
        )
        return credentials

    def test_pairing_with_the_code_typed_on_the_server(self):
        shown = []
        cli = self.open_pairing()

        def type_code(code):
            shown.append(code)
            self.typist(cli)(code)

        credentials = asyncio.run(
            fake_client.pair("127.0.0.1", self.port, on_code=type_code)
        )
        out = self.finish(cli)
        self.assertEqual(cli.returncode, 0, out)
        self.assertIn("Paired fake-client", out)
        # The server never prints the code: it has to be read off the client.
        self.assertNotIn(shown[0], out)
        self.assertNotIn(shown[0].replace(" ", ""), out)
        # The secret is kept where only this user can read it, and is never listed.
        self.assertEqual(stat.S_IMODE(os.stat(self.pairing_file).st_mode), 0o600)
        devices = self.control("devices")["devices"]
        self.assertEqual(
            [device["device_id"] for device in devices], [credentials["device_id"]]
        )
        self.assertNotIn(credentials["secret"], json.dumps(devices))

    def test_pairing_needs_an_open_window(self):
        with self.assertRaises(fake_client.ServerRefused) as refusal:
            asyncio.run(fake_client.pair("127.0.0.1", self.port))
        self.assertIn("voxize-remote pair", str(refusal.exception))
        self.assertEqual(self.control("devices")["devices"], [])

    def test_a_wrong_code_does_not_pair(self):
        credentials, server_said, refusal = self.pair(typed="000 000")
        self.assertIsNone(credentials)
        self.assertIn("did not match", refusal)
        self.assertIn("did not match", server_said)
        self.assertEqual(self.control("devices")["devices"], [])

    def test_answering_yes_does_not_pair(self):
        # The old ceremony's answer, typed ahead or by habit, is not a code.
        credentials, _, _ = self.pair(typed="y")
        self.assertIsNone(credentials)
        self.assertEqual(self.control("devices")["devices"], [])

    def test_an_empty_answer_does_not_pair(self):
        credentials, _, _ = self.pair(typed="")
        self.assertIsNone(credentials)
        self.assertEqual(self.control("devices")["devices"], [])

    def test_the_client_can_cancel(self):
        credentials, server_said, _ = self.pair(cancel=True, typed="")
        self.assertIsNone(credentials)
        self.assertEqual(self.control("devices")["devices"], [])

    def test_the_revealed_nonce_must_match_the_commitment(self):
        cli = self.open_pairing()
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(
                fake_client.pair(
                    "127.0.0.1",
                    self.port,
                    on_code=self.typist(cli),
                    reveal=pairing.new_nonce(),
                )
            )
        self.finish(cli)
        self.assertIn("does not match its commitment", self.server_log())
        self.assertEqual(self.control("devices")["devices"], [])

    def test_a_failed_attempt_leaves_the_window_open(self):
        cli = self.open_pairing()
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(
                fake_client.pair(
                    "127.0.0.1",
                    self.port,
                    device="first",
                    on_code=self.typist(cli, "111 111"),
                )
            )
        credentials = asyncio.run(
            fake_client.pair(
                "127.0.0.1", self.port, device="second", on_code=self.typist(cli)
            )
        )
        out = self.finish(cli)
        self.assertIn("Paired second", out)
        self.assertEqual(
            [device["name"] for device in self.control("devices")["devices"]],
            ["second"],
        )
        self.assertTrue(credentials)

    def test_one_window_pairs_one_client(self):
        self.paired_client()
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(fake_client.pair("127.0.0.1", self.port, device="second"))
        self.assertEqual(len(self.control("devices")["devices"]), 1)

    def test_pairing_again_replaces_the_earlier_pairing(self):
        first = self.paired_client()
        second = self.paired_client()
        self.assertEqual(
            [device["device_id"] for device in self.control("devices")["devices"]],
            [second["device_id"]],
        )
        self.assertIn(
            f"replaced the earlier pairing {first['device_id']}", self.server_log()
        )
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(fake_client.handshake("127.0.0.1", self.port, first))

    def test_pairing_again_disconnects_the_earlier_pairing(self):
        first = self.paired_client()

        async def connected_then_replaced() -> bool:
            reader, writer, _ = await fake_client.handshake(
                "127.0.0.1", self.port, first
            )
            await asyncio.to_thread(self.paired_client)
            try:
                while True:
                    await asyncio.wait_for(frames.read(reader), 10)
            except asyncio.IncompleteReadError:
                return True
            finally:
                writer.close()

        self.assertTrue(asyncio.run(connected_then_replaced()), self.server_log())

    def test_the_window_closes_when_pair_goes_away(self):
        # Ctrl-C on `voxize-remote pair` (or `cc remote setup`) before any client asked: a rerun must not be "busy".
        cli = self.open_pairing()
        cli.terminate()
        self.finish(cli)
        deadline = time.monotonic() + 10
        while "pairing window closed" not in self.server_log():
            self.assertLess(time.monotonic(), deadline, self.server_log())
            time.sleep(0.05)
        self.paired_client()

    def test_names_from_the_network_cannot_drive_the_terminal(self):
        credentials, server_said, _ = self.pair(
            device="evil\x1b[8m\x1b[2Jhidden\r\nfake line"
        )
        self.assertIsNotNone(credentials)
        self.assertNotIn("\x1b", server_said)
        self.assertNotIn("\x1b", self.server_log())
        self.assertIn("evil[8m[2Jhiddenfake line", server_said)

    def test_unpair_forgets_the_client(self):
        credentials = self.paired_client()
        self.assertEqual(
            self.control("unpair", credentials["device_id"]), {"result": "unpaired"}
        )
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(fake_client.handshake("127.0.0.1", self.port, credentials))

    def test_unpair_drops_a_dictation_in_progress(self):
        credentials = self.paired_client()

        async def dictate_then_unpair() -> tuple[int, list[dict]]:
            reader, writer, _ = await fake_client.handshake(
                "127.0.0.1", self.port, credentials
            )
            dictation = asyncio.create_task(
                fake_client.dictate(
                    reader,
                    writer,
                    fake_client.tone(6),
                    seconds=5,
                    cancel=False,
                    timeout=20,
                )
            )
            await asyncio.sleep(2)
            await asyncio.to_thread(self.control, "unpair", credentials["device_id"])
            try:
                return await dictation
            except fake_client.ServerRefused:
                return -1, []

        asyncio.run(dictate_then_unpair())
        time.sleep(1)
        self.assertEqual(self.pane_text().strip(), "", self.server_log())
        self.assertIn("unpaired", self.server_log())
        self.assertNotIn("pasted", self.server_log())

    def test_lines_are_joined_where_enter_would_submit_them(self):
        # The pane runs cat, which never asks for bracketed paste: a newline there would be Enter.
        from voxize_remote.server import Tmux

        tmux = Tmux(self.tmux_socket, "remote")
        pane_id = tmux.run(
            "display-message", "-p", "-t", "remote:", "#{pane_id}"
        ).strip()
        tmux.paste(pane_id, "first line\nsecond line\n")
        deadline = time.monotonic() + 5
        while "second line" not in self.pane_text():
            self.assertLess(time.monotonic(), deadline, self.pane_text())
            time.sleep(0.05)
        time.sleep(0.3)
        self.assertEqual(self.pane_text().strip(), "first line second line")

    # ── proving the pairing ──

    def test_unpaired_client_is_refused(self):
        stranger = {"device_id": "0123456789abcdef", "secret": "00" * 32}
        with self.assertRaises(fake_client.ServerRefused) as refusal:
            asyncio.run(fake_client.handshake("127.0.0.1", self.port, stranger))
        self.assertIn("not paired", str(refusal.exception))
        self.assertIn("unknown device", self.server_log())

    def test_wrong_secret_is_refused(self):
        credentials = self.paired_client()
        forged = dict(credentials, secret="11" * 32)
        # The forger cannot check the server's proof either; it answers anyway and must be cut off.
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(
                fake_client.handshake(
                    "127.0.0.1", self.port, forged, check_server=False
                )
            )
        self.assertIn("wrong proof", self.server_log())
        self.assertEqual(self.control("status")["client"], None)

    def test_recorded_handshake_cannot_be_replayed(self):
        credentials = self.paired_client()
        secret = bytes.fromhex(credentials["secret"])

        async def record_then_replay() -> str:
            # A genuine exchange, as an eavesdropper would record it.
            reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
            client_nonce = pairing.new_nonce()
            hello = {
                "type": "hello",
                "protocol": 2,
                "device_id": credentials["device_id"],
                "nonce": client_nonce.hex(),
            }
            writer.write(frames.encode_json(hello))
            challenge = await fake_client.receive(reader)
            answer = {
                "type": "answer",
                "proof": pairing.client_proof(
                    secret, client_nonce, bytes.fromhex(challenge["nonce"])
                ),
            }
            writer.write(frames.encode_json(answer))
            await fake_client.receive(reader)
            writer.close()
            # The same hello and answer again: the server's new nonce makes the old answer worthless.
            reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
            writer.write(frames.encode_json(hello))
            await fake_client.receive(reader)
            writer.write(frames.encode_json(answer))
            try:
                return json.dumps(await fake_client.receive(reader))
            except fake_client.ServerRefused as refusal:
                return f"refused: {refusal}"

        self.assertTrue(asyncio.run(record_then_replay()).startswith("refused"))
        self.assertIn("wrong proof", self.server_log())

    def test_secret_works_only_from_the_paired_node(self):
        # A pairing made from another Tailscale node; this connection arrives on loopback.
        device = pairing.new_device("elsewhere", "nOTHERNODE", "other-client")
        pairing.FileStore(self.pairing_file).add(device)
        credentials = {"device_id": device.device_id, "secret": device.secret.hex()}
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(fake_client.handshake("127.0.0.1", self.port, credentials))
        self.assertIn("paired from other-client, not from here", self.server_log())

    def test_loopback_needs_debug_adb(self):
        credentials = self.paired_client()
        self.start_server(debug_adb=False)
        with self.assertRaises(fake_client.ServerRefused):
            asyncio.run(fake_client.handshake("127.0.0.1", self.port, credentials))
        self.assertIn("loopback connections need --debug-adb", self.server_log())

    def test_strangers_get_small_frames_and_no_audio(self):
        async def send_and_listen(frame: bytes) -> str:
            reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
            writer.write(frame)
            try:
                return json.dumps(await fake_client.receive(reader, timeout=15))
            except fake_client.ServerRefused as refusal:
                return f"refused: {refusal}"

        big = frames.encode(frames.JSON, b"{" + b" " * 8000 + b"}")
        self.assertTrue(asyncio.run(send_and_listen(big)).startswith("refused"))
        self.assertIn("exceeds 4096", self.server_log())
        audio = frames.encode(frames.AUDIO, b"\0" * 1920)
        self.assertTrue(asyncio.run(send_and_listen(audio)).startswith("refused"))

    def test_deeply_nested_json_is_refused_cleanly(self):
        async def send_nested() -> None:
            reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
            writer.write(frames.encode(frames.JSON, b"[" * 4000))
            with contextlib.suppress(fake_client.ServerRefused):
                await fake_client.receive(reader, timeout=10)

        asyncio.run(send_nested())
        # Within the 4 KiB cap Python's parser reports a decode error rather than a RecursionError; either way the
        # connection is refused with one log line, never a traceback.
        self.assertIn("not JSON", self.server_log())
        self.assertNotIn("Traceback", self.server_log())

    def test_the_server_cannot_start_a_dictation(self):
        completed = subprocess.run(
            [SERVER, "--control-socket", self.control_socket, "toggle"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("invalid choice", completed.stderr)
        # Nor through the socket directly, bypassing the command line.
        with socket.socket(socket.AF_UNIX) as raw:
            raw.connect(self.control_socket)
            raw.sendall(b"toggle\n")
            self.assertIn("unknown command", raw.recv(4096).decode())

    # ── dictation, once paired ──

    def dictate(self, *arguments: str) -> tuple[int, list[dict]]:
        credentials_file = os.path.join(self.directory, "credentials.json")
        if not os.path.exists(credentials_file):
            with open(credentials_file, "w", encoding="utf-8") as handle:
                json.dump(self.paired_client(), handle)
        completed = subprocess.run(
            [
                shutil.which("voxize-remote-python"),
                "-m",
                "voxize_remote.fake_client",
                "dictate",
                "--port",
                str(self.port),
                "--credentials",
                credentials_file,
                "--timeout",
                "30",
                *arguments,
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        messages = [json.loads(line) for line in completed.stdout.splitlines()]
        return completed.returncode, messages

    def test_dictation_lands_in_the_pane(self):
        code, messages = self.dictate("--seconds", "1.5")
        self.assertEqual(code, 0, f"{messages}\n{self.server_log()}")
        kinds = [message["type"] for message in messages]
        self.assertIn("capture", kinds)
        self.assertIn("halt", kinds)
        final = [message for message in messages if message["type"] == "status"][-1]
        self.assertEqual(final["phase"], "done", final)
        self.assertTrue(final["detail"].startswith("pasted into"), final)
        words = " ".join(final["text"].split())[:40]
        self.assertTrue(words)
        deadline = time.monotonic() + 5
        while words not in " ".join(self.pane_text().split()):
            self.assertLess(
                time.monotonic(),
                deadline,
                f"pane never showed {words!r}:\n{self.pane_text()}",
            )
            time.sleep(0.05)
        self.assertIn("audio done:", self.server_log())
        # A short dictation gives Voxize no estimate: the client is told to spin (progress null), never a number.
        working = [
            m
            for m in messages
            if m["type"] == "status" and m["phase"] in ("finishing", "processing")
        ]
        self.assertTrue(working, messages)
        self.assertTrue(all("progress" in m for m in working), working)

    def test_progress_reaches_the_client(self):
        # Long enough for 50 characters of live text, so Voxize predicts and reports a fraction.
        code, messages = self.dictate("--seconds", "5")
        self.assertEqual(code, 0, f"{messages}\n{self.server_log()}")
        fractions = [
            m["progress"]
            for m in messages
            if m["type"] == "status"
            and m["phase"] == "processing"
            and m.get("progress") is not None
        ]
        self.assertTrue(fractions, messages)
        self.assertEqual(fractions, sorted(fractions))
        self.assertGreaterEqual(fractions[-1], 0.9)

    def test_cancel_pastes_nothing(self):
        code, messages = self.dictate("--seconds", "1", "--cancel")
        self.assertEqual(code, 0, f"{messages}\n{self.server_log()}")
        self.assertEqual(self.pane_text().strip(), "")
        self.assertEqual(self.control("status")["phase"], "cancelled")
        self.assertIn("dictation ended: cancelled\n", self.server_log())

    def test_a_planted_module_in_the_pane_directory_does_not_run(self):
        # The pane sits in a cloned repository with a json.py of its own.
        hostile = os.path.join(self.directory, "cloned-repository")
        os.mkdir(hostile)
        marker = os.path.join(self.directory, "planted-code-ran")
        with open(os.path.join(hostile, "json.py"), "w", encoding="utf-8") as handle:
            handle.write(f"open({marker!r}, 'w').write('ran')\nraise SystemExit(1)\n")
        subprocess.run(["tmux", "-S", self.tmux_socket, "kill-server"], check=False)
        subprocess.run(
            [
                "tmux",
                "-S",
                self.tmux_socket,
                "-f",
                "/dev/null",
                "new-session",
                "-d",
                "-s",
                "remote",
                "-x",
                "200",
                "-y",
                "40",
                "-c",
                hostile,
                "cat",
            ],
            check=True,
        )
        code, messages = self.dictate("--seconds", "1.5")
        self.assertFalse(os.path.exists(marker), "the planted json.py ran")
        self.assertEqual(code, 0, f"{messages}\n{self.server_log()}")

    def test_no_attached_client_pastes_nowhere(self):
        # Without --any-pane a session nobody is attached to (the client on the hub's list) is refused.
        credentials = self.paired_client()
        with open(
            os.path.join(self.directory, "credentials.json"), "w", encoding="utf-8"
        ) as handle:
            json.dump(credentials, handle)
        self.start_server(any_pane=False)
        code, messages = self.dictate("--seconds", "1")
        final = [message for message in messages if message["type"] == "status"][-1]
        self.assertEqual(final["phase"], "error", messages)
        self.assertIn("open a session in Termux first", final["detail"])
        self.assertNotIn("capture", [message["type"] for message in messages])
        self.assertEqual(self.pane_text().strip(), "")

    def test_the_client_learns_whether_termux_has_a_session_open(self):
        credentials = self.paired_client()

        async def watch() -> list[bool]:
            reader, writer, status = await fake_client.handshake(
                "127.0.0.1", self.port, credentials
            )
            seen = [status["session"]]
            # A terminal attaching to the hub's tmux session, as Termux does when a session is opened from the hub.
            attached = subprocess.Popen(
                [
                    "script",
                    "-qfc",
                    f"tmux -S {self.tmux_socket} attach -t remote",
                    "/dev/null",
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline and seen[-1] is not True:
                    message = await fake_client.receive(reader, timeout=10)
                    if message["type"] == "status":
                        seen.append(message["session"])
            finally:
                attached.terminate()
                attached.wait(10)
            writer.close()
            return seen

        seen = asyncio.run(watch())
        self.assertEqual((seen[0], seen[-1]), (False, True), seen)

    def serve_beside(self, *listen_and_socket: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [
                SERVER,
                "--control-socket",
                *listen_and_socket[1:],
                "serve",
                "--mock",
                "--listen",
                listen_and_socket[0],
                "--tmux-socket",
                self.tmux_socket,
                "--pairing-file",
                self.pairing_file,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_a_second_server_leaves_the_first_ones_control_socket_alone(self):
        completed = self.serve_beside(f"127.0.0.1:{free_port()}", self.control_socket)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn(
            f"a server already answers on {self.control_socket}; stop it first: systemctl --user stop",
            completed.stderr,
        )
        self.assertNotIn("Traceback", completed.stderr)
        self.assertEqual(self.control("status")["phase"], "idle")

    def test_a_taken_port_is_a_sentence_not_a_traceback(self):
        completed = self.serve_beside(
            f"127.0.0.1:{self.port}", os.path.join(self.directory, "other.sock")
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn(
            f"cannot listen on 127.0.0.1:{self.port} (Address already in use)",
            completed.stderr,
        )
        self.assertNotIn("Traceback", completed.stderr)

    def test_a_dead_servers_control_socket_is_replaced(self):
        stale = os.path.join(self.directory, "stale.sock")
        left_behind = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        left_behind.bind(stale)
        left_behind.close()  # bound, never listening: what a killed server leaves
        server = subprocess.Popen(
            [
                SERVER,
                "--control-socket",
                stale,
                "serve",
                "--mock",
                "--listen",
                f"127.0.0.1:{free_port()}",
                "--tmux-socket",
                self.tmux_socket,
                "--pairing-file",
                self.pairing_file,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            from voxize_remote.server import control_answers

            deadline = time.monotonic() + 20
            while not control_answers(stale):
                if server.poll() is not None:
                    self.fail(f"the server exited: {server.stderr.read()}")
                self.assertLess(
                    time.monotonic(),
                    deadline,
                    "the server never took over the stale socket",
                )
                time.sleep(0.05)
        finally:
            server.terminate()
            server.wait(20)
            server.stderr.close()

    def test_status_without_client(self):
        status = self.control("status")
        self.assertEqual((status["phase"], status["client"]), ("idle", None))


class OnDemandTest(unittest.TestCase):
    """The server as the user service runs it: sockets from systemd, gone once idle."""

    def setUp(self):
        self.directory = tempfile.mkdtemp(prefix="voxize-remote-on-demand.")
        self.addCleanup(shutil.rmtree, self.directory, True)
        self.tmux_socket = os.path.join(self.directory, "tmux.sock")
        self.log_path = os.path.join(self.directory, "server.log")

    def test_idle_exit(self):
        started = time.monotonic()
        with open(self.log_path, "w") as log:
            completed = subprocess.run(
                [
                    SERVER,
                    "--control-socket",
                    os.path.join(self.directory, "control.sock"),
                    "serve",
                    "--mock",
                    "--listen",
                    f"127.0.0.1:{free_port()}",
                    "--tmux-socket",
                    self.tmux_socket,
                    "--pairing-file",
                    os.path.join(self.directory, "paired.json"),
                    "--idle-exit",
                    "2",
                ],
                stdout=subprocess.DEVNULL,
                stderr=log,
                timeout=30,
            )
        self.assertEqual(completed.returncode, 0)
        self.assertLess(time.monotonic() - started, 10)
        self.assertIn("no client for 2s; exiting", open(self.log_path).read())

    def test_sockets_from_systemd(self):
        activate = shutil.which("systemd-socket-activate")
        if activate is None:
            self.skipTest("systemd-socket-activate is not installed")
        port = free_port()
        control = os.path.join(self.directory, "control.sock")
        with open(self.log_path, "w") as log:
            server = subprocess.Popen(
                [
                    activate,
                    "-l",
                    f"127.0.0.1:{port}",
                    "-l",
                    control,
                    "--fdname=clients:control",
                    SERVER,
                    "serve",
                    "--systemd",
                    "--mock",
                    "--debug-adb",
                    "--tmux-socket",
                    self.tmux_socket,
                    "--pairing-file",
                    os.path.join(self.directory, "paired.json"),
                    "--idle-exit",
                    "3",
                ],
                stdout=subprocess.DEVNULL,
                stderr=log,
            )
        try:
            deadline = time.monotonic() + 10
            while not os.path.exists(control):
                self.assertLess(time.monotonic(), deadline, open(self.log_path).read())
                time.sleep(0.05)
            # The first connection starts the server; it answers on the socket systemd holds.
            completed = subprocess.run(
                [SERVER, "--control-socket", control, "status", "--json"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            self.assertEqual(
                json.loads(completed.stdout)["phase"], "idle", completed.stderr
            )
            self.assertIn("(from systemd)", open(self.log_path).read())
            # Nothing connected for 3 seconds: it exits by itself.
            server.wait(20)
            self.assertIn("exiting", open(self.log_path).read())
        finally:
            server.kill()


class InstalledEnvironmentTest(unittest.TestCase):
    """The service runs with the wrapper's environment and little else; the build's own PYTHONPATH hides gaps here."""

    def run_wrapped(self, code: str) -> subprocess.CompletedProcess:
        directory = tempfile.mkdtemp(prefix="voxize-remote-environment.")
        self.addCleanup(shutil.rmtree, directory, True)
        script = os.path.join(directory, "check.py")
        with open(script, "w", encoding="utf-8") as handle:
            handle.write(code)
        return subprocess.run(
            [shutil.which("voxize-remote-python"), script],
            env={"HOME": directory, "PATH": "/nonexistent"},
            capture_output=True,
            text=True,
            timeout=120,
        )

    def test_the_keyring_library_loads(self):
        completed = self.run_wrapped(
            "from voxize_remote.pairing import KeyringStore\nKeyringStore()\n"
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_a_backend_started_like_a_dictation_finds_its_modules(self):
        # Dictation.begin runs sys.executable -P -m voxize.backend --audio-fd FD from /, with the server's environment.
        completed = self.run_wrapped(
            "import os, subprocess, sys\n"
            "subprocess.run([sys.executable, '-P', '-c', 'import voxize.backend.session, voxize.audio'],\n"
            "               cwd='/', env=os.environ, check=True)\n"
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_ffmpeg_is_on_the_path(self):
        completed = self.run_wrapped(
            "import shutil, sys\nsys.exit(0 if shutil.which('ffmpeg') else 1)\n"
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)


class JournalTest(unittest.TestCase):
    """Under systemd the journal adds the time and the unit to every line; the server leaves them out then."""

    def test_stderr_is_recognised_as_the_journal(self):
        from unittest import mock

        from voxize_remote.server import stderr_is_the_journal

        status = os.fstat(sys.stderr.fileno())
        with mock.patch.dict(
            os.environ, {"JOURNAL_STREAM": f"{status.st_dev}:{status.st_ino}"}
        ):
            self.assertTrue(stderr_is_the_journal())
        # Inherited from a service by a program whose stderr went elsewhere (a terminal it opened, a file).
        with mock.patch.dict(
            os.environ, {"JOURNAL_STREAM": f"{status.st_dev}:{status.st_ino + 1}"}
        ):
            self.assertFalse(stderr_is_the_journal())
        with mock.patch.dict(os.environ, {"JOURNAL_STREAM": "garbage"}):
            self.assertFalse(stderr_is_the_journal())
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertFalse(stderr_is_the_journal())

    def test_journal_lines_drop_the_time_and_the_name(self):
        from unittest import mock

        from voxize_remote import server as server_module

        with mock.patch.object(
            server_module, "LOG_PREFIX", None
        ), contextlib.redirect_stderr(io.StringIO()) as out:
            server_module.log("client connected: phone")
        self.assertEqual(out.getvalue(), "client connected: phone\n")
        with mock.patch.object(
            server_module, "LOG_PREFIX", "voxize-remote: "
        ), contextlib.redirect_stderr(io.StringIO()) as out:
            server_module.log("client connected: phone")
        self.assertRegex(
            out.getvalue(), r"^\d\d:\d\d:\d\d voxize-remote: client connected: phone\n$"
        )


class IdentifyPeerTest(unittest.TestCase):
    """Tailscale's answers, faked: who gets past the address check."""

    SELF = {"Self": {"UserID": 7, "ID": "nSERVER"}}

    def identify(self, whois: dict, address: str = "100.64.0.9"):
        from voxize_remote import server as server_module

        def fake_tailscale_json(subcommand, *positional):
            if subcommand == "status":
                return self.SELF
            if isinstance(whois, Exception):
                raise whois
            return whois

        original = server_module.tailscale_json
        server_module.tailscale_json = fake_tailscale_json
        try:
            return server_module.identify_peer(address, allow_loopback=False)
        finally:
            server_module.tailscale_json = original

    def test_same_owner_other_node_passes(self):
        peer = self.identify(
            {
                "UserProfile": {"ID": 7, "LoginName": "stan"},
                "Node": {"StableID": "nCLIENT", "ComputedName": "client"},
            }
        )
        self.assertEqual((peer.node_id, peer.node_name), ("nCLIENT", "client"))

    def test_other_owner_is_refused(self):
        from voxize_remote.server import Refused

        with self.assertRaisesRegex(Refused, "not this machine's user"):
            self.identify(
                {
                    "UserProfile": {"ID": 8, "LoginName": "eve"},
                    "Node": {"StableID": "nEVE", "ComputedName": "eve"},
                }
            )

    def test_this_machine_is_refused(self):
        from voxize_remote.server import Refused

        with self.assertRaisesRegex(Refused, "is this machine"):
            self.identify(
                {
                    "UserProfile": {"ID": 7, "LoginName": "stan"},
                    "Node": {"StableID": "nSERVER", "ComputedName": "server"},
                }
            )

    def test_unidentifiable_is_refused(self):
        from voxize_remote.server import Refused

        with self.assertRaisesRegex(Refused, "could not identify"):
            self.identify(RuntimeError("no tailscaled"))

    def test_a_tagged_server_refuses_everyone(self):
        from voxize_remote.server import Refused

        self.SELF = {"Self": {"UserID": 7, "ID": "nSERVER", "Tags": ["tag:server"]}}
        with self.assertRaisesRegex(Refused, "tagged"):
            self.identify(
                {
                    "UserProfile": {"ID": 7, "LoginName": "tagged-devices"},
                    "Node": {"StableID": "nOTHER", "ComputedName": "other"},
                }
            )

    def test_ipv4_peers_of_a_dual_stack_listener_are_unmapped(self):
        # systemd's listener is dual-stack: an IPv4 client arrives as ::ffff:100.x.y.z.
        from voxize_remote import server as server_module

        asked = []

        def fake_tailscale_json(subcommand, *positional):
            if subcommand == "status":
                return self.SELF
            asked.extend(positional)
            return {
                "UserProfile": {"ID": 7, "LoginName": "stan"},
                "Node": {"StableID": "nCLIENT", "ComputedName": "c"},
            }

        original = server_module.tailscale_json
        server_module.tailscale_json = fake_tailscale_json
        try:
            self.assertEqual(
                server_module.identify_peer(
                    "::ffff:100.64.0.9", allow_loopback=False
                ).node_id,
                "nCLIENT",
            )
        finally:
            server_module.tailscale_json = original
        self.assertEqual(asked, ["100.64.0.9"])
        with self.assertRaisesRegex(server_module.Refused, "--debug-adb"):
            server_module.identify_peer("::ffff:127.0.0.1", allow_loopback=False)

    def test_loopback_needs_the_flag(self):
        from voxize_remote.server import Refused, identify_peer

        with self.assertRaisesRegex(Refused, "--debug-adb"):
            identify_peer("127.0.0.1", allow_loopback=False)
        self.assertEqual(
            identify_peer("127.0.0.1", allow_loopback=True).node_id,
            pairing.LOOPBACK_NODE,
        )


if __name__ == "__main__":
    unittest.main()
