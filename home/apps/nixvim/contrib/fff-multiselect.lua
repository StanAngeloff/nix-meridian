-- Restore fzf-lua-style multi-select habits on top of fff's picker.
--
-- fff 0.9.x has no "select all", and its <CR>/<C-t> only ever act on the item under the cursor. These actions reimplement the behaviour its released select() drops, by overriding the picker's buffer-local keymaps once fff has created them.
--
-- This reaches into fff's picker internals (picker_ui, picker_ui_state, utils), so it is pinned to the 0.9.x picker layout and is the first thing to revisit when the fff-nvim package is bumped. Every entry point degrades to a no-op if those modules move.

local M = {}

local function picker()
  local ok, p = pcall(require, "fff.picker_ui.picker_ui")
  if ok and p and p.state then
    return p
  end
  return nil
end

local function has_selection(state)
  return next(state.selected_files) ~= nil or next(state.selected_items) ~= nil
end

-- Cap for "mark everything"; fff's own exhaustive quickfix path uses 10000 too.
local FULL_LIMIT = 10000

-- <C-a>: mark the COMPLETE result set for the current query, not just the rows the picker has lazily paged in. The picker fetches results on demand, so marking state.filtered_items would silently drop most of a "grep a string, open all 50 hits" run; instead we re-query the full set through fff's programmatic search API and mark all of it. send_to_quickfix (<CR>) and the tab action (<C-t>) then operate on the marks, so every hit is carried through even though only a page is visible.
local function select_all()
  local p = picker()
  if not p or not p.state.active then
    return
  end

  local ok, fff = pcall(require, "fff")
  if not ok then
    return
  end

  local state = p.state
  local query = state.query or ""

  if state.mode == "grep" then
    local result = fff.content_search(query, {
      mode = state.grep_mode or "plain",
      page_size = FULL_LIMIT,
      max_matches_per_file = 0, -- unlimited per file
      time_budget_ms = 0, -- no time cap: we want every match, not a preview
    })
    for _, item in ipairs(result.items or {}) do
      if item.relative_path then
        -- Mirrors picker_ui_state.grep_item_key so send_to_quickfix recognises the marks.
        local key = string.format("%s:%d:%d", item.relative_path, item.line_number or 1, item.col or 0)
        state.selected_items[key] = item
      end
    end
  else
    local result = fff.file_search(query, { mode = "files", max_results = FULL_LIMIT })
    for _, item in ipairs(result.items or {}) do
      if item.relative_path then
        state.selected_files[item.relative_path] = true
      end
    end
  end

  p.render_list()
  pcall(function()
    p.update_status()
  end)
end

-- <CR>: open the item under the cursor, or send the marked set to the quickfix list when anything is marked (fzf-lua's file_edit_or_qf).
local function open_or_quickfix()
  local p = picker()
  if not p or not p.state.active then
    return
  end

  if has_selection(p.state) then
    p.send_to_quickfix()
  else
    p.select("edit")
  end
end

-- <C-t>: open every marked file in its own tab, or the cursor item when nothing is marked.
local function tab_selected()
  local p = picker()
  if not p or not p.state.active then
    return
  end

  local state = p.state
  if not has_selection(state) then
    p.select("tab")
    return
  end

  local ok, utils = pcall(require, "fff.utils")
  if not ok then
    return
  end

  local seen, paths = {}, {}
  local function add(relative_path)
    local absolute_path = utils.canonicalize_fff_path(relative_path)
    if absolute_path and not seen[absolute_path] then
      seen[absolute_path] = true
      table.insert(paths, absolute_path)
    end
  end

  if state.mode == "grep" then
    for _, item in pairs(state.selected_items) do
      add(item.relative_path)
    end
  else
    for relative_path in pairs(state.selected_files) do
      add(relative_path)
    end
  end
  table.sort(paths)

  p.close()
  vim.schedule(function()
    for _, absolute_path in ipairs(paths) do
      vim.cmd("tabedit " .. vim.fn.fnameescape(vim.fn.fnamemodify(absolute_path, ":.")))
    end
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("NixMeridianFffMultiSelect", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "fff_input", "fff_list" },
    callback = function(event)
      local buffer = event.buf
      local modes = vim.bo[buffer].filetype == "fff_input" and { "i", "n" } or { "n" }

      -- fff binds <CR>/<C-t> later in the same create_ui() call, after this FileType fires. Deferring past that tick lets our buffer-local maps win.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buffer) then
          return
        end

        local opts = { buffer = buffer, noremap = true, silent = true, nowait = true }
        vim.keymap.set(modes, "<CR>", open_or_quickfix, opts)
        vim.keymap.set(modes, "<C-t>", tab_selected, opts)
        vim.keymap.set(modes, "<C-a>", select_all, opts)
      end)
    end,
  })
end

return M
