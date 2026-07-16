-- Blank fff's live-grep empty state instead of its "Start typing..." help banner.
--
-- When a live grep has no results, fff fills the list with a "Start typing to search file contents..." banner plus a few usage tips (renderer.lua render_grep_empty_state). We replace that with a blank list -- the way fzf showed nothing until you typed.
--
-- renderer.render_list draws that banner only on one path: the picker is a live grep with zero items (its items come from state.filtered_items). We detect exactly that case and do the same buffer and state reset the empty branch does, minus the help lines; every other render defers to the original. state is shared (picker_ui.state is picker_ui_state.state), so one reference has active/mode/filtered_items/list_buf/ns_id. Pinned to fff 0.9.x's renderer; degrades to a no-op if it moves.

local M = {}

function M.setup()
  local ok_renderer, renderer = pcall(require, "fff.picker_ui.renderer")
  local ok_state, picker_ui_state = pcall(require, "fff.picker_ui.picker_ui_state")
  local ok_separator, list_separator = pcall(require, "fff.list_separator")
  if not ok_renderer or not ok_state or type(renderer.render_list) ~= "function" then
    return
  end

  local state = picker_ui_state.state
  local original = renderer.render_list

  renderer.render_list = function(...)
    if
      state.active
      and state.mode == "grep"
      and #(state.filtered_items or {}) == 0
      and state.list_buf
      and vim.api.nvim_buf_is_valid(state.list_buf)
    then
      if ok_separator then
        pcall(list_separator.hide)
      end
      state.line_to_item = {}
      state.item_to_lines = {}
      state.last_render_ctx = nil
      vim.api.nvim_set_option_value("modifiable", true, { buf = state.list_buf })
      vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, {})
      vim.api.nvim_set_option_value("modifiable", false, { buf = state.list_buf })
      vim.api.nvim_buf_clear_namespace(state.list_buf, state.ns_id, 0, -1)
      return
    end
    return original(...)
  end
end

return M
