"""Pairing: one secret per client, and the proofs both ends give on every connection.

A client pairs once, while ``voxize-remote pair`` holds a pairing window open on the server:

    client → server   pair       {device, commitment: SHA-256(pairing nonce)}
    server → client   pairing    {device_id, secret, server}
    client → server   reveal     {nonce: the pairing nonce}

Both ends then know the six-digit code HMAC(secret, "voxize-remote confirm", pairing nonce). The client shows it, and
Stan types it on the server; the server keeps the pairing (with the client's Tailscale node) only if the typed code
matches, then sends ``paired``. Typing the code, instead of answering yes, means he has looked at the client. The
commitment fixes the client's nonce before it sees the secret and the secret before the server sees the nonce, so no
one relaying the exchange can search for a secret whose code matches.

Every later connection opens with a challenge in both directions (Link.java does the client's half):

    client → server   hello      {device_id, nonce: client nonce}
    server → client   challenge  {nonce: server nonce, proof: HMAC(secret, "voxize-remote server", nonces)}
    client → server   answer     {proof: HMAC(secret, "voxize-remote client", nonces)}

The server proves itself first, so a client never obeys an impostor; each side's proof carries its own label, so one
cannot be reflected as the other; fresh nonces from both ends make a recorded exchange useless.

Secrets live in the GNOME keyring (one item per client), or in a 0600 JSON file for tests.
"""

from __future__ import annotations

import contextlib
import dataclasses
import hashlib
import hmac
import json
import os
import secrets
import time

NONCE_BYTES = 32
SECRET_BYTES = 32
_SERVER_LABEL = b"voxize-remote server"
_CLIENT_LABEL = b"voxize-remote client"
_CONFIRM_LABEL = b"voxize-remote confirm"
# A client paired over adb's loopback tunnel has no Tailscale node; the server accepts it only with --debug-adb.
LOOPBACK_NODE = "loopback"


@dataclasses.dataclass(frozen=True)
class Device:
    device_id: str
    secret: bytes
    name: str
    node_id: str
    node_name: str
    paired_at: str

    def summary(self) -> dict:
        return {
            "device_id": self.device_id,
            "name": self.name,
            "node": self.node_name,
            "node_id": self.node_id,
            "paired_at": self.paired_at,
        }


def new_device(name: str, node_id: str, node_name: str) -> Device:
    return Device(
        device_id=secrets.token_hex(8),
        secret=secrets.token_bytes(SECRET_BYTES),
        name=name,
        node_id=node_id,
        node_name=node_name,
        paired_at=time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    )


def new_nonce() -> bytes:
    return secrets.token_bytes(NONCE_BYTES)


def _mac(secret: bytes, label: bytes, client_nonce: bytes, server_nonce: bytes) -> str:
    return hmac.new(
        secret, label + b"\0" + client_nonce + server_nonce, hashlib.sha256
    ).hexdigest()


def server_proof(secret: bytes, client_nonce: bytes, server_nonce: bytes) -> str:
    return _mac(secret, _SERVER_LABEL, client_nonce, server_nonce)


def client_proof(secret: bytes, client_nonce: bytes, server_nonce: bytes) -> str:
    return _mac(secret, _CLIENT_LABEL, client_nonce, server_nonce)


def proofs_match(expected: str, received: object) -> bool:
    return isinstance(received, str) and hmac.compare_digest(
        expected.encode(), received.encode()
    )


def commitment(pairing_nonce: bytes) -> str:
    return hashlib.sha256(pairing_nonce).hexdigest()


def confirmation_code(secret: bytes, pairing_nonce: bytes) -> str:
    """The six digits the client shows and Stan types on the server: "123 456"."""
    digest = hmac.new(
        secret, _CONFIRM_LABEL + b"\0" + pairing_nonce, hashlib.sha256
    ).digest()
    number = int.from_bytes(digest[:4], "big") % 1_000_000
    return f"{number // 1000:03d} {number % 1000:03d}"


def codes_match(expected: str, typed: object) -> bool:
    """The typed code against the expected one, ignoring spaces; constant time."""
    if not isinstance(typed, str):
        return False
    digits = "".join(character for character in typed if not character.isspace())
    return hmac.compare_digest(expected.replace(" ", "").encode(), digits.encode())


def printable(text: object, limit: int = 80) -> str:
    """A name from the network, safe to print in a terminal or a log: no control or escape characters."""
    return (
        "".join(character for character in str(text) if character.isprintable())[:limit]
        or "?"
    )


def decode_nonce(value: object) -> bytes | None:
    if not isinstance(value, str) or len(value) != 2 * NONCE_BYTES:
        return None
    try:
        return bytes.fromhex(value)
    except ValueError:
        return None


# ── where the secrets live ──


def _to_record(device: Device) -> dict:
    return {**device.summary(), "secret": device.secret.hex()}


def _from_record(record: dict) -> Device:
    return Device(
        device_id=record["device_id"],
        secret=bytes.fromhex(record["secret"]),
        name=record.get("name", ""),
        node_id=record["node_id"],
        node_name=record.get("node_name") or record.get("node", ""),
        paired_at=record.get("paired_at", ""),
    )


class FileStore:
    """A 0600 JSON file of paired clients (tests; the server uses the keyring unless told otherwise)."""

    def __init__(self, path: str) -> None:
        self.path = path

    def load(self) -> dict[str, Device]:
        try:
            with open(self.path, encoding="utf-8") as handle:
                records = json.load(handle)
        except FileNotFoundError:
            return {}
        return {record["device_id"]: _from_record(record) for record in records}

    def _write(self, devices: dict[str, Device]) -> None:
        temporary_path = f"{self.path}.{os.getpid()}.tmp"
        descriptor = os.open(
            temporary_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(
                [_to_record(device) for device in devices.values()], handle, indent=2
            )
        os.replace(temporary_path, self.path)

    def add(self, device: Device) -> None:
        devices = self.load()
        devices[device.device_id] = device
        self._write(devices)

    def remove(self, device_id: str) -> bool:
        devices = self.load()
        if devices.pop(device_id, None) is None:
            return False
        self._write(devices)
        return True


class KeyringStore:
    """One GNOME keyring item per paired client, keyed by its device id."""

    def __init__(self) -> None:
        import gi

        gi.require_version("Secret", "1")
        from gi.repository import Secret

        self._secret = Secret
        self._schema = Secret.Schema.new(
            "dev.flemma.voxize.remote.Device",
            Secret.SchemaFlags.NONE,
            {"device": Secret.SchemaAttributeType.STRING},
        )

    def load(self) -> dict[str, Device]:
        flags = (
            self._secret.SearchFlags.ALL
            | self._secret.SearchFlags.UNLOCK
            | self._secret.SearchFlags.LOAD_SECRETS
        )
        items = self._secret.password_search_sync(self._schema, {}, flags, None) or []
        devices = {}
        for item in items:
            value = item.get_secret()
            if value is None:
                continue
            with contextlib.suppress(ValueError, KeyError):
                device = _from_record(json.loads(value.get_text()))
                devices[device.device_id] = device
        return devices

    def add(self, device: Device) -> None:
        stored = self._secret.password_store_sync(
            self._schema,
            {"device": device.device_id},
            self._secret.COLLECTION_DEFAULT,
            f"Voxize Remote: {device.name} ({device.node_name})",
            json.dumps(_to_record(device)),
            None,
        )
        if not stored:
            raise RuntimeError("the keyring did not store the pairing")

    def remove(self, device_id: str) -> bool:
        return bool(
            self._secret.password_clear_sync(self._schema, {"device": device_id}, None)
        )
