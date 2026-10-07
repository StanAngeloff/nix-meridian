"""Checks of what a process can reach. namespace_browser.py runs them inside Plannotator's namespace;
the tests run them again outside it, as the control that proves each check would catch a leak.
"""

import errno
import json
import os
import re
import socket
import stat
import subprocess
import urllib.request

RESOLVED_VARLINK_SOCKET = "/run/systemd/resolve/io.systemd.Resolve"
NIX_DAEMON_SOCKET = "/nix/var/nix/daemon-socket/socket"
PROBE_HOSTNAME = "example.com"


def outcome(check):
    """{"ok": true, "detail": …} when the check reached its target; {"ok": false, "detail": the error} when not."""
    try:
        return {"ok": True, "detail": check()}
    except Exception as error:
        return {"ok": False, "detail": f"{type(error).__name__}: {error}"}


def link_names():
    # /sys/class/net shows the parent's links inside a nested namespace; ip asks the kernel about this one.
    output = subprocess.run(
        ["ip", "-color=never", "-brief", "link"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return [line.split()[0].split("@")[0] for line in output.splitlines()]


def resolve_with_glibc():
    return sorted(
        {
            address[4][0]
            for address in socket.getaddrinfo(
                PROBE_HOSTNAME, 443, type=socket.SOCK_STREAM
            )
        }
    )


def resolve_with_varlink():
    """resolved's varlink API, the way nss-resolve reaches it: a pathname socket, which no network namespace stops."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(15)
        connection.connect(RESOLVED_VARLINK_SOCKET)
        request = {
            "method": "io.systemd.Resolve.ResolveHostname",
            "parameters": {"name": PROBE_HOSTNAME},
        }
        connection.sendall(json.dumps(request).encode() + b"\0")
        reply = b""
        while not reply.endswith(b"\0"):
            chunk = connection.recv(65536)
            if not chunk:
                raise ConnectionError("resolved closed the connection")
            reply += chunk
    answer = json.loads(reply[:-1])
    if "error" in answer:
        raise RuntimeError(answer["error"])
    return len(answer["parameters"]["addresses"])


def fetch_https():
    with urllib.request.urlopen(f"https://{PROBE_HOSTNAME}/", timeout=15) as response:
        return response.status


def connect_tcp(port):
    with socket.create_connection(("127.0.0.1", port), timeout=5):
        return port


def connect_unix(path):
    """Connects to a Unix socket of any type, trying stream, then seqpacket, then datagram: each refuses the others."""
    for socket_type in (socket.SOCK_STREAM, socket.SOCK_SEQPACKET, socket.SOCK_DGRAM):
        with socket.socket(socket.AF_UNIX, socket_type) as connection:
            connection.settimeout(5)
            try:
                connection.connect(path)
            except OSError as error:
                if error.errno == errno.EPROTOTYPE:
                    continue
                raise
            return path
    raise ConnectionError(f"{path} takes no stream, seqpacket or datagram connection")


def is_socket(path):
    try:
        return stat.S_ISSOCK(os.stat(path).st_mode)
    except OSError:
        return False


def listed_socket_paths():
    """Every socket isolate.sh looks for, as this process sees them: the network namespace's socket table,
    and file bind mounts, which always have a root other than /, from the mount table, with its octal escapes undone.
    """
    paths = set()
    with open("/proc/net/unix", errors="surrogateescape") as table:
        for line in table:
            fields = line.rstrip("\n").split(None, 7)
            if len(fields) == 8 and fields[7].startswith("/"):
                paths.add(fields[7])
    with open("/proc/self/mountinfo", errors="surrogateescape") as table:
        for line in table:
            fields = line.split(" ")
            if fields[3] != "/":
                paths.add(
                    re.sub(
                        r"\\([0-7]{3})",
                        lambda match: chr(int(match.group(1), 8)),
                        fields[4],
                    )
                )
    return sorted(path for path in paths if is_socket(path))


def answering_sockets(paths):
    """Those of the paths that accept a connection."""
    return [path for path in paths if outcome(lambda: connect_unix(path))["ok"]]


def socket_inventory(root_paths):
    """Every socket under the roots, found with lstat: bwrap binds a socket over a placeholder regular file,
    so the directory entry's type (what os.scandir and find -type s trust) says file while the path is a socket.
    """
    found = []
    for root_path in root_paths:
        for directory_path, directory_names, file_names in os.walk(
            root_path, onerror=lambda error: None
        ):
            for name in directory_names + file_names:
                entry_path = os.path.join(directory_path, name)
                try:
                    if stat.S_ISSOCK(os.lstat(entry_path).st_mode):
                        found.append(entry_path)
                except OSError:
                    pass
    return sorted(found)


def gpu_devices():
    """The entries under /dev/dri: the GPU's render nodes (renderD*) and card nodes (card*), which reach the display."""
    try:
        return sorted(os.path.join("/dev/dri", name) for name in os.listdir("/dev/dri"))
    except FileNotFoundError:
        return []


def server_listeners(process_id):
    """The TCP addresses the Plannotator server listens on, as ss sees them in the caller's network namespace."""
    output = subprocess.run(
        ["ss", "-ltnpH"], capture_output=True, text=True, check=True
    ).stdout
    return [
        line.split()[3] for line in output.splitlines() if f"pid={process_id}," in line
    ]


def run(configuration, server_process_id):
    checks = {
        "links": lambda: outcome(link_names),
        "glibc_dns": lambda: outcome(resolve_with_glibc),
        "varlink_dns": lambda: outcome(resolve_with_varlink),
        "https": lambda: outcome(fetch_https),
        "beacon": lambda: outcome(lambda: connect_tcp(configuration["beacon_port"])),
        "nix_daemon": lambda: outcome(lambda: connect_unix(NIX_DAEMON_SOCKET)),
        "wayland": lambda: outcome(
            lambda: connect_unix(configuration["wayland_socket_path"])
        ),
        "sockets": lambda: socket_inventory(configuration["inventory_roots"]),
        "answering_sockets": lambda: answering_sockets(
            configuration["candidate_sockets"]
        ),
        "decoy_exists": lambda: os.path.lexists(configuration["decoy_socket"]),
        "gpu_devices": gpu_devices,
        "graphics_drivers": lambda: os.path.isdir("/run/opengl-driver"),
        "listeners": lambda: server_listeners(server_process_id),
    }
    return {name: checks[name]() for name in configuration["checks"]}
