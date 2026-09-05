local M = {}

local state = require "buffy.state"
local utils = require "buffy.utils"
local config = require "buffy.config"

--- @type integer|nil
M.buf = nil

--- @type integer|nil
M.win = nil

--- @type string[]
M.lines = {}

--- @type (integer|nil)[]
M.buf_map = {}

--- @type BuffyIconInfo[]
M.icon_highlights = {}

--- @type string|nil
M.saved_guicursor = nil

--- @type integer|nil
M.autocmd = nil

--- @type integer|nil
M.peek_buf = nil
--- @type integer|nil
M.peek_win = nil
--- @type uv_timer_t|nil
M.peek_timer = nil

--- @class BuffyIconInfo
--- @field hl string|nil Highlight group for the icon.
--- @field len number Byte length of the icon string.
--- @field path_start number|nil Byte offset where the path portion begins.

--- Return true if the picker window is open and valid.
--- @return boolean
function M.is_open()
  return M.win ~= nil and vim.api.nvim_win_is_valid(M.win)
end

--- Tear down the picker window, buffer, and autocmds.
function M.close()
  if M.autocmd then
    vim.api.nvim_del_autocmd(M.autocmd)
    M.autocmd = nil
  end
  if M.selection_autocmd then
    vim.api.nvim_del_autocmd(M.selection_autocmd)
    M.selection_autocmd = nil
  end
  if M.saved_guicursor then
    vim.o.guicursor = M.saved_guicursor
    M.saved_guicursor = nil
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
  end
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
    M.buf = nil
  end
end

--- Populate M.lines, M.buf_map, and M.icon_highlights from current state.
function M.populate_lines()
  local cfg = config.get()

  M.lines = {}
  M.buf_map = {}
  M.icon_highlights = {}

  local bufs
  if state.show_all then
    local tracked = state.get_all()
    local all = state.get_system_bufs()
    local tracked_set = {}
    for _, b in ipairs(tracked) do
      tracked_set[b] = true
    end
    bufs = {}
    for _, b in ipairs(tracked) do
      table.insert(bufs, b)
    end
    for _, b in ipairs(all) do
      if not tracked_set[b] then
        table.insert(bufs, b)
      end
    end
  else
    bufs = state.get_all()
  end

  for _, bufnr in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local markers = ""
      if state.is_hidden(bufnr) then
        markers = markers .. "H"
      end
      if state.show_all and not state.is_tracked(bufnr) then
        markers = markers .. "-"
      end
      local entry = utils.get_entry_display(bufnr, cfg, markers)
      table.insert(M.lines, entry.text)
      table.insert(M.buf_map, bufnr)
      table.insert(M.icon_highlights, {
        hl = entry.icon_hl,
        len = entry.icon_len,
        path_start = entry.path_start,
      })
    end
  end

  if #M.lines == 0 then
    table.insert(M.lines, "No tracked buffers")
    table.insert(M.buf_map, nil)
    table.insert(M.icon_highlights, { hl = nil, len = 0 })
  end
end

--- Apply icon and path extmark highlights to a buffer.
--- @param buf integer Buffer handle.
--- @param lines string[] Lines displayed in the buffer.
--- @param highlights BuffyIconInfo[] Per-line highlight info.
--- @param ns integer Namespace id.
function M.apply_highlights(buf, lines, highlights, ns)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for line_idx, info in ipairs(highlights) do
    if info.hl and info.len > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, line_idx - 1, 0, {
        end_col = info.len,
        hl_group = info.hl,
        priority = 200,
      })
    end
    if info.path_start then
      local line_len = #lines[line_idx]
      if info.path_start < line_len then
        vim.api.nvim_buf_set_extmark(buf, ns, line_idx - 1, info.path_start, {
          end_col = line_len,
          hl_group = "BuffyPath",
          priority = 100,
        })
      end
    end
  end
end

local border_presets = {
  horizontal = { "─", "─", "─", " ", "─", "─", "─", " " },
  vertical = { " ", " ", " ", "│", " ", " ", " ", "│" },
}

local function _resolve_border(border)
  if type(border) == "string" then
    return border_presets[border] or border
  end
  return border
end

local function _compute_win_position(width, height, position, border)
  local border_h = border ~= "none" and 2 or 0
  local border_w = border ~= "none" and 2 or 0

  local col = math.floor((vim.o.columns - width - border_w) / 2)

  local row
  if position == "center" then
    row = math.floor((vim.o.lines - height - border_h) / 2)
  elseif position == "bottom" then
    row = vim.o.lines - height - border_h - 2
  else
    row = 0
  end

  return row, col
end

--- Refresh the buffer contents and highlights for an already-open picker.
function M.render()
  if not M.is_open() or not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    return
  end

  M.populate_lines()

  local new_height = M.get_height()
  local cur_height = vim.api.nvim_win_get_height(M.win)
  if new_height ~= cur_height then
    vim.api.nvim_win_set_height(M.win, new_height)
  end

  local ns = vim.api.nvim_create_namespace "buffy_icons"
  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, M.lines)
  vim.bo[M.buf].modifiable = false

  M.apply_highlights(M.buf, M.lines, M.icon_highlights, ns)
  M.update_selection()
end

--- Move the cursor and highlight to the currently-selected line.
function M.update_selection()
  if not M.is_open() then
    return
  end

  local ns = vim.api.nvim_create_namespace "buffy_selection"
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)

  local cursor = vim.api.nvim_win_get_cursor(M.win)
  local display_idx = cursor[1]
  if display_idx >= 1 and display_idx <= #M.buf_map then
    vim.api.nvim_buf_add_highlight(
      M.buf,
      ns,
      "BuffySelected",
      display_idx - 1,
      0,
      -1
    )
    state.selected_bufnr = M.buf_map[display_idx]
  end
