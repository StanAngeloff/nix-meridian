-- Show fff's pagination scrollbar as an overflow indicator on the first page too.
--
-- fff hides the scrollbar until you actually scroll to a later page: scrollbar.lua returns early while its internal "ever shown" flag is unset and page_index == 0. So a result set that overflows the visible list gives no hint that there is more below, which with a short (half-height) picker is almost always. We wrap scrollbar.render to warm that flag on page 0 of a multi-page list by rendering once as if on page 1 (which creates the window and flips the flag), then fall through to the real render so the thumb lands at the true position. Single-page results still show nothing. Pinned to fff 0.9.x's scrollbar module; the wrap degrades to a no-op if it moves.

local M = {}

function M.setup()
  local ok, scrollbar = pcall(require, "fff.scrollbar")
  if not ok or type(scrollbar.render) ~= "function" then
    return
  end

  local original_render = scrollbar.render

  scrollbar.render = function(layout, config, list_win, pagination, prompt_position)
    local page_size = pagination.page_size or 0
    local total_pages = page_size > 0 and math.ceil((pagination.total_matched or 0) / page_size) or 1

    if total_pages > 1 and (pagination.page_index or 0) == 0 then
      local warm = vim.tbl_extend("force", pagination, { page_index = 1 })
      pcall(original_render, layout, config, list_win, warm, prompt_position)
    end

    return original_render(layout, config, list_win, pagination, prompt_position)
  end
end

return M
