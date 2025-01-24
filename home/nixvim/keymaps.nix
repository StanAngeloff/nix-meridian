{
  programs.nixvim.keymaps = [
    {
      action = ":NERDTreeMirrorToggle<CR>";
      key = "<Tab>";
      mode = "n";
    }
  ];
}
