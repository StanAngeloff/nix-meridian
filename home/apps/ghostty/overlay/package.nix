{
  lib,
  writeShellApplication,
  ghostty,
  name,
  command,
  runtimeEnv ? { },
  window-background ? "#060610",
  window-width ? 80,
  window-height ? 24,
  window-padding ? 8,
  ...
}@args:
let
  fromHex =
    hex:
    let
      clean = builtins.substring 1 6 hex;
      r = lib.fromHexString (builtins.substring 0 2 clean);
      g = lib.fromHexString (builtins.substring 2 2 clean);
      b = lib.fromHexString (builtins.substring 4 2 clean);
    in
    {
      inherit r g b;
    };

  toHex =
    n:
    let
      s = lib.toHexString n;
    in
    if builtins.stringLength s == 1 then "0${s}" else s;

  clamp = x: lib.min 255 (lib.max 0 x);

  mix =
    c1: c2:
    let
      rgb1 = fromHex c1;
      rgb2 = fromHex c2;
      r = clamp (rgb1.r + rgb2.r);
      g = clamp (rgb1.g + rgb2.g);
      b = clamp (rgb1.b + rgb2.b);
    in
    "#${toHex r}${toHex g}${toHex b}";
in
writeShellApplication {
  inherit name runtimeEnv;

  text = ''
    export FZF_DEFAULT_OPTS="''${FZF_DEFAULT_OPTS:-} \
      --color=bg+:${mix window-background "#333333"} \
      --color=fg:dim,fg+:regular \
      --color=hl:-1:regular:underline,hl+:-1:regular:underline \
    ";

    ${lib.getExe ghostty} \
      --maximize=false \
      --window-decoration=auto \
      --window-width=${builtins.toString window-width} --window-height=${builtins.toString window-height} \
      --window-padding-x=${builtins.toString window-padding} --window-padding-y=${builtins.toString window-padding} \
      --gtk-custom-css=${../gtk-overlay.css} \
      --background=${lib.escapeShellArg window-background} ${
        builtins.concatStringsSep "," (
          lib.mapAttrsToList (name: value: "--${name}=${lib.escapeShellArg name}") (
            builtins.removeAttrs args [
              "lib"
              "writeShellApplication"
              "name"
              "command"
              "runtimeEnv"
              "ghostty"
              "window-background"
              "window-width"
              "window-height"
              "window-padding"
            ]
          )
        )
      } -e sh -c ${lib.escapeShellArg command}
  '';
}
