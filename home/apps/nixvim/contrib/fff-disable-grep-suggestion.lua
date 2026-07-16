-- Disable fff's live-grep -> filename "suggestion" fallback.
--
-- When a live grep returns no content matches, fff silently runs a filename search instead and shows those files as a suggestion (search_manager.lua), turning "no matches" into a surprise switch to file mode. We drop it so a live grep with no matches simply shows "No results".
--
-- We wrap file_picker.search_files_paginated: in live grep the only caller of it is that no-match suggestion (the grep results themselves come from grep_renderer), so returning an empty list when the picker is in grep mode removes the suggestion. The normal file picker (state.mode is nil) is passed straight through, untouched. Pinned to fff 0.9.x's picker internals; degrades to a no-op if they move.

local M = {}

function M.setup()
  local ok_state, picker_ui_state = pcall(require, "fff.picker_ui.picker_ui_state")
  local ok_fp, file_picker = pcall(require, "fff.file_picker")
  if not ok_state or not ok_fp or type(file_picker.search_files_paginated) ~= "function" then
    return
  end

  local original = file_picker.search_files_paginated

  file_picker.search_files_paginated = function(query, ...)
    -- In live grep the only caller is the no-match "suggest filenames" fallback; drop it so a
    -- grep with no content matches shows "No results" instead of switching to a filename search.
    if picker_ui_state.state and picker_ui_state.state.mode == "grep" then
      return {}
    end
    return original(query, ...)
  end
end

return M
