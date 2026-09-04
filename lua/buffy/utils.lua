local M = {}

--- Return the file-type icon and highlight group for a buffer.
--- @param bufnr integer
--- @return string, string|nil
function M.get_icon(bufnr)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then
    return "", nil
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return "", nil
  end

  local filename = vim.fn.fnamemodify(name, ":t")
  local ext = vim.fn.fnamemodify(name, ":e")
  local icon, hl_group = devicons.get_icon(filename, ext, { default = true })
  return icon or "", hl_group
end

--- Return true if the buffer has unsaved changes.
--- @param bufnr integer
--- @return boolean
function M.is_modified(bufnr)
  return vim.bo[bufnr].modified
end

--- Return the tail filename for a buffer.
--- @param bufnr integer
--- @return string
function M.get_filename(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return "[No Name]"
  end
  return vim.fn.fnamemodify(name, ":t")
end

--- Return a short, human-friendly path for a buffer.
--- @param bufnr integer
--- @return string
function M.get_relative_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return "[No Name]"
  end

  local cwd = vim.fn.getcwd()
  if name:sub(1, #cwd) == cwd then
    return name:sub(#cwd + 2)
  end

  local home = vim.fn.expand "~"
  if name:sub(1, #home) == home then
    return "~/" .. name:sub(#home + 2)
  end

  return name
end

--- @class BuffyDisplayResult
--- @field text string The formatted line to display.
--- @field icon_hl string|nil The highlight group for the icon.
--- @field icon_len number Byte length of the icon string.
--- @field path_start number|nil Byte offset where the path portion begins.

--- Build the display string for a buffer entry.
--- @param bufnr integer
--- @param config BuffyConfig
--- @return BuffyDisplayResult
function M.get_entry_display(bufnr, config)
  local parts = {}
  local icon_hl = nil
  local icon_len = 0

  if config.icons then
    local icon, hl = M.get_icon(bufnr)
    if icon ~= "" then
      table.insert(parts, icon .. " ")
      icon_hl = hl
      icon_len = #icon + 1
    end
  end

  local filename = M.get_filename(bufnr)
  local path = M.get_relative_path(bufnr)

  local max_path = 60
  if #path > max_path then
    path = path:sub(1, max_path - 3) .. "…"
  end

  local path_start = icon_len + #filename + 2
  table.insert(parts, filename .. "  " .. path)

  if M.is_modified(bufnr) then
    table.insert(parts, " [+]")
  end

  return {
    text = table.concat(parts),
    icon_hl = icon_hl,
    icon_len = icon_len,
    path_start = path_start,
  }
end

return M
