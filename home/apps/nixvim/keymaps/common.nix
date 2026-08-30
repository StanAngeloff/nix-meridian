# Keymaps common to the full nixvim configuration and popup-nvim.
# Each entry uses a simple { key, modes, action } record with optional desc.
#
# Consumers convert to their native format:
#   - keymaps/default.nix        -> programs.nixvim.keymaps entries
#   - modules/lib/popup-nvim.nix -> vimscript lines in init.vim
{
  leader = ",";

  keymaps = [
    # Motion
    {
      key = "j";
      modes = [
        "n"
        "v"
      ];
      action = "gj";
    }
    {
      key = "k";
      modes = [
        "n"
        "v"
      ];
      action = "gk";
    }
    {
      key = "Y";
      modes = [ "n" ];
      action = "y$";
      desc = "Make Y consistent with C and D. See ':help Y'";
    }
    {
      key = "$";
      modes = [ "v" ];
      action = "g_";
      desc = "Make $ behave consistently in visual mode";
    }

    # Clipboard
    {
      key = "<leader>p";
      modes = [
        "n"
        "v"
      ];
      action = "\"+p";
      desc = "Paste from the system clipboard";
    }
    {
      key = "<leader>P";
      modes = [
        "n"
        "v"
      ];
      action = "\"+P";
      desc = "Paste from the system clipboard";
    }
    {
      key = "<leader>y";
      modes = [ "v" ];
      action = "\"+y";
      desc = "Yank to the system clipboard";
    }
    {
      key = "<leader>d";
      modes = [ "v" ];
      action = "\"+d";
      desc = "Delete to the system clipboard";
    }
    {
      key = "<leader>=";
      modes = [ "n" ];
      action = "mZggVG\"+yg`Z";
      desc = "Copy entire buffer to the system clipboard";
    }
    {
      key = "<leader>v";
      modes = [ "n" ];
      action = "g`[Vg`]o";
      desc = "Restore last implicit selection (e.g., on paste) in visual mode";
    }

    # Escape
    {
      key = "<C-C>";
      modes = [
        "n"
        "i"
        "v"
      ];
      action = "<Esc><Esc>";
      desc = "Escape, escape!";
    }

    # Insert mode undo groups
    {
      key = "<C-W>";
      modes = [ "i" ];
      action = "<C-G>u<C-W>";
    }
    {
      key = "<C-R>";
      modes = [ "i" ];
      action = "<C-G>u<C-R>";
    }
    {
      key = "<C-J>";
      modes = [ "i" ];
      action = "<C-G>u<C-O>o";
    }
    {
      key = "<C-K>";
      modes = [ "i" ];
      action = "<C-G>u<C-O>O";
    }
    {
      key = "<C-L>";
      modes = [ "i" ];
      action = "<C-O>:normal <C-L><CR>";
    }
    {
      key = "<Return>";
      modes = [ "i" ];
      action = "<C-G>u<CR>";
    }
  ];
}
