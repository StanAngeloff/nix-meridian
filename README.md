# nix-meridian

A declarative NixOS system and home configuration, focused on reproducibility and maintainability.

## Overview

This repository contains my personal NixOS system configuration and home environment setup, managed through Nix flakes. It represents a transition from my previous Ansible-based setup ([StanAngeloff/longitude](https://github.com/StanAngeloff/longitude)) to a fully declarative system configuration.

### Key Features

- **GNOME Shell** desktop environment with carefully chosen extensions
- **Development Environment**:
  - NeoVim with extensive plugin configuration via nixvim
  - Git with advanced configuration
  - Zsh as default shell
  - Podman for containerization
- **Terminal Setup**:
  - Alacritty as the primary terminal
  - tmux for session management
  - Custom prompt and key bindings
- **Applications**:
  - Brave ~~Firefox with privacy-focused configuration~~
  - Thunderbird
  - Various GUI and CLI tools
  - Key programming languages

## Structure

```
.
├── home/              # Home Manager configuration
│   ├── apps/          # Application-specific configurations
│   ├── essentials/    # Core user environment settings
│   ├── gnome-shell/   # GNOME Shell customization
│   └── services/      # User services (GPG, SSH, etc.)
├── machines/          # Machine-specific configurations
├── modules/           # Custom Nix modules
└── system/            # NixOS system configuration
    ├── apps/          # System-wide applications
    └── components/    # System components (audio, networking, etc.)
```

## Requirements

- NixOS 25.05 or later
- Private fonts:
  - Berkeley Mono™ (TX-02) - primary monospace font

### Post-Installation Steps

1. Install Berkeley Mono™ and patch with Nerd Fonts [(always use `*.ttf` fonts for this)](https://github.com/ryanoasis/nerd-fonts/issues/1772):

   ```bash
   cd ~/.local/share/fonts
   nix-shell -I nixpkgs=https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz -p nerd-font-patcher -p parallel
   parallel -j8 nerd-font-patcher --no-progressbars --careful --has-no-italic --single-width-glyphs --complete --name postscript {} ::: *.ttf
   ```

   Be patient! The patching will take a while.

2. Import GPG secret keys from a backup

## Usage

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/StanAngeloff/nix-meridian.git
cd nix-meridian

# Build and switch to the configuration
sudo nixos-rebuild switch --flake .
```

### Updating

```bash
# Pull latest changes
git pull

# Rebuild the system
sudo nixos-rebuild switch --flake .
```

## Components

### Desktop Environment

- **Window Manager**: GNOME Shell with custom keybindings
- **Theme**: Dark variant with custom font configuration
- **Extensions**:
  - Clipboard Indicator
  - Window Title Is Back
  - Bing Wallpaper Changer
  - Various usability improvements

### Development Tools

- **Editor**: Neovim with extensive plugin configuration:
  - LSP support
  - Treesitter
  - Git integration
  - Custom keybindings
  - Completion & snippets
- **Version Control**: Git with advanced configuration
- **Terminal Multiplexer**: tmux with custom bindings

### Security

- Full disk encryption
- GPG & SSH agent configuration
- Secure defaults

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
