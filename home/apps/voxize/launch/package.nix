{
  writeShellApplication,
  coreutils,
  gawk,
  jq,
  systemd,
  tmux,
  voxize,
}:
# Super+S: voxize-tui in a tmux floating pane when Ghostty with tmux has focus, else the Voxize window (see voxize-launch.sh).
writeShellApplication {
  name = "voxize-launch";

  # systemd provides busctl; voxize provides both voxize and voxize-tui.
  runtimeInputs = [
    coreutils
    gawk
    jq
    systemd
    tmux
    voxize
  ];

  text = builtins.readFile ./voxize-launch.sh;
}
