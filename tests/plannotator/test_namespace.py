"""The network namespace the plannotator wrapper enters, probed from inside by namespace_browser.py.

Each check runs again outside the namespace, in this process, as the control that proves it would catch a leak.
The controls need what the namespace takes away:
DNS through glibc and through resolved, https://example.com/, and the nix daemon.
"""

import pathlib
import socket
import subprocess
import tempfile

import pytest

import namespace_probe
from harness import (
    Beacon,
    WAYLAND_SOCKET_NAME,
    finish,
    launch,
    make_environment,
    wait_for,
)

INSIDE_CHECKS = [
    "links",
    "glibc_dns",
    "varlink_dns",
    "https",
    "beacon",
    "nix_daemon",
    "wayland",
    "sockets",
    "answering_sockets",
    "decoy_exists",
    "gpu_devices",
    "graphics_drivers",
]


@pytest.fixture(scope="module")
def namespace_beacon():
    beacon = Beacon()
    yield beacon
    beacon.close()


@pytest.fixture(scope="module")
def decoy_socket_file(wayland_runtime_path):
    """A socket beside Weston's: the namespace re-binds the display socket alone, not its directory."""
    decoy_file = wayland_runtime_path / "decoy"
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(decoy_file))
    listener.listen()
    yield decoy_file
    listener.close()
    decoy_file.unlink()


@pytest.fixture(scope="module")
def home_decoy_socket_file(tmp_path_factory):
    """A socket where a daemon in $HOME keeps one (the tests' files live under ~/.cache):
    outside every masked directory, so only isolate.sh's cover for each socket keeps it from answering.
    """
    decoy_file = tmp_path_factory.mktemp("home-decoy") / "daemon.sock"
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(decoy_file))
    listener.listen()
    yield decoy_file
    listener.close()
    decoy_file.unlink()


@pytest.fixture(scope="module")
def linked_decoy_socket_file(tmp_path_factory):
    """A socket bound through an absolute symbolic link, the path the socket table then lists:
    bwrap cannot mount over a path that leads through such a link, so isolate.sh covers the socket's real path.
    """
    decoy_path = tmp_path_factory.mktemp("linked-decoy")
    (decoy_path / "real").mkdir()
    (decoy_path / "link").symlink_to(decoy_path / "real")
    decoy_file = decoy_path / "link" / "daemon.sock"
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(decoy_file))
    listener.listen()
    yield decoy_file
    listener.close()
    decoy_file.unlink()


@pytest.fixture(scope="module")
def inside(
    package_path,
    wayland_runtime_path,
    tmp_path_factory,
    namespace_beacon,
    decoy_socket_file,
    home_decoy_socket_file,
    linked_decoy_socket_file,
):
    """What namespace_probe.run sees from inside one session's namespace."""
    work_path = tmp_path_factory.mktemp("namespace")
    environment = make_environment(work_path, wayland_runtime_path)
    (work_path / "probe.md").write_text("# Probe\n")
    session = launch(
        package_path,
        environment,
        work_path / "session",
        ["annotate", "probe.md"],
        work_path,
        probe={
            "checks": INSIDE_CHECKS,
            "beacon_port": namespace_beacon.port,
            "wayland_socket_path": str(wayland_runtime_path / WAYLAND_SOCKET_NAME),
            "decoy_socket": str(decoy_socket_file),
            "inventory_roots": ["/run", "/tmp", "/nix/var"],
            # Listed now, while every decoy listens, so the namespace starts with them in the table.
            "candidate_sockets": sorted(
                set(namespace_probe.listed_socket_paths())
                | {
                    str(wayland_runtime_path / WAYLAND_SOCKET_NAME),
                    str(decoy_socket_file),
                    str(home_decoy_socket_file),
                    str(linked_decoy_socket_file),
                }
            ),
        },
    )
    try:
        result = session.probe_result()
        status, _ = session.request_json("/api/exit", "POST", {})
        assert status == 200
        session.process.communicate(timeout=60)
        session.wait_until_nothing_remains()
    finally:
        finish(session)
    return result


def test_the_only_link_is_loopback(inside):
    assert inside["links"] == {"ok": True, "detail": ["lo"]}
    control = namespace_probe.outcome(namespace_probe.link_names)
    assert control["ok"] and set(control["detail"]) - {"lo"}, f"control: {control}"


