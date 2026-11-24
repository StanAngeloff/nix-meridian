"""The client link's framing: a kind byte, a big-endian 32-bit length, then the payload.

Kind ``J`` carries one JSON object (UTF-8); kind ``A`` carries raw PCM, signed 16-bit little-endian, mono, 24 kHz, the
format Voxize records in. The Android app (VoxService.java) writes and reads the same frames.
"""

import asyncio
import json
import struct

JSON = b"J"
AUDIO = b"A"
HEADER = struct.Struct(">cI")
MAXIMUM_PAYLOAD_LENGTH = 1 << 20


class FrameError(ValueError):
    """A frame that does not fit the format."""


def encode(kind: bytes, payload: bytes) -> bytes:
    return HEADER.pack(kind, len(payload)) + payload


def encode_json(message: dict) -> bytes:
    return encode(
        JSON, json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode()
    )


async def read(
    reader: asyncio.StreamReader, maximum_length: int = MAXIMUM_PAYLOAD_LENGTH
) -> tuple[bytes, bytes]:
    """The next frame as (kind, payload); asyncio.IncompleteReadError at end of stream.

    Before a peer has proved itself the server passes a small ``maximum_length``, so a stranger cannot make it allocate
    a megabyte per frame.
    """
    header = await reader.readexactly(HEADER.size)
    kind, length = HEADER.unpack(header)
    if kind not in (JSON, AUDIO):
        raise FrameError(f"unknown frame kind {kind!r}")
    if length > maximum_length:
        raise FrameError(f"frame of {length} bytes exceeds {maximum_length}")
    return kind, await reader.readexactly(length)


def decode_json(payload: bytes) -> dict:
    try:
        message = json.loads(payload)
    except (ValueError, RecursionError) as error:
        # RecursionError: deeply nested brackets, which a stranger can send within the 4 KiB first frame.
        raise FrameError(f"not JSON: {type(error).__name__}") from None
    if not isinstance(message, dict) or not isinstance(message.get("type"), str):
        raise FrameError("expected an object with a string 'type'")
    return message
