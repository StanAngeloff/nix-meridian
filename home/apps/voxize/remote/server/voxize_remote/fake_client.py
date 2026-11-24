"""A stand-in for the Android app, for tests: ``python -m voxize_remote.fake_client``.

    fake_client pair --credentials FILE         pair through an open pairing window (prints the code to type on
                                                the server), keep the secret in FILE
    fake_client dictate --credentials FILE ...   prove the pairing, tap, stream a WAV (24 kHz mono 16-bit) or a tone in
                                                real time, tap again after --seconds, print every message until the
                                                dictation ends; exit 0 when the server reports done

The steps are also functions (pair, handshake, dictate), so tests can break one on purpose.
"""

import argparse
import asyncio
import json
import math
import struct
import sys
import wave

from voxize_remote import frames, pairing

PROTOCOL_VERSION = 2
RATE = 24000
FRAME_SAMPLES = 960


class ServerRefused(Exception):
    """The server sent an error or closed the connection."""


class ServerImpostor(Exception):
    """The server's proof did not match the secret."""


def tone(seconds: float) -> bytes:
    samples = int(RATE * seconds)
    return b"".join(
        struct.pack("<h", int(8000 * math.sin(2 * math.pi * 220 * n / RATE)))
        for n in range(samples)
    )


def read_wav(path: str) -> bytes:
    with wave.open(path, "rb") as audio:
        if (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) != (
            RATE,
            1,
            2,
        ):
            sys.exit(f"{path}: need 24 kHz mono 16-bit")
        return audio.readframes(audio.getnframes())


async def receive(reader: asyncio.StreamReader, timeout: float = 30.0) -> dict:
    try:
        kind, payload = await asyncio.wait_for(frames.read(reader), timeout)
    except (asyncio.IncompleteReadError, ConnectionResetError):
        raise ServerRefused("connection closed") from None
    message = frames.decode_json(payload)
    if message.get("type") == "error":
        raise ServerRefused(message.get("message"))
    return message


async def pair(
    host: str,
    port: int,
    device: str = "fake-client",
    on_code=None,
    cancel: bool = False,
    reveal: bytes | None = None,
) -> dict:
    """Pair through the server's open window; the credentials, or ServerRefused.

    ``on_code(code)`` is called with the code the client would show (the tests type it into `voxize-remote pair`);
    ``cancel`` gives up after seeing it; ``reveal`` reveals a nonce other than the committed one (a test of the check).
    """
    reader, writer = await asyncio.open_connection(host, port)
    try:
        pairing_nonce = pairing.new_nonce()
        writer.write(
            frames.encode_json(
                {
                    "type": "pair",
                    "protocol": PROTOCOL_VERSION,
                    "device": device,
                    "commitment": pairing.commitment(pairing_nonce),
                }
            )
        )
        offer = await receive(reader)
        if offer.get("type") != "pairing":
            raise ServerRefused(f"expected pairing, got {offer}")
        secret = bytes.fromhex(offer["secret"])
        writer.write(
            frames.encode_json(
                {"type": "reveal", "nonce": (reveal or pairing_nonce).hex()}
            )
        )
        await writer.drain()
        code = pairing.confirmation_code(secret, pairing_nonce)
        if on_code is not None:
            await asyncio.to_thread(on_code, code)
        else:
            print(json.dumps({"code": code, "server": offer.get("server")}), flush=True)
        if cancel:
            writer.write(frames.encode_json({"type": "pair_rejected"}))
            await writer.drain()
            raise ServerRefused("cancelled on the client")
        result = await receive(reader, timeout=150)
        if result.get("type") != "paired":
            raise ServerRefused(f"expected paired, got {result}")
        return {
            "device_id": offer["device_id"],
            "secret": offer["secret"],
            "device": device,
        }
    finally:
        writer.close()


