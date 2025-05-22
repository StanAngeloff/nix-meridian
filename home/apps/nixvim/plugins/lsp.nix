{ pkgs, ... }:
{
  programs.nixvim = {
    plugins = {
      lsp = {
        enable = true;
        inlayHints = true;

        onAttach = # lua
          ''
            -- Enable completion triggered by <C-X><C-O>
            vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

            -- Mappings
            --
            -- See `:help vim.lsp.*` for documentation on any of the below functions
            local bufopts = { noremap = true, silent = true, buffer = bufnr }

            vim.keymap.set('n', 'H', '<cmd>Lspsaga hover_doc<CR>', bufopts)
            vim.keymap.set('n', 'K', '<cmd>Lspsaga peek_type_definition<CR>', bufopts)
            vim.keymap.set('n', 'L', '<cmd>Lspsaga peek_definition<CR>', bufopts)
            vim.keymap.set('n', '<Space>', '<cmd>Lspsaga code_action<CR>', bufopts)

            vim.keymap.set('n', '[e', '<cmd>Lspsaga diagnostic_jump_prev<CR>', bufopts)
            vim.keymap.set('n', ']e', '<cmd>Lspsaga diagnostic_jump_next<CR>', bufopts)
          '';

        servers = {
          astro = {
            enable = true;
          };
          bashls = {
            enable = true;
          };
          cssls = {
            enable = true;
          };
          graphql = {
            enable = true;
          };
          html = {
            enable = true;
          };
          jsonls = {
            enable = true;
          };
          lua_ls = {
            enable = true;
          };
          nixd = {
            enable = true;
            settings = {
              formatting.command = [ "nixpkgs-fmt" ];
            };
          };
          tailwindcss = {
            enable = true;
          };
          theme_check = {
            enable = true;
            package = null;
          };
          typos_lsp = {
            enable = true;
            settings = {
              diagnosticSeverity = "Warning";
            };
          };
          vimls = {
            enable = true;
          };
          yamlls = {
            enable = true;
          };

          # Deno vs. TypeScript
          # See `:h vim.fs.root()`
          denols = {
            enable = true;
            extraOptions.single_file_support = false;
            rootMarkers = [
              # lua
              ''
                function (name)
                  return require("lspconfig").util.root_pattern("deno.json", "deno.jsonc")(name);
                end
              ''
            ];
          };
          ts_ls = {
            enable = true;
            extraOptions.single_file_support = false;
            rootMarkers = [
              # lua
              ''
                function (name)
                  local lspconfig = require("lspconfig");
                  local denolsFiles = lspconfig.util.root_pattern("deno.json", "deno.jsonc")(name);
                  if denolsFiles then
                    return nil;
                  end
                  return lspconfig.util.root_pattern("package.json", "tsconfig.json")(name);
                end
              ''
            ];
          };
        };
      };
    };
  };
}
