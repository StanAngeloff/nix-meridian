{
  lib,
  writeShellApplication,
  name ? "voxinput-record",
  # See https://gitlab.gnome.org/GNOME/adwaita-icon-theme/-/tree/gnome-48/Adwaita/symbolic for a list of icons.
  icon ? "audio-input-microphone",
  replaceVars,
  voxinput,
  dotool,
  libnotify,
  procps,
  systemd,
  tmux,
  zenity,
  gawk,
  python313Packages,
}:
writeShellApplication {
  inherit name;

  text = builtins.readFile (
    replaceVars ./record.sh {
      inherit name icon;

      voxinput = lib.getExe voxinput;

      busctl = "${lib.getBin systemd}/bin/busctl";
      dotool = "${lib.getBin dotool}/bin/dotool";
      gawk = lib.getExe gawk;
      llm = lib.getExe (python313Packages.llm.withPlugins { llm-anthropic = true; });
      notify-send = lib.getExe libnotify;
      pgrep = "${lib.getBin procps}/bin/pgrep";
      tmux = lib.getExe tmux;
      zenity = lib.getExe zenity;
    }
  );

  meta.mainProgram = name;
}
