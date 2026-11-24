"""Voxize's backend with OpenAI unreachable: a fake key, and every endpoint on a closed local port.

For test_real_backend.py only, with its arguments (``--audio-fd FD``). The real Session runs (bootstrap, PipeAudioCapture,
the WARMING detector, stop, batch); the provider calls fail on connect, so nothing leaves this machine.
"""

import runpy
import sys

import voxize.checks
import voxize.transcribe

voxize.checks.check_all = lambda: []
voxize.checks.get_api_key = lambda service: "sk-offline-test"
voxize.transcribe._WS_URL = "ws://127.0.0.1:9/v1/realtime?intent=transcription"

sys.argv = ["voxize.backend", *sys.argv[1:]]
runpy.run_module("voxize.backend", run_name="__main__", alter_sys=True)
