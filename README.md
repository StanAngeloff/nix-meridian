# nix-meridian

Clean-slate NixOS and home configuration.

## About

This is an experimental repository containing my NixOS and home configuration files. It represents a fresh start from my previous setup ([StanAngeloff/longitude](https://github.com/StanAngeloff/longitude)) which relied on traditional dotfiles management and Ansible for system bootstrapping.

While that approach served me well through the 2020s, NixOS has rekindled my interest in truly reproducible systems. The promise of bringing up an entire system from declarative configuration files aligns perfectly with my infrastructure-as-code philosophy, but takes it to a whole new level.

## Status

This repository is highly experimental and personal. I'm using it to explore NixOS on a new machine while deliberately leaving behind years of accumulated tooling and configurations. This means:

- It's specifically tailored to my needs and preferences
- Many of my usual tools and conveniences are intentionally missing
- The repository history may be rewritten at any time
- Configuration choices might be suboptimal as I learn

### Hiccups

#### Berkeley Mono™ (TX-02) Typeface

This font family has to be downloaded and installed manually. Patch with Nerd Fonts afterwards:

```shellsession
$ cd ~/.local/share/fonts
$ nix-shell -p nerd-font-patcher
$ for f in *.ttf; do nerd-font-patcher --progressbars --mono --adjust-line-height --complete $f ; done
```

#### `dropbox`

```shellsession
$ DISPLAY= dropbox update
```

```
Dropbox is the easiest way to share and store your files online. Want to learn more? Head to https://www.dropbox.com/
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
FileNotFoundError: [Errno 2] No such file or directory: '/home/stan/.dropbox-hm'
```

## Future

Should this experiment prove successful in meeting my daily computing needs, I plan to archive my previous dotfiles and Ansible configurations, fully embracing the Nix way. However, NixOS still needs to prove itself as a long-term solution for my workflow.
