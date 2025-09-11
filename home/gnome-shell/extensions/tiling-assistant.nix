{ pkgs, ... }:
let
  rect =
    x: y: width: height:
    opts@{
      loopType ? null,
      appId ? null,
    }:
    {
      inherit appId loopType;
      rect = {
        inherit
          x
          y
          width
          height
          ;
      };
    };
  items = list: {
    _items = builtins.map (
      i:
      let
        x = builtins.elemAt i 0;
        y = builtins.elemAt i 1;
        w = builtins.elemAt i 2;
        h = builtins.elemAt i 3;
        opts = if builtins.length i > 4 then builtins.elemAt i 4 else { };
      in
      rect x y w h opts
    ) list;
  };
  layout = name: list: { _name = name; } // (items list);
in
{
  programs.gnome-shell.extensions = with pkgs.gnomeExtensions; [
    { package = tiling-assistant; }
  ];

  dconf.settings."org/gnome/shell/extensions/tiling-assistant" = {
    enable-advanced-experimental-features = true;
    import-layout-examples = false;
    search-popup-layout = [ "<Super>KP_5" ];
    tile-maximize = [ "<Super>Up" ];
  };

  home.file.".config/tiling-assistant/layouts.json".text = builtins.toJSON [
    # nixfmt: off
    (layout "3 : 1" [ [ 0 0 0.75 1 ] [ 0.75 0 0.25 1 ] ])
    (layout "N-Columns" [ [ 0 0 1 1 { loopType = "v"; } ] ])
    (layout "Master and Stack" [ [ 0 0 0.5 1 ] [ 0.5 0 0.5 1 { loopType = "h"; } ] ])
    # nixfmt: on, as: list-of-calls
  ];
}
