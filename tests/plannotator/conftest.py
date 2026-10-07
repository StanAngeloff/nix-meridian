"""Fixtures for tests/plannotator, over harness.py; how to run the tests is in test_package.py's docstring."""

import os
import pathlib
import shutil
import subprocess
import tempfile

import pytest

from harness import (
    Beacon,
    WAYLAND_SOCKET_NAME,
    finish,
    launch,
    make_environment,
    wait_for,
)

MASKED_PATHS = ("/tmp", "/run")


@pytest.hookimpl(tryfirst=True)
def pytest_configure(config):
    # Inside the namespace /tmp is an empty tmpfs, so the files the tests hand Plannotator must live elsewhere.
    if config.option.basetemp is None:
        cache_path = pathlib.Path(
            os.environ.get("XDG_CACHE_HOME") or pathlib.Path.home() / ".cache"
        )
        config.option.basetemp = str(cache_path / "plannotator-tests")
    base_path = os.path.realpath(config.option.basetemp)
    if any(
        base_path == masked_path or base_path.startswith(masked_path + "/")
        for masked_path in MASKED_PATHS
    ):
        raise pytest.UsageError(
            f"--basetemp {base_path} is under a directory Plannotator's namespace masks"
        )


@pytest.fixture(scope="session")
def package_path():
    value = os.environ.get("PLANNOTATOR_PACKAGE")
    if not value:
        pytest.fail("PLANNOTATOR_PACKAGE must name a built plannotator package")
    return pathlib.Path(value)


@pytest.fixture(scope="session")
def wayland_runtime_path(tmp_path_factory):
    """A headless Weston that hosts every review window: windows are shown and work, on nobody's screen.

    Its runtime directory sits under XDG_RUNTIME_DIR, inside the /run that the namespace masks,
    so test_namespace.py can tell the one socket the namespace re-binds from a decoy beside it.
    """
    runtime_root = os.environ.get("XDG_RUNTIME_DIR", "")
    if not runtime_root.startswith("/run/"):
        pytest.fail(
            f"XDG_RUNTIME_DIR must name a directory under /run, not {runtime_root!r}"
        )
    runtime_path = pathlib.Path(
        tempfile.mkdtemp(prefix="plannotator-tests-", dir=runtime_root)
    )
    log_file = tmp_path_factory.mktemp("weston") / "weston.log"
    with log_file.open("w") as log:
        weston = subprocess.Popen(
            [
                "weston",
                "--backend=headless",
                f"--socket={WAYLAND_SOCKET_NAME}",
                "--no-config",
            ],
            env={**os.environ, "XDG_RUNTIME_DIR": str(runtime_path)},
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    try:
        wait_for(
            lambda: (runtime_path / WAYLAND_SOCKET_NAME).is_socket()
            or weston.poll() is not None,
            30,
            "Weston to start",
        )
        assert weston.poll() is None, f"Weston exited: {log_file.read_text()}"
        yield runtime_path
    finally:
        weston.terminate()
        weston.wait(timeout=30)
        shutil.rmtree(runtime_path, ignore_errors=True)


@pytest.fixture
def environment(tmp_path, wayland_runtime_path):
    return make_environment(tmp_path, wayland_runtime_path)


@pytest.fixture
def data_path(environment):
    return pathlib.Path(environment["PLANNOTATOR_DATA_DIR"])


@pytest.fixture
def start_session(package_path, tmp_path):
    """Starts sessions through harness.launch; whatever any of them leaves running is killed when the test ends."""
    sessions = []

    def start(arguments, environment, cwd, **options):
        session = launch(
            package_path,
            environment,
            tmp_path / f"session-{len(sessions)}",
            arguments,
            cwd,
            **options,
        )
        sessions.append(session)
        return session

    yield start
    for session in sessions:
        finish(session)


@pytest.fixture
def beacon():
    beacon = Beacon()
    yield beacon
    beacon.close()