def test_names_do_not_resolve_through_glibc(inside):
    assert not inside["glibc_dns"]["ok"], inside["glibc_dns"]
    control = namespace_probe.outcome(namespace_probe.resolve_with_glibc)
    assert control["ok"], f"control: {control}"


def test_names_do_not_resolve_through_resolveds_varlink_socket(inside):
    # A pathname socket under /run: a network namespace alone leaves it reachable.
    assert not inside["varlink_dns"]["ok"], inside["varlink_dns"]
    control = namespace_probe.outcome(namespace_probe.resolve_with_varlink)
    assert control["ok"], f"control: {control}"


def test_https_fails_and_the_tests_loopback_is_out_of_reach(inside, namespace_beacon):
    assert not inside["https"]["ok"], inside["https"]
    assert not inside["beacon"]["ok"], inside["beacon"]
    assert namespace_beacon.connection_count == 0
    control = namespace_probe.outcome(namespace_probe.fetch_https)
    assert control["ok"], f"control: {control}"
    control = namespace_probe.outcome(
        lambda: namespace_probe.connect_tcp(namespace_beacon.port)
    )
    assert control["ok"], f"control: {control}"
    wait_for(
        lambda: namespace_beacon.connection_count == 1,
        10,
        "the control's connection to reach the beacon",
    )


def test_the_nix_daemon_is_out_of_reach(inside):
    # The daemon downloads whatever it is asked to, so its socket would be a way out.
    assert not inside["nix_daemon"]["ok"], inside["nix_daemon"]
    control = namespace_probe.outcome(
        lambda: namespace_probe.connect_unix(namespace_probe.NIX_DAEMON_SOCKET)
    )
    assert control["ok"], f"control: {control}"


def test_the_display_socket_is_the_only_socket_that_crosses(
    inside, wayland_runtime_path, decoy_socket_file
):
    wayland_socket_path = str(wayland_runtime_path / WAYLAND_SOCKET_NAME)
    assert inside["sockets"] == [wayland_socket_path]
    assert inside["wayland"]["ok"], inside["wayland"]
    assert inside["decoy_exists"] is False
    # Control: outside, the same inventory finds both sockets, the decoy among them.
    assert namespace_probe.socket_inventory([str(wayland_runtime_path)]) == sorted(
        [wayland_socket_path, str(decoy_socket_file)]
    )


def test_no_socket_answers_but_the_display(
    inside,
    wayland_runtime_path,
    decoy_socket_file,
    home_decoy_socket_file,
    linked_decoy_socket_file,
):
    # Every socket bound or bind-mounted where this process can see it:
    # outside the bubble, the host's whole socket table, $HOME's daemons included;
    # inside it, what the bubble lets through, such as its gpg agent mount.
    assert inside["answering_sockets"] == [
        str(wayland_runtime_path / WAYLAND_SOCKET_NAME)
    ]
    # Control: outside, every decoy answers:
    # the one under /run, the one beside the tests' files in $HOME and the one behind a link.
    decoys = sorted(
        [
            str(decoy_socket_file),
            str(home_decoy_socket_file),
            str(linked_decoy_socket_file),
        ]
    )
    assert namespace_probe.answering_sockets(decoys) == decoys


def test_the_gpus_render_nodes_cross_and_its_card_nodes_do_not(inside):
    # The review window draws on the GPU through its render nodes and NixOS's graphics drivers under the masked /run.
    # The card nodes reach the display; only outside the bubble does the control below find any of them.
    outside = namespace_probe.gpu_devices()
    render_node_paths = [
        device_path
        for device_path in outside
        if pathlib.Path(device_path).name.startswith("renderD")
    ]
    assert inside["gpu_devices"] == render_node_paths
    assert inside["graphics_drivers"] == pathlib.Path("/run/opengl-driver").is_dir()


def test_a_working_directory_the_namespace_hides_fails_loudly(
    package_path, tmp_path_factory, wayland_runtime_path
):
    # /tmp is masked: without --chdir, bwrap would quietly run Plannotator in $HOME instead.
    environment = make_environment(
        tmp_path_factory.mktemp("hidden-working-directory"), wayland_runtime_path
    )
    hidden_path = pathlib.Path(
        tempfile.mkdtemp(prefix="plannotator-tests-", dir="/tmp")
    )
    try:
        result = subprocess.run(
            [str(package_path / "bin" / "plannotator"), "--version"],
            env=environment,
            cwd=hidden_path,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    finally:
        hidden_path.rmdir()
    assert result.returncode != 0, result.stdout
    assert "chdir" in result.stderr, result.stderr
