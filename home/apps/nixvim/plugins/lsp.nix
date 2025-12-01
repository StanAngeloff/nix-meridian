{ pkgs, pkgs-unstable, ... }:
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
            package = pkgs.graphql-language-service-cli;
          };
          html = {
            enable = true;
          };
          jsonls = {
            enable = true;
            package = pkgs-unstable.vscode-json-languageserver;
          };
          jsonnet_ls = {
            enable = true;
            package = pkgs-unstable.jsonnet-language-server;
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
          terraformls = {
            enable = true;
          };
          theme_check = {
            enable = true;
            package = null;
          };
          ts_ls = {
            enable = true;
            # NOTE: I used to enable denols conditionally based on the presence of a deno.json,
            #       but I rarely work on Deno-only projects these days – it's not worth the complexity.
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
        };
      };
    };
  };
}
