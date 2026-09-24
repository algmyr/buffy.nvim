local M = {}

local _ = require "buffy.types"

--- Ordered list of tracked buffer handles.
--- @type integer[]
M.buf_list = {}

--- Set of buffer handles explicitly untracked by the user via the picker.
--- Prevents auto_track from re-adding them on BufEnter.
--- @type table<integer, boolean>
M.explicitly_untracked = {}

--- Index into buf_list for next/prev cycling.
--- @type integer
M.current_idx = 1

--- Buffer handle shown as selected in the picker, or nil.
--- @type integer|nil
M.selected_bufnr = nil

--- When true the picker also shows untracked buffers.
--- @type boolean
M.show_all = true
M.quickpick = false

--- Provider used for vim.api queries (injected for testing).
--- @type BufProvider|nil
M.buf_provider = nil

--- Inject a buffer provider for vim.api calls.
--- @param buf_provider BufProvider
function M.set_buf_provider(buf_provider)
  M.buf_provider = buf_provider
end

--- Add a buffer to the tracked list. Returns true on success.
--- @param bufnr integer
--- @return boolean
function M.add_buffer(bufnr)
  if M.buf_provider and not M.buf_provider.is_valid(bufnr) then
    return false
  end

  for _, b in ipairs(M.buf_list) do
    if b == bufnr then
      return false
    end
  end

  table.insert(M.buf_list, bufnr)
  return true
end

