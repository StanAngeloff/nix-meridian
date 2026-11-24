# Voxize Remote on this machine

Voxize Remote dictates on the phone into the Claude Code session it is showing: tap the floating microphone over Termux, speak, tap again, and this machine's Voxize pastes the cleaned-up text into that session's prompt, unsent. It ships with Voxize: the `voxize-remote` command, the Android client (each release carries it signed) and its documentation, in Voxize's README ("Voxize Remote") and `docs/architecture-decision-voxize-remote.md`.

This directory runs it here:

| Path | What |
| --- | --- |
| `default.nix` | the server on demand: socket units `voxize-remote-clients` (port 7223) and `voxize-remote-control` (`$XDG_RUNTIME_DIR/voxize-remote.sock`) start `voxize-remote.service`, which exits 5 minutes after its last client; tmux and Tailscale on its PATH, `TMUX_TMPDIR` for tmux's socket |
| `firewall.nix`, `port.nix` | the port, open on `tailscale0` only |
| `pkgs/voxize/package.nix` | the package: `voxize-remote`, the release's signed APK as `VOXIZE_REMOTE_APK`, adb and ffmpeg on its PATH |

## Setting up a phone

```sh
cc remote setup
```

Connect the phone with a USB cable (Developer options → USB debugging) when it asks, or type `w` to use Wireless debugging. Setup types the `ssh cc` bootstrap into Termux (after you press Enter), then runs `voxize-remote setup-client`: it installs the app, allows it the microphone, notifications, "Display over other apps" and Usage access, pairs it (the phone shows six digits, you type them here) and checks it connects. An app signed with another key, or newer than the release, is replaced without asking. Afterwards use a new Termux session (swipe in from the left edge, New session), `ssh cc`, open a session: the floating microphone appears.

Tailscale on the phone must carry Voxize Remote: with split tunneling set to selected apps, include it.

## On this machine

```sh
voxize-remote status                  # the connected client and the dictation in progress
voxize-remote devices                 # paired clients
voxize-remote unpair DEVICE           # forget one
journalctl --user -u voxize-remote    # the server's log
```

To try a Voxize checkout against the mock backend (no OpenAI calls), stop the units, run the server by hand on the same port, and start the sockets again afterwards:

```sh
systemctl --user stop voxize-remote.service voxize-remote-clients.socket voxize-remote-control.socket
uv run voxize-remote serve --mock --port 7223
systemctl --user start voxize-remote-clients.socket voxize-remote-control.socket
```
