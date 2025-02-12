{
  programs.nixvim.plugins.blink-cmp = {
    enable = true;

    settings = {
      signature.enabled = true;

      keymap = {
        "<C-K>" = [
          "select_prev"
          "fallback"
        ];
        "<C-J>" = [
          "select_next"
          "fallback"
        ];
        "<Return>" = [
          "select_and_accept"
          "fallback"
        ];
      };
    };
  };
}
