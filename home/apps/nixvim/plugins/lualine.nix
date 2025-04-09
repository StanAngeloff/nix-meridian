{ pkgs-unstable, ... }:
{
  programs.nixvim.plugins.lualine = {
    enable = true;
    package = pkgs-unstable.vimPlugins.lualine-nvim;

    luaConfig.pre = # lua
      ''
        local lualine__monochrome = {
          a = { fg = '#e4e4e4', bg = '#3a3a3a', gui = 'NONE' },
          b = { fg = '#e4e4e4', bg = '#4e4e4e' },
          c = { fg = '#eeeeee', bg = '#262626' },
        }

        local lualine__theme = {
          normal = lualine__monochrome,
          insert = lualine__monochrome,
          visual = lualine__monochrome,
          replace = lualine__monochrome,
          inactive = {
            a = { fg = '#666666', bg = lualine__monochrome.a.bg, gui = 'NONE' },
          },
        }
      '';

    settings = {
      options = {
        theme.__raw = "lualine__theme";
        icons_enabled = true;
        component_separators = {
          left = "";
          right = "";
        };
        section_separators = {
          left = "";
          right = "";
        };
      };
      sections = {
        lualine_a = [
          "mode"
          {
            __unkeyed = "%{&spell ? '󰓆  ' : ''}";
            draw_empty = false;
            padding = 0;
          }
          {
            __unkeyed = "%{&paste ? '󰆒  ' : ''}";
            draw_empty = false;
            padding = 0;
          }
        ];
        lualine_b = [
          {
            __unkeyed = "filename";
            path = 1;
            symbols = {
              modified = "∗";
            };
          }
        ];
        lualine_c = [
          {
            __unkeyed = "diff";
            diff_color = {
              added = "LuaLineDiffAdd";
              modified = "LuaLineDiffChange";
              removed = "LuaLineDiffDelete";
            };
          }
          {
            __unkeyed = "diagnostics";
            diagnostics_color = {
              error = "LuaLineDiagnosticError";
              warn = "LuaLineDiagnosticWarn";
              info = "LuaLineDiagnosticInfo";
              hint = "LuaLineDiagnosticHint";
            };
          }
        ];
        lualine_x = [
          {
            __unkeyed = "copilot";
            symbols = {
              spinners = "dots_hop";
            };
            show_colors = false;
            show_loading = true;
          }
          "encoding"
          "fileformat"
        ];
        lualine_y = [ "progress" ];
        lualine_z = [ "location" ];
      };
    };
  };
}