async def handshake(
    host: str, port: int, credentials: dict, check_server: bool = True
) -> tuple[asyncio.StreamReader, asyncio.StreamWriter, dict]:
    """Connect and prove the pairing both ways; (reader, writer, the server's first status)."""
    secret = bytes.fromhex(credentials["secret"])
    reader, writer = await asyncio.open_connection(host, port)
    client_nonce = pairing.new_nonce()
    writer.write(
        frames.encode_json(
            {
                "type": "hello",
                "protocol": PROTOCOL_VERSION,
                "device": credentials.get("device", "fake-client"),
                "device_id": credentials["device_id"],
                "nonce": client_nonce.hex(),
            }
        )
    )
    challenge = await receive(reader)
    server_nonce = pairing.decode_nonce(challenge.get("nonce"))
    if challenge.get("type") != "challenge" or server_nonce is None:
        raise ServerRefused(f"expected challenge, got {challenge}")
    if check_server and not pairing.proofs_match(
        pairing.server_proof(secret, client_nonce, server_nonce), challenge.get("proof")
    ):
        writer.close()
        raise ServerImpostor("the server could not prove it holds the secret")
    writer.write(
        frames.encode_json(
            {
                "type": "answer",
                "proof": pairing.client_proof(secret, client_nonce, server_nonce),
            }
        )
    )
    status = await receive(reader)
    return reader, writer, status


async def dictate(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    pcm: bytes,
    seconds: float,
    cancel: bool,
    timeout: float = 60.0,
) -> tuple[int, list[dict]]:
    """Tap, stream, tap again (or cancel); every message received, and 0 if it ended as expected."""
    messages: list[dict] = []
    streaming: asyncio.Task | None = None
    halted = asyncio.Event()
    started = False
    writer.write(frames.encode_json({"type": "toggle"}))

    async def stream() -> None:
        writer.write(
            frames.encode_json({"type": "capturing", "rate": RATE, "source": "fake"})
        )
        step = FRAME_SAMPLES * 2
        for offset in range(0, len(pcm), step):
            if halted.is_set():
                break
            writer.write(frames.encode(frames.AUDIO, pcm[offset : offset + step]))
            await writer.drain()
            await asyncio.sleep(
                FRAME_SAMPLES / RATE
            )  # real-time pacing, as a microphone delivers
        await halted.wait()
        writer.write(frames.encode_json({"type": "captured"}))
        await writer.drain()

    async def tap_again() -> None:
        await asyncio.sleep(seconds)
        writer.write(frames.encode_json({"type": "cancel" if cancel else "toggle"}))
        await writer.drain()

    tapper = asyncio.create_task(tap_again())
    try:
        while True:
            message = await receive(reader, timeout)
            messages.append(message)
            if message["type"] == "capture":
                streaming = asyncio.create_task(stream())
            elif message["type"] == "halt":
                halted.set()
            elif message["type"] == "status":
                if message["phase"] != "idle":
                    started = True
                if message["phase"] == "error":
                    return 1, messages
                if started and message["phase"] in ("done", "cancelled"):
                    return (
                        0
                        if message["phase"] == ("cancelled" if cancel else "done")
                        else 1
                    ), messages
    finally:
        tapper.cancel()
        if streaming is not None:
            streaming.cancel()
        writer.close()


async def run(arguments: argparse.Namespace) -> int:
    if arguments.command == "pair":
        credentials = await pair(
            arguments.host, arguments.port, cancel=arguments.cancel_pairing
        )
        with open(arguments.credentials, "w", encoding="utf-8") as handle:
            json.dump(credentials, handle)
        return 0
    with open(arguments.credentials, encoding="utf-8") as handle:
        credentials = json.load(handle)
    pcm = read_wav(arguments.wav) if arguments.wav else tone(arguments.seconds)
    reader, writer, status = await handshake(
        arguments.host, arguments.port, credentials
    )
    print(json.dumps(status, ensure_ascii=False), flush=True)
    code, messages = await dictate(
        reader, writer, pcm, arguments.seconds, arguments.cancel, arguments.timeout
    )
    for message in messages:
        print(json.dumps(message, ensure_ascii=False), flush=True)
    return code


def main() -> None:
    parser = argparse.ArgumentParser(prog="fake_client")
    parser.add_argument("command", choices=("pair", "dictate"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--credentials", required=True)
    parser.add_argument(
        "--cancel-pairing",
        action="store_true",
        help="pair: give up after showing the code",
    )
    parser.add_argument("--wav")
    parser.add_argument(
        "--seconds", type=float, default=2.0, help="tap again after this long"
    )
    parser.add_argument("--cancel", action="store_true", help="the second tap cancels")
    parser.add_argument("--timeout", type=float, default=60.0)
    try:
        sys.exit(asyncio.run(run(parser.parse_args())))
    except (ServerRefused, ServerImpostor) as error:
        sys.exit(f"fake_client: {error}")


if __name__ == "__main__":
    main()
