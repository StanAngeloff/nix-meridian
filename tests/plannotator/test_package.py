r"""Behavior tests for pkgs/plannotator, against the real build.

What each file covers:
- this file: the wrapper's pinned settings and read-only runtime directory;
- test_namespace.py: the loopback-only namespace;
- test_window.py: the review window;
- test_teardown.py: every way a review ends.
harness.py explains how a test reaches a server it cannot connect to.

PLANNOTATOR_PACKAGE names a package built with installSkills = true.
Every test gets its own HOME and data directory under pytest's base temporary directory.
conftest.py moves that directory to ~/.cache/plannotator-tests, because the namespace masks /tmp.
Review windows open on a headless Weston, so nothing appears on the desktop, and nothing touches ~/.claude/plannotator.
pkgs/plannotator/update.sh runs these after every bump. To run them by hand, from the repository root:

    export PLANNOTATOR_PACKAGE="$(nix build --no-link --print-out-paths --impure --expr \
      "(builtins.getFlake \"path:$PWD\").nixosConfigurations.stan-latitude.pkgs.plannotator.override { installSkills = true; }")"
    nix shell --inputs-from "path:$PWD" nixpkgs#python3Packages.pytest nixpkgs#nodejs nixpkgs#git nixpkgs#iproute2 \
      nixpkgs#weston --command pytest -p no:cacheprovider tests/plannotator

XDG_RUNTIME_DIR must be under /run. The namespace tests also run each check outside the namespace, as a control,
so they need what the namespace takes away: DNS, https://example.com/ and the nix daemon.
Node is on PATH so the runtime installs get past their Node preflight to the point where they would write into vendor/.
"""

import json
import struct
import subprocess
import time

import pytest

PLANNOTATOR_VERSION = "0.27.22"
SEM_VERSION = "0.8.0"
SKILL_NAMES = ["plannotator-annotate", "plannotator-last", "plannotator-review"]
ORIGINAL_SOURCE = (
    "export function greet(name: string): string {\n  return `Hello, ${name}`;\n}\n"
)
CHANGED_SOURCE = (
    "export function greet(name: string): string {\n  return `Hello there, ${name}!`;\n}\n\n"
    "export function part(name: string): string {\n  return `Goodbye, ${name}`;\n}\n"
)


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
    tmp_path, environment, start_session
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
    session = start_session(
        ["annotate", "probe.md"],
        hostile_environment,
        tmp_path,
        probe={"checks": ["listeners"]},
    )

    # ss runs inside the server's network namespace, where its sockets are.
    listeners = session.probe_result()["listeners"]
    assert listeners, "no listening socket found for the plannotator process"
    assert all(address.startswith("127.0.0.1:") for address in listeners), listeners

    status, plan = session.request_json("/api/plan")
    assert status == 200
    assert plan["sharingEnabled"] is False

    status, _ = session.request_json(
        "/api/feedback",
        "POST",
        {"feedback": "Probe feedback from the test.", "annotations": []},
    )
    assert status == 200
    stdout, stderr = session.process.communicate(timeout=60)
    assert session.process.returncode == 0, stderr
    assert "Probe feedback from the test." in stdout


def test_semantic_diff_runs_the_pinned_sem(tmp_path, environment, start_session):
    repository_path = tmp_path / "repository"
    make_repository(repository_path, environment)
    session = start_session(["review"], environment, repository_path)

    status, semantic_diff = session.request_json("/api/semantic-diff")
    assert status == 200
    assert semantic_diff["status"] == "ok", semantic_diff
    assert semantic_diff["semVersion"] == SEM_VERSION
    assert semantic_diff["semSource"] == "env"

    status, _ = session.request_json("/api/exit", "POST", {})
    assert status == 200
    session.process.communicate(timeout=60)


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
    tmp_path, environment, data_path, start_session
):
    (data_path / "config.json").write_text(
        json.dumps({"reviewAnalysis": {"callFlow": True}})
    )
    repository_path = tmp_path / "repository"
    make_repository(repository_path, environment)
    session = start_session(["review"], environment, repository_path)

    # Accepted and running means the origin check and the Node preflight passed, so the install really starts.
    status, install_status = session.request_json(
        "/api/call-flow/install",
        "POST",
        {"languageIds": ["javascript-typescript"]},
        {"Origin": session.base_url},
    )
    assert status == 200, install_status
    assert install_status.get("state") == "running", install_status
    deadline = time.monotonic() + 180
    while install_status.get("state") == "running" and time.monotonic() < deadline:
        time.sleep(1)
        _, install_status = session.request_json("/api/call-flow/install-status")
    assert install_status.get("state") == "error", install_status
    assert "EACCES" in install_status.get("error", ""), install_status
    assert list((data_path / "vendor").iterdir()) == []

    session.request_json("/api/exit", "POST", {})
    session.process.communicate(timeout=60)


def test_ships_the_review_windows_desktop_entry_and_icon(package_path):
    desktop_lines = (
        (package_path / "share" / "applications" / "plannotator.desktop")
        .read_text()
        .splitlines()
    )
    for line in [
        "Name=Plannotator",
        "Icon=plannotator",
        "StartupWMClass=plannotator",
        "NoDisplay=true",
    ]:
        assert line in desktop_lines, desktop_lines
    icon_bytes = (
        package_path
        / "share"
        / "icons"
        / "hicolor"
        / "256x256"
        / "apps"
        / "plannotator.png"
    ).read_bytes()
    # A PNG whose header chunk says 256 by 256, as the icon directory promises.
    assert icon_bytes[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", icon_bytes[16:24]) == (256, 256)
