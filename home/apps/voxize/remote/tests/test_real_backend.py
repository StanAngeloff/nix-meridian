"""The real (not mock) Voxize session on client audio: every streamed byte reaches the session's audio.wav."""

import json
import math
import os
import shutil
import struct
import subprocess
import tempfile
import time
import unittest
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
TERMINAL_STATES = {"READY", "ERROR", "CANCELLED"}


class RealBackendTest(unittest.TestCase):
    def test_client_audio_reaches_the_wav(self):
        directory = tempfile.mkdtemp(prefix="voxize-remote-real.")
        self.addCleanup(shutil.rmtree, directory, True)
        # 1.5 s of a loud tone, so the WARMING detector flips to RECORDING on level, not on its timeout.
        pcm = b"".join(
            struct.pack("<h", int(12000 * math.sin(2 * math.pi * 330 * n / 24000)))
            for n in range(36000)
        )
        read_fd, write_fd = os.pipe()
        environment = dict(
            os.environ,
            XDG_STATE_HOME=os.path.join(directory, "state"),
            XDG_CONFIG_HOME=os.path.join(directory, "config"),
            XDG_RUNTIME_DIR=directory,
            OPENAI_BASE_URL="http://127.0.0.1:9/v1",
        )
        process = subprocess.Popen(
            [
                shutil.which("voxize-remote-python"),
                os.path.join(HERE, "offline_backend.py"),
                "--audio-fd",
                str(read_fd),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=open(os.path.join(directory, "stderr"), "w"),
            pass_fds=(read_fd,),
            env=environment,
            text=True,
        )
        os.close(read_fd)
        self.addCleanup(process.kill)

        events = []

        def next_event() -> dict:
            line = process.stdout.readline()
            self.assertTrue(
                line,
                f"backend exited; events {events}\n{open(os.path.join(directory, 'stderr')).read()[-3000:]}",
            )
            event = json.loads(line)
            events.append(event)
            return event

        def send(message: dict) -> None:
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()

        self.assertEqual(next_event()["type"], "hello")
        send({"type": "start", "cwd": directory, "glossaries": []})
        os.write(write_fd, pcm)
        os.close(write_fd)  # the server closes the pipe before it sends stop

        session_directory = None
        stop_sent = False
        deadline = time.monotonic() + 60
        while True:
            self.assertLess(time.monotonic(), deadline, events)
            event = next_event()
            if event["type"] == "session":
                session_directory = event["dir"]
            if event["type"] == "state":
                if event["state"] in ("WARMING", "RECORDING") and not stop_sent:
                    stop_sent = True
                    send({"type": "stop"})
                if event["state"] in TERMINAL_STATES:
                    break
        states = [event["state"] for event in events if event["type"] == "state"]
        self.assertIn("TRANSCRIBING", states, events)
        send({"type": "close", "trash_if_empty": False})
        process.wait(20)

        self.assertIsNotNone(session_directory, events)
        with wave.open(os.path.join(session_directory, "audio.wav"), "rb") as audio:
            self.assertEqual(
                (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()),
                (24000, 1, 2),
            )
            self.assertEqual(audio.readframes(audio.getnframes()), pcm)
        # Piped audio leaves this machine's microphone free: no lock was taken.
        self.assertFalse(os.path.exists(os.path.join(directory, "voxize-mic.lock")))
        print(
            f"\n  states {states}; failures {[e.get('message') for e in events if e['type'] == 'failure']}"
        )


if __name__ == "__main__":
    unittest.main()
