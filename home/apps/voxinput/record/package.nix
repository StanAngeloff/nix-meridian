{
  lib,
  writeShellApplication,
  name ? "voxinput-record",
  icon ? "microphone-sensitivity-high",
  replaceVars,
  voxinput,
  libnotify,
  procps,
  systemd,
  tmux,
  zenity,
}:
writeShellApplication {
  inherit name;

  text = builtins.readFile (
    replaceVars ./record.sh {
      inherit name icon;

      voxinput = "${lib.makeBinPath [ voxinput ]}/voxinput";

      busctl = "${lib.makeBinPath [ systemd ]}/busctl";
      notify-send = "${lib.makeBinPath [ libnotify ]}/notify-send";
      pgrep = "${lib.makeBinPath [ procps ]}/pgrep";
      tmux = "${lib.makeBinPath [ tmux ]}/tmux";
      zenity = "${lib.makeBinPath [ zenity ]}/zenity";
    }
  );
}
