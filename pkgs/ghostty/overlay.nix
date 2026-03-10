{
  ghostty,
  runCommand,
  imagemagick,
}:
let
  manipulateIconsAndHueRotateToOrange = # bash
    ''
      for icon in $out/share/icons/hicolor/*/apps/com.mitchellh.ghostty.png; do
        chmod u+w "$icon"
        magick mogrify -define modulate:colorspace=HSB -modulate 100,100,180 "$icon"
      done
    '';
in
runCommand "ghostty"
  {
    nativeBuildInputs = [ imagemagick ];

    outputs = [
      "out"
      "terminfo"
      "shell_integration"
      "vim"
    ];

    meta = {
      mainProgram = "ghostty";
    };
  }
  ''
    cp -r ${ghostty} $out
    cp -r ${ghostty.terminfo} $terminfo
    cp -r ${ghostty.shell_integration} $shell_integration
    cp -r ${ghostty.vim} $vim

    ${manipulateIconsAndHueRotateToOrange}
  ''