--- Remove a buffer from the tracked list. Returns true if it was present.
--- @param bufnr integer
--- @return boolean
function M.remove_buffer(bufnr)
  for i, b in ipairs(M.buf_list) do
    if b == bufnr then
      table.remove(M.buf_list, i)
      if i < M.current_idx then
        M.current_idx = M.current_idx - 1
      elseif M.current_idx > #M.buf_list then
        M.current_idx = math.max(1, #M.buf_list)
      end
      if M.selected_bufnr == bufnr then
        if #M.buf_list == 0 then
          M.selected_bufnr = nil
        else
          M.selected_bufnr = M.buf_list[math.min(i, #M.buf_list)]
        end
      end
      return true
    end
  end
  return false
end

--- Add a buffer after clearing an explicit user removal. Returns true on success.
--- @param bufnr integer
--- @return boolean
function M.track_buffer(bufnr)
  if not M.add_buffer(bufnr) then
    return false
  end
  M.unmark_untracked(bufnr)
  return true
end

--- Remove a buffer and prevent auto-tracking from restoring it. Returns true on success.
--- @param bufnr integer
--- @return boolean
function M.untrack_buffer(bufnr)
  if not M.remove_buffer(bufnr) then
    return false
  end
  M.mark_untracked(bufnr)
  return true
end

--- Flip tracked membership for a buffer. Returns true on success.
--- @param bufnr integer
--- @return boolean
function M.toggle_tracked(bufnr)
  if M.is_tracked(bufnr) then
    return M.untrack_buffer(bufnr)
  end
  return M.track_buffer(bufnr)
end

--- Return the next valid buffer, wrapping around.
--- @return integer|nil
function M.get_next()
  if #M.buf_list == 0 then
    return nil
  end

  local start = M.current_idx
  repeat
    M.current_idx = M.current_idx % #M.buf_list + 1
    local bufnr = M.buf_list[M.current_idx]
    if not M.buf_provider or M.buf_provider.is_valid(bufnr) then
      return bufnr
    end
  until M.current_idx == start

  return nil
end

--- Return the previous valid buffer, wrapping around.
--- @return integer|nil
function M.get_prev()
  if #M.buf_list == 0 then
    return nil
  end

  local start = M.current_idx
  repeat
    M.current_idx = (M.current_idx - 2) % #M.buf_list + 1
    local bufnr = M.buf_list[M.current_idx]
    if not M.buf_provider or M.buf_provider.is_valid(bufnr) then
      return bufnr
    end
  until M.current_idx == start

  return nil
end

--- Move the cursor index to the entry matching bufnr.
--- @param bufnr integer
--- @return boolean
function M.set_current(bufnr)
  for i, b in ipairs(M.buf_list) do
    if b == bufnr then
      M.current_idx = i
      return true
    end
  end
  return false
end

--- Move a buffer from one position to another in the tracked list.
--- @param from_idx integer
--- @param to_idx integer
--- @return boolean
function M.move_buffer(from_idx, to_idx)
  if from_idx < 1 or from_idx > #M.buf_list then
    return false
  end
  if to_idx < 1 or to_idx > #M.buf_list then
    return false
  end

  local bufnr = table.remove(M.buf_list, from_idx)
  table.insert(M.buf_list, to_idx, bufnr)

  if M.current_idx == from_idx then
    M.current_idx = to_idx
  elseif from_idx < M.current_idx and to_idx >= M.current_idx then
    M.current_idx = M.current_idx - 1
  elseif from_idx > M.current_idx and to_idx <= M.current_idx then
    M.current_idx = M.current_idx + 1
  end

  return true
end

--- Mark a buffer as explicitly untracked so auto_track will skip it.
--- @param bufnr integer
function M.mark_untracked(bufnr)
  M.explicitly_untracked[bufnr] = true
end

--- Remove the explicit-untrack mark from a buffer.
--- @param bufnr integer
function M.unmark_untracked(bufnr)
  M.explicitly_untracked[bufnr] = nil
end

--- Return true if the buffer was explicitly untracked by the user.
--- @param bufnr integer
--- @return boolean
function M.is_explicitly_untracked(bufnr)
  return M.explicitly_untracked[bufnr] == true
end

--- Return true if the buffer is in the tracked list.
--- @param bufnr integer
--- @return boolean
function M.is_tracked(bufnr)
  for _, b in ipairs(M.buf_list) do
    if b == bufnr then
      return true
    end
  end
  return false
end

--- Return tracked buffers that are valid.
--- @return integer[]
function M.get_visible()
  local visible = {}
  for _, bufnr in ipairs(M.buf_list) do
    if not M.buf_provider or M.buf_provider.is_valid(bufnr) then
      table.insert(visible, bufnr)
    end
  end
  return visible
end

--- Return the raw tracked list.
--- @return integer[]
function M.get_all()
  return M.buf_list
end

--- Return true if the buffer is a listed, normal file buffer worth tracking.
--- @param bufnr integer
--- @return boolean
local function _is_ok_buffer(bufnr)
  if not M.buf_provider or not M.buf_provider.is_valid(bufnr) then
    return false
  end
  if not M.buf_provider.is_listed(bufnr) then
    return false
  end
  local name = M.buf_provider.get_name(bufnr)
  local bt = M.buf_provider.get_buftype(bufnr)
  return name ~= ""
    and not name:match "^%w+://"
    and not name:match "^%["
    and bt == ""
end

--- Return all listed system buffers that are valid, non-empty, non-protocol, and normal.
--- @return integer[]
function M.get_system_bufs()
  if not M.buf_provider then
    return {}
  end

  local result = {}
  for _, bufnr in ipairs(M.buf_provider.get_all_bufs()) do
    if _is_ok_buffer(bufnr) then
      table.insert(result, bufnr)
    end
  end
  return result
end

--- Seed the tracked list from buffers that were opened on the command line.
function M.init_from_cli()
  if not M.buf_provider then
    return
  end

  for _, bufnr in ipairs(M.buf_provider.get_all_bufs()) do
    if _is_ok_buffer(bufnr) then
      M.add_buffer(bufnr)
    end
  end

  if #M.buf_list > 0 then
    M.set_current(M.buf_provider.get_current_buf())
    M.selected_bufnr = M.buf_provider.get_current_buf()
  end
end

--- Reset all state to initial values.
function M.clear()
  M.buf_list = {}
  M.explicitly_untracked = {}
  M.current_idx = 1
  M.selected_bufnr = nil
  M.show_all = true
  M.quickpick = false
end

return M
