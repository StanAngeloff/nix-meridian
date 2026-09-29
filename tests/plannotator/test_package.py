r"""Behavior tests for pkgs/plannotator: the wrapper's pinned settings and read-only runtime directory, against the real binary.

PLANNOTATOR_PACKAGE names a package built with installSkills = true. Every test gets its own HOME and data directory
under tmp_path, and a recording browser command, so nothing touches ~/.claude/plannotator or opens a real browser.
pkgs/plannotator/update.sh runs these after every bump. To run them by hand, from the repository root:

    export PLANNOTATOR_PACKAGE="$(nix build --no-link --print-out-paths --impure --expr \
      "(builtins.getFlake \"path:$PWD\").nixosConfigurations.stan-latitude.pkgs.plannotator.override { installSkills = true; }")"
    nix shell --inputs-from "path:$PWD" nixpkgs#python3Packages.pytest nixpkgs#nodejs nixpkgs#git nixpkgs#iproute2 \
      --command pytest -p no:cacheprovider tests/plannotator

Node is on PATH so the runtime installs get past their Node preflight to the point where they would write into vendor/.
"""

import json
import os
import pathlib
import re
import signal
import subprocess
import time
import urllib.error
import urllib.request

import pytest

PLANNOTATOR_VERSION = "0.27.22"
SEM_VERSION = "0.8.0"
SKILL_NAMES = ["plannotator-annotate", "plannotator-last", "plannotator-review"]
ADVERTISED_URL_PATTERN = re.compile(r"http://localhost:(\d+)/?")
ORIGINAL_SOURCE = (
    "export function greet(name: string): string {\n  return `Hello, ${name}`;\n}\n"
)
CHANGED_SOURCE = (
    "export function greet(name: string): string {\n  return `Hello there, ${name}!`;\n}\n\n"
    "export function part(name: string): string {\n  return `Goodbye, ${name}`;\n}\n"
)


@pytest.fixture(scope="session")
def package_path():
    value = os.environ.get("PLANNOTATOR_PACKAGE")
    if not value:
        pytest.fail("PLANNOTATOR_PACKAGE must name a built plannotator package")
    return pathlib.Path(value)


@pytest.fixture
def browser_file(tmp_path):
    return tmp_path / "browser-calls"


@pytest.fixture
def data_path(tmp_path):
    path = tmp_path / "data"
    path.mkdir()
    return path


@pytest.fixture
def environment(tmp_path, browser_file, data_path):
    """Built from scratch so nothing from the test runner's PLANNOTATOR_* or SSH_* variables leaks in."""
    home_path = tmp_path / "home"
    home_path.mkdir()
    browser_path = tmp_path / "browser"
    browser_path.write_text(
        f"#!/bin/sh\nprintf '%s\\t%s\\n' \"$#\" \"$1\" >> '{browser_file}'\n"
    )
    browser_path.chmod(0o755)
    return {
        "PATH": os.environ["PATH"],
        "HOME": str(home_path),
        "LANG": "C.UTF-8",
        "PLANNOTATOR_DATA_DIR": str(data_path),
        "PLANNOTATOR_BROWSER": str(browser_path),
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Probe",
        "GIT_AUTHOR_EMAIL": "probe@example.invalid",
        "GIT_COMMITTER_NAME": "Probe",
        "GIT_COMMITTER_EMAIL": "probe@example.invalid",
    }


