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
            vim.keymap.set('n', '<leader>c', '<cmd>Lspsaga code_action<CR>', bufopts)

            vim.keymap.set('n', '[e', '<cmd>Lspsaga diagnostic_jump_prev<CR>', bufopts)
            vim.keymap.set('n', ']e', '<cmd>Lspsaga diagnostic_jump_next<CR>', bufopts)

            -- BUG: terraform-ls's semantic tokens drive Neovim 0.12's semantic_tokens.lua
            --      into an unbounded loop on files whose tokens run past the end of the
            --      buffer (for example a trailing heredoc), which hangs the editor.
            --      The treesitter highlighter still covers terraform, so disable only the
            --      semantic-token capability for this server.
            if client.name == 'terraformls' then
              client.server_capabilities.semanticTokensProvider = nil
            end
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
            # NOTE: nixd's default --log=info traces every request and reply to stderr,
            #       and Neovim writes each stderr chunk to lsp.log as an ERROR line.
            cmd = [
              "nixd"
              "--log=error"
            ];
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
          tsgo = {
            enable = true;
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

    # NOTE: Neovim doesn't offer file watching to language servers on Linux, and tsgo then turns its own watching off,
    #       so it misses files changed on disk (a git checkout, generated code) until it restarts.
    #       This is a separate vim.lsp.config call because Neovim deep-merges it into the server's config,
    #       whereas capabilities set through plugins.lsp would replace the shared ones, blink-cmp's included.
    #       See https://github.com/nix-community/nixvim/blob/4836e77b1798cd42e2de28593bec4c1788da08f5/modules/lsp/servers/default.nix#L185
    extraConfigLua = # lua
      ''
        vim.lsp.config('tsgo', {
          capabilities = { workspace = { didChangeWatchedFiles = { dynamicRegistration = true } } },
        })

        vim.api.nvim_set_hl(0, "LspInlayHint", { fg = "#4f4f4f" })
      '';
  };
}