end

--- Compute the clamped window height.
--- @return integer
function M.get_height()
  local cfg = config.get()
  local height = #M.lines
  height = math.max(height, 1)
  height = math.min(height, cfg.max_height)
  return height
end

--- Open the floating picker window.
function M.open()
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden = "wipe"
  vim.bo[M.buf].buftype = "nofile"
  vim.bo[M.buf].swapfile = false

  M.populate_lines()

  local height = M.get_height()
  local width = vim.o.columns
  local cfg = config.get()

  local row, col =
    _compute_win_position(width, height, cfg.picker.position, cfg.picker.border)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
  }

  if cfg.picker.border ~= "none" then
    win_opts.border = _resolve_border(cfg.picker.border)
  end

  M.win = vim.api.nvim_open_win(M.buf, true, win_opts)

  M.saved_guicursor = vim.o.guicursor
  vim.o.guicursor = "a:ver1"

  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, M.lines)
  vim.bo[M.buf].modifiable = false

  local ns = vim.api.nvim_create_namespace "buffy_icons"
  M.apply_highlights(M.buf, M.lines, M.icon_highlights, ns)

  vim.wo[M.win].wrap = false
  vim.wo[M.win].winfixbuf = true

  local sign_bg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg or "#242424"
  vim.api.nvim_set_hl(0, "BuffyFloat", { bg = sign_bg, fg = "#d4d4d4" })
  vim.api.nvim_set_hl(0, "BuffyPath", { fg = "#666666" })
  vim.api.nvim_set_hl(0, "BuffySelected", { bold = true })
  vim.wo[M.win].winhighlight = "Normal:BuffyFloat"

  local win = M.win
  M.selection_autocmd = vim.api.nvim_create_autocmd("CursorMoved", {
    callback = function()
      if M.is_open() and M.win and vim.api.nvim_win_is_valid(win) then
        M.update_selection()
      end
    end,
  })
  M.autocmd = vim.api.nvim_create_autocmd("WinEnter", {
    callback = function()
      if vim.api.nvim_get_current_win() ~= win then
        vim.schedule(function()
          if M.win and vim.api.nvim_win_is_valid(win) then
            M.close()
          end
        end)
      end
    end,
  })

  M.update_selection()
end

--- Close the peek window and cancel its timer.
function M.peek_close()
  if M.peek_timer then
    M.peek_timer:stop()
    M.peek_timer = nil
  end
  if M.peek_win and vim.api.nvim_win_is_valid(M.peek_win) then
    vim.api.nvim_win_close(M.peek_win, true)
    M.peek_win = nil
  end
end

--- Show a temporary floating preview of the visible buffer list, highlighting
--- current_bufnr. The window auto-closes after a short delay.
--- @param current_bufnr integer
function M.peek(current_bufnr)
  if M.peek_timer then
    M.peek_timer:stop()
  end

  local visible = state.get_visible()
  if #visible == 0 then
    return
  end

  local cfg = config.get()
  local lines = {}
  local highlights = {}
  local current_line = 1

  for i, bufnr in ipairs(visible) do
    local entry = utils.get_entry_display(bufnr, cfg)
    table.insert(lines, entry.text)
    table.insert(highlights, {
      hl = entry.icon_hl,
      len = entry.icon_len,
      path_start = entry.path_start,
    })
    if bufnr == current_bufnr then
      current_line = i
    end
  end

  local max_width = 0
  for _, line in ipairs(lines) do
    if #line > max_width then
      max_width = #line
    end
  end

  local width = math.min(max_width + 2, vim.o.columns - 4)
  local height = math.min(#lines, cfg.max_height)

  local row, col =
    _compute_win_position(width, height, cfg.peek.position, cfg.peek.border)

  if not M.peek_buf or not vim.api.nvim_buf_is_valid(M.peek_buf) then
    M.peek_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.peek_buf].bufhidden = "wipe"
    vim.bo[M.peek_buf].buftype = "nofile"
    vim.bo[M.peek_buf].swapfile = false
  end

  vim.bo[M.peek_buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.peek_buf, 0, -1, false, lines)
  vim.bo[M.peek_buf].modifiable = false

  local ns = vim.api.nvim_create_namespace "buffy_peek"
  M.apply_highlights(M.peek_buf, lines, highlights, ns)

  if M.peek_win and vim.api.nvim_win_is_valid(M.peek_win) then
    local reconfig = {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
    }
    if cfg.peek.border ~= "none" then
      reconfig.border = _resolve_border(cfg.peek.border)
    end
    vim.api.nvim_win_set_config(M.peek_win, reconfig)
  else
    local peek_opts = {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      focusable = false,
    }
    if cfg.peek.border ~= "none" then
      peek_opts.border = _resolve_border(cfg.peek.border)
    end
    M.peek_win = vim.api.nvim_open_win(M.peek_buf, false, peek_opts)
  end

  local sign_bg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg or "#242424"
  vim.api.nvim_set_hl(0, "BuffyPeek", { bg = sign_bg, fg = "#d4d4d4" })
  vim.wo[M.peek_win].winhighlight = "Normal:BuffyPeek"

  vim.api.nvim_buf_add_highlight(
    M.peek_buf,
    ns,
    "BuffySelected",
    current_line - 1,
    0,
    -1
  )

  M.peek_timer = vim.defer_fn(function()
    M.peek_close()
  end, 1500)
end

return M