@pytest.fixture
def start_session(package_path):
    """Starts a long-running plannotator command; kills its process group when the test ends."""
    processes = []

    def start(arguments, environment, cwd):
        process = subprocess.Popen(
            [str(package_path / "bin" / "plannotator"), *arguments],
            env=environment,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        processes.append(process)
        return process

    yield start
    # The whole group, even after a clean exit: a child such as sem may outlive plannotator itself.
    for process in processes:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def run_plannotator(package_path, arguments, environment, cwd=None, timeout=300):
    return subprocess.run(
        [str(package_path / "bin" / "plannotator"), *arguments],
        env=environment,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def wait_for_browser_calls(browser_file, timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if browser_file.exists() and browser_file.read_text().splitlines():
            return browser_file.read_text().splitlines()
        time.sleep(0.2)
    pytest.fail(f"plannotator did not run the browser command within {timeout} seconds")


def session_base_url(browser_file):
    """The advertised URL says localhost; requests go to 127.0.0.1 so the Host header is predictable."""
    argument_count, url = wait_for_browser_calls(browser_file)[0].split("\t", 1)
    assert argument_count == "1", f"browser command got {argument_count} arguments"
    match = ADVERTISED_URL_PATTERN.fullmatch(url)
    assert match, f"unexpected session URL {url!r}"
    return f"http://127.0.0.1:{match.group(1)}"


def request_json(url, method="GET", body=None, headers=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, json.loads(response.read() or b"null")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"null")


def listening_addresses(process_id):
    output = subprocess.run(
        ["ss", "-ltnpH"], capture_output=True, text=True, check=True
    ).stdout
    return [
        line.split()[3] for line in output.splitlines() if f"pid={process_id}," in line
    ]


def make_repository(repository_path, environment):
    repository_path.mkdir()

    def git(*arguments):
        subprocess.run(
            ["git", *arguments], cwd=repository_path, env=environment, check=True
        )

    git("init", "-q", "-b", "main")
    (repository_path / "greeting.ts").write_text(ORIGINAL_SOURCE)
    git("add", "greeting.ts")
    git("commit", "-q", "-m", "Initial greeting")
    (repository_path / "greeting.ts").write_text(CHANGED_SOURCE)


def test_reports_its_pinned_version(package_path, environment):
    result = run_plannotator(package_path, ["--version"], environment)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"plannotator {PLANNOTATOR_VERSION}"


def test_ships_the_pinned_skills(package_path):
    for skill_name in SKILL_NAMES:
        skill_text = (
            package_path / "share" / "claude-code" / "skills" / skill_name / "SKILL.md"
        ).read_text()
        assert f"name: {skill_name}" in skill_text
        assert "disable-model-invocation: true" in skill_text


def test_stays_on_loopback_with_sharing_off_whatever_the_caller_asks(
    tmp_path, environment, browser_file, start_session
):
    # A cc remote pane carries SSH_CONNECTION, which alone would switch upstream to a 0.0.0.0 bind.
    hostile_environment = {
        **environment,
        "SSH_CONNECTION": "192.0.2.1 50000 192.0.2.2 22",
        "SSH_TTY": "/dev/pts/9",
        "PLANNOTATOR_REMOTE": "1",
        "PLANNOTATOR_SHARE": "enabled",
    }
    (tmp_path / "probe.md").write_text("# Probe\n\nA line to annotate.\n")
    process = start_session(["annotate", "probe.md"], hostile_environment, tmp_path)
    base_url = session_base_url(browser_file)

    addresses = listening_addresses(process.pid)
    assert addresses, "no listening socket found for the plannotator process"
    assert all(address.startswith("127.0.0.1:") for address in addresses), addresses

    status, plan = request_json(f"{base_url}/api/plan")
    assert status == 200
    assert plan["sharingEnabled"] is False

    status, _ = request_json(
        f"{base_url}/api/feedback",
        "POST",
        {"feedback": "Probe feedback from the test.", "annotations": []},
    )
    assert status == 200
    stdout, stderr = process.communicate(timeout=60)
    assert process.returncode == 0, stderr
    assert "Probe feedback from the test." in stdout


def test_semantic_diff_runs_the_pinned_sem(
    tmp_path, environment, browser_file, start_session
):
    repository_path = tmp_path / "repository"
    make_repository(repository_path, environment)
    process = start_session(["review"], environment, repository_path)
    base_url = session_base_url(browser_file)

    status, semantic_diff = request_json(f"{base_url}/api/semantic-diff")
    assert status == 200
    assert semantic_diff["status"] == "ok", semantic_diff
    assert semantic_diff["semVersion"] == SEM_VERSION
    assert semantic_diff["semSource"] == "env"

    status, _ = request_json(f"{base_url}/api/exit", "POST", {})
    assert status == 200
    process.communicate(timeout=60)


@pytest.mark.parametrize("runtime_name", ["agent-terminal", "call-flow"])
def test_runtime_directory_is_read_only(
    package_path, environment, data_path, runtime_name
):
    assert run_plannotator(package_path, ["--version"], environment).returncode == 0
    vendor_path = data_path / "vendor"
    assert vendor_path.stat().st_mode & 0o777 == 0o555

    result = run_plannotator(
        package_path, ["install-runtime", runtime_name], environment
    )
    assert result.returncode != 0, result.stdout
    # The refusal must come from vendor/ itself, not from a missing Node or npm, or from the network.
    # agent-terminal reports it on stdout; call-flow dies on it with an uncaught exception on stderr.
    assert "EACCES" in result.stdout + result.stderr, result.stdout + result.stderr
    assert list(vendor_path.iterdir()) == []


def test_call_flow_cannot_install_from_the_review_ui(
    tmp_path, environment, browser_file, data_path, start_session
):
    (data_path / "config.json").write_text(
        json.dumps({"reviewAnalysis": {"callFlow": True}})
    )
    repository_path = tmp_path / "repository"
    make_repository(repository_path, environment)
    process = start_session(["review"], environment, repository_path)
    base_url = session_base_url(browser_file)

    # Accepted and running means the origin check and the Node preflight passed, so the install really starts.
    status, install_status = request_json(
        f"{base_url}/api/call-flow/install",
        "POST",
        {"languageIds": ["javascript-typescript"]},
        {"Origin": base_url},
    )
    assert status == 200, install_status
    assert install_status.get("state") == "running", install_status
    deadline = time.monotonic() + 180
    while install_status.get("state") == "running" and time.monotonic() < deadline:
        time.sleep(1)
        _, install_status = request_json(f"{base_url}/api/call-flow/install-status")
    assert install_status.get("state") == "error", install_status
    assert "EACCES" in install_status.get("error", ""), install_status
    assert list((data_path / "vendor").iterdir()) == []

    request_json(f"{base_url}/api/exit", "POST", {})
    process.communicate(timeout=60)
