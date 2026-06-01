# nix-meridian

A declarative NixOS system and home configuration, focused on reproducibility and maintainability.

## Overview

This repository contains my personal NixOS system configuration and home environment setup, managed through Nix flakes. It represents a transition from my previous Ansible-based setup ([StanAngeloff/longitude](https://github.com/StanAngeloff/longitude)) to a fully declarative system configuration.

The source tree is the source of truth. Rather than maintaining a parallel inventory here, look at:

- `home/apps/` — every user-space program I install, one directory per app.
- `system/components/` — every system-level component (audio, networking, podman, …).
- `home/gnome-shell/extensions/` — every GNOME Shell extension that's enabled.

### Highlights

- **Desktop**: GNOME Shell with a curated set of extensions.
- **Editor**: NeoVim via [nixvim](https://github.com/nix-community/nixvim).
- **Terminal**: Ghostty + tmux + zsh.
- **Containers**: rootless Podman (no Docker socket — `sudo` is required by design).
- **AI tooling**: my own [flemma.nvim](https://github.com/Flemma-Dev/flemma.nvim) — an AI workspace inside Neovim where every conversation is a `.chat` file you own — plus Claude Code.

## How it actually feels to use

- `<Super>t` opens Ghostty, or focuses the existing window if one's already up. `home/apps/ghostty/launch/`
- `<Super>s` opens Voxize for voice input — see [StanAngeloff/voxize](https://github.com/StanAngeloff/voxize). `home/apps/voxize/`
- `<Ctrl><Shift>e` opens `unipicker` in a Ghostty overlay window. The chosen codepoint lands in the clipboard via `wl-copy`. `home/gnome-shell/keybindings.nix`
- Screenshots saved under `~/Pictures/Screenshots` open in Swappy automatically (systemd user service + `inotifywait`). `home/apps/swappy/launch/`
- In `eog`, a Swappy plugin adds an "annotate" action so you can mark up an image you're already viewing. `home/apps/eog/`
- `less` is replaced by `ov` everywhere, including `git`'s pager. An `ov-less.yaml` keeps the less-style keybinds. `home/apps/ov/`
- `git diff` and `git show` use `tig` as the pager (with a perl ANSI stripper in front). `home/apps/tig/`
- In tmux, `prefix C-g` toggles a `tig status` popup; once it's open, `Alt+z` toggles its size between 90% and 100% (outside the popup it falls back to `resize-pane -Z`). `home/apps/tmux/abilities/tmux.tig.conf`
- In tmux copy-mode, `d` on a `/nix/store/...` path runs `nix-diff /run/current-system <path> | ov` in a popup. `home/apps/tmux/abilities/tmux.nix-diff.conf`
- `nsx <pkg> -- <cmd>` is `npx` for nixpkgs — fetches `<pkg>` from the chosen channel and runs `<cmd>`. `home/apps/nsx/`
- `preview <file.md>` renders Markdown in Brave via headless nvim + the (revived) `markdown-preview.nvim`. The browser tab survives nvim's exit. `home/apps/nixvim/plugins/markdown-preview-nvim/`
- The zsh cursor reflects whether the prompt is editable: beam means you can type, block means a command is running. `home/apps/zsh/default.nix`

## Structure

```
.
├── home/              # Home Manager configuration
│   ├── apps/          # User-space applications (one directory per app)
│   ├── essentials/    # Core user environment, fonts, GTK, XDG
│   ├── gnome-shell/   # GNOME Shell extensions, settings, keybindings
│   └── services/      # User services (Bluetooth, GPG, SSH)
├── machines/          # Per-machine hardware configuration
├── modules/           # Custom Nix modules and shared options
├── pkgs/              # Local package overlays (e.g. Ghostty)
├── system/            # NixOS system configuration
│   ├── apps/          # System-wide applications
│   └── components/    # System components
├── contrib/           # Helper scripts (e.g. nixfmt-pretty.awk)
├── flake.nix          # Flake inputs and outputs
├── Makefile           # `make switch`, `make format`
└── treefmt.toml       # Formatter wiring (nixfmt + shfmt + stylua + ruff/black)
```

## Requirements

- NixOS 26.05 or later
- Private fonts:
  - Berkeley Mono™ (TX-02) — primary monospace font

### Post-Installation Steps

1. Install Berkeley Mono™ and patch with Nerd Fonts [(always use `*.ttf` fonts for this)](https://github.com/ryanoasis/nerd-fonts/issues/1772):

   ```bash
   cd ~/.local/share/fonts
   nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz -p nerd-font-patcher -p parallel
   parallel -j8 nerd-font-patcher --no-progressbars --careful --has-no-italic --single-width-glyphs --complete --name postscript {} ::: *.ttf
   ```

   Be patient! The patching will take a while.

2. Import GPG secret keys from a backup.

## Usage

### Initial install (bootstrap)

> [!IMPORTANT]
> On a freshly cloned, not-yet-rebuilt system, **`make switch` will not work** — neither `gnumake` nor `nh` is on `PATH` until the first rebuild has run home-manager activation. Use the stock `nixos-rebuild` invocation for the very first switch, and only then move to the Makefile.

```bash
git clone https://github.com/StanAngeloff/nix-meridian.git
cd nix-meridian
sudo nixos-rebuild switch --flake .
```

That single rebuild brings up the NixOS system _and_ the home-manager profile, which is what puts `make`, `nh`, and friends on `PATH`.

### Day-to-day (after the bootstrap above)

Once the initial rebuild has completed at least once, the Makefile is the front door:

```bash
make switch   # nh os switch --ask .
make format   # treefmt across nix/python/shell/lua
```

`nh` shows a diff and asks before applying, which beats raw `nixos-rebuild` for routine changes.

## Security

- Full disk encryption (LUKS).
- Firewall on, with interface-scoped rules for `podman+`.
- `sudo` cache disabled — `timestamp_timeout=0` — with narrow `NOPASSWD` carve-outs for the `nh`/`switch-to-configuration` flow only.
- Rootless Podman; no Docker socket exposed.
- GPG & SSH agent configuration.

## Known Issues

- Dropbox installation requires manual intervention
- Some applications may need additional configuration on first run

### `dropbox`

<details>
<summary><code>$ DISPLAY= dropbox update</code></summary>
<pre>Dropbox is the easiest way to share and store your files online. Want to learn more? Head to https://www.dropbox.com/
In order to use Dropbox, you must download the proprietary daemon.
Note: python3-gpg (python3-gpgme for Ubuntu 16.10 and lower) is not installed, we will not be able to verify binary signatures. [y/n] Traceback (most recent call last):
  File "[..]/urllib/request.py", line 1344, in do_open
    h.request(req.get_method(), req.selector, req.data, headers,
  File "[..]/http/client.py", line 1336, in request
    self._send_request(method, url, body, headers, encode_chunked)
  File "[..]/http/client.py", line 1382, in _send_request
    self.endheaders(body, encode_chunked=encode_chunked)
  File "[..]/http/client.py", line 1331, in endheaders
    self._send_output(message_body, encode_chunked=encode_chunked)
  File "[..]/http/client.py", line 1091, in _send_output
    self.send(msg)
  File "[..]/http/client.py", line 1035, in send
    self.connect()
  File "[..]/http/client.py", line 1470, in connect
    super().connect()
  File "[..]/http/client.py", line 1001, in connect
    self.sock = self._create_connection(
                ^^^^^^^^^^^^^^^^^^^^^^^^
  File "[..]/socket.py", line 841, in create_connection
    for res in getaddrinfo(host, port, 0, SOCK_STREAM):
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "[..]/socket.py", line 976, in getaddrinfo
    for res in _socket.getaddrinfo(host, port, family, type, proto, flags):
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
socket.gaierror: [Errno -2] Name or service not known
During handling of the above exception, another exception occurred:
Traceback (most recent call last):
  File "[..]/bin/dropbox", line 568, in download
    for progress, status in download.copy_data():
                            ^^^^^^^^^^^^^^^^^^^^
  File "[..]/bin/dropbox", line 200, in download_file_chunk
    with closing(opener.open(url)) as f:
                 ^^^^^^^^^^^^^^^^
  File "[..]/urllib/request.py", line 515, in open
    response = self._open(req, data)
               ^^^^^^^^^^^^^^^^^^^^^
  File "[..]/urllib/request.py", line 532, in _open
    result = self._call_chain(self.handle_open, protocol, protocol +
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "[..]/urllib/request.py", line 492, in _call_chain
    result = func(*args)
             ^^^^^^^^^^^
  File "[..]/urllib/request.py", line 1392, in https_open
    return self.do_open(http.client.HTTPSConnection, req,
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "[..]/urllib/request.py", line 1347, in do_open
    raise URLError(err)
urllib.error.URLError: <urlopen error [Errno -2] Name or service not known>
Error: Trouble connecting to Dropbox servers. Maybe your internet connection is down, or you need to set your http_proxy environment variable.
Starting Dropbox...Traceback (most recent call last):
  File "[..]/bin/dropbox", line 1587, in <module>
    ret = main(sys.argv)
          ^^^^^^^^^^^^^^
  File "[..]/bin/dropbox", line 1576, in main
    result = commands[argv[i]](argv[i+1:])
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "[..]/bin/dropbox", line 1427, in start
    if not start_dropbox():
           ^^^^^^^^^^^^^^^
  File "[..]/bin/dropbox", line 763, in start_dropbox
    subprocess.Popen([DROPBOXD_PATH], preexec_fn=os.setsid, cwd=os.path.expanduser("~"),
  File "[..]/subprocess.py", line 1026, in __init__
    self._execute_child(args, executable, preexec_fn, close_fds,
  File "[..]/subprocess.py", line 1955, in _execute_child
    raise child_exception_type(errno_num, err_msg, err_filename)
FileNotFoundError: [Errno 2] No such file or directory: '/home/stan/.dropbox-hm'</pre>
</details>

## Acknowledgments

This configuration draws inspiration from various sources and previous work:

- My previous Ansible-based setup ([StanAngeloff/longitude](https://github.com/StanAngeloff/longitude))
- The NixOS & Home Manager communities
- Various dotfiles repositories and configurations from the community

## License

MIT. Feel free to use any parts of this configuration as inspiration for your own setup.
