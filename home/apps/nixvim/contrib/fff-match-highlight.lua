-- Highlight the query match in the file picker case-insensitively, the way grep already does.
--
-- fff's file_renderer highlights the query only where it occurs as an exact-case contiguous substring: file_renderer.lua does string.find(line, query, 1, true), which is case-sensitive. So with smart_case on (case-insensitive while the query has no uppercase), searching "file" matches "FILENAME" but leaves the "FILE" unhighlighted, because the case-sensitive find returns nothing. Grep mode has no such gap: it highlights from the Rust core's match_ranges, which were computed with smart_case.
--
-- We wrap apply_highlights and, once the original has run, fill that gap: when the query folds under smart_case (all-lowercase) and the original found no exact-case occurrence to highlight, we run a case-folded string.find and draw the same 'matched' highlight over that range. string.lower touches only ASCII and preserves byte length, so the offsets stay valid for the (byte-based) extmark on the untouched line. Additive and leaves exactly one highlight per line: exact-case and mixed-case queries are handled entirely by the original, so we only ever add a mark the renderer skipped.
--
-- Pinned to fff 0.9.x's file_renderer; degrades to a no-op if the module or its apply_highlights move.

local M = {}

function M.setup()
  local ok, file_renderer = pcall(require, "fff.picker_ui.file_renderer")
  if not ok or type(file_renderer.apply_highlights) ~= "function" then
    return
  end

  local original = file_renderer.apply_highlights

  file_renderer.apply_highlights = function(item, ctx, item_idx, buf, ns_id, line_idx, line_content)
    original(item, ctx, item_idx, buf, ns_id, line_idx, line_content)

    local query = ctx and ctx.query
    if not query or query == "" then
      return
    end

    -- Only fold case when smart_case would: a query with any uppercase stays case-sensitive,
    -- and the original already highlighted its exact-case hit.
    if query ~= query:lower() then
      return
    end

    -- The original drew the highlight when an exact-case occurrence exists; only step in for the
    -- case-differs gap (e.g. "file" against "FILENAME"), so we never double-mark a line.
    if string.find(line_content, query, 1, true) then
      return
    end

    local match_start, match_end = string.find(line_content:lower(), query, 1, true)
    if match_start and match_end then
      local matched_hl = ctx.config and ctx.config.hl and ctx.config.hl.matched or "IncSearch"
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx - 1, match_start - 1, {
        end_col = match_end,
        hl_group = matched_hl,
      })
    end
  end
end

return M
