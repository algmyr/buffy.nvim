local M = {}

local state = require "buffy.state"
local _ = require "buffy.types"
local config = require "buffy.config"
local compose = require "buffy.compose"

--- @type integer|nil
M.buf = nil

--- @type integer|nil
M.win = nil

--- @type string[]
M.lines = {}

--- @type (integer|nil)[]
M.buf_map = {}

--- @type BuffyHighlight[][]
M.entry_highlights = {}

--- @type string|nil
M.saved_guicursor = nil

--- @type integer|nil
M.autocmd = nil
M.label_map = {}

--- @type integer|nil
M.peek_buf = nil
--- @type integer|nil
M.peek_win = nil
--- @type uv_timer_t|nil
M.peek_timer = nil

--- Return true if the picker window is open and valid.
--- @return boolean
function M.is_open()
  return M.win ~= nil and vim.api.nvim_win_is_valid(M.win)
end

--- Tear down the picker window, buffer, and autocmds.
function M.close()
  state.quickpick = false
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

--- Build a context table for a buffer.
--- @param bufnr integer
--- @return BuffyContext
local function _make_ctx(bufnr)
  return {
    is_untracked = state.show_all and not state.is_tracked(bufnr),
  }
end

--- Populate M.lines, M.buf_map, and M.entry_highlights from current state.
function M.populate_lines()
  local cfg = config.get()

  M.lines = {}
  M.buf_map = {}
  M.entry_highlights = {}
  --- @type table<string, integer>
  M.label_map = {}

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

  local label_idx = 1
  for _, bufnr in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local ctx = _make_ctx(bufnr)
      local spec = { unpack(cfg.layout) }

      local label = nil
      local quickpick_chars = cfg.quickpick_chars
      if state.quickpick and label_idx <= #quickpick_chars then
        label = quickpick_chars:sub(label_idx, label_idx)
        M.label_map[label] = bufnr
        table.insert(
          spec,
          1,
          { text = label .. ": ", hl = { "BuffyLabel", 300 } }
        )
        label_idx = label_idx + 1
      end

      local components = compose.evaluate(spec, bufnr, ctx)
      local text, highlights = compose.compose(components)

      table.insert(M.lines, text)
      table.insert(M.buf_map, bufnr)
      table.insert(M.entry_highlights, highlights)
    end
  end

  if #M.lines == 0 then
    table.insert(M.lines, "No tracked buffers")
    table.insert(M.buf_map, nil)
    table.insert(M.entry_highlights, {})
  end
end

--- Apply highlight extmarks to a buffer.
--- @param buf integer Buffer handle.
--- @param line_idx number Line index (0-based).
--- @param highlights BuffyHighlight[] Highlight ranges for the line.
--- @param ns integer Namespace id.
local function _apply_line_highlights(buf, line_idx, highlights, ns)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, ns, line_idx, h.col, {
      end_col = h.end_col,
      hl_group = h.hl,
      priority = h.priority,
    })
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

  local ns_icons = vim.api.nvim_create_namespace "buffy_icons"
  local ns_select = vim.api.nvim_create_namespace "buffy_selection"
  vim.api.nvim_buf_clear_namespace(M.buf, ns_icons, 0, -1)
  vim.api.nvim_buf_clear_namespace(M.buf, ns_select, 0, -1)

  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, M.lines)
  vim.bo[M.buf].modifiable = false

  for line_idx, highlights in ipairs(M.entry_highlights) do
    _apply_line_highlights(M.buf, line_idx - 1, highlights, ns_icons)
  end

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
  for line_idx, highlights in ipairs(M.entry_highlights) do
    _apply_line_highlights(M.buf, line_idx - 1, highlights, ns)
  end

  vim.wo[M.win].wrap = false
  vim.wo[M.win].winfixbuf = true

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
  local visible = state.get_visible()
  if #visible == 0 then
    M.peek_close()
    return
  end

  if M.peek_timer then
    M.peek_timer:stop()
  end

  local cfg = config.get()
  local lines = {}
  local all_highlights = {}
  local current_line = 1

  for i, bufnr in ipairs(visible) do
    local ctx = _make_ctx(bufnr)
    local components = compose.evaluate(cfg.layout, bufnr, ctx)
    local text, highlights = compose.compose(components)
    table.insert(lines, text)
    table.insert(all_highlights, highlights)
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
  vim.api.nvim_buf_clear_namespace(M.peek_buf, ns, 0, -1)
  for line_idx, highlights in ipairs(all_highlights) do
    _apply_line_highlights(M.peek_buf, line_idx - 1, highlights, ns)
  end

  local win_config = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
  }
  if cfg.peek.border ~= "none" then
    win_config.border = _resolve_border(cfg.peek.border)
  end
  if M.peek_win and vim.api.nvim_win_is_valid(M.peek_win) then
    vim.api.nvim_win_set_config(M.peek_win, win_config)
  else
    win_config.style = "minimal"
    win_config.focusable = false
    M.peek_win = vim.api.nvim_open_win(M.peek_buf, false, win_config)
  end

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
