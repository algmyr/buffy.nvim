local M = {}

local _ = require "buffy.types"

--- Return both the tail filename and relative path for a buffer, fetching the
--- name only once.
--- @param name string
--- @return string, string
local function _get_name_parts(name)
  if name == "" then
    return "[No Name]", "[No Name]"
  end

  local filename = vim.fn.fnamemodify(name, ":t")

  local cwd = vim.fn.getcwd()
  if name:sub(1, #cwd) == cwd then
    return filename, name:sub(#cwd + 2)
  end

  local home = vim.fn.expand "~"
  if name:sub(1, #home) == home then
    return filename, "~/" .. name:sub(#home + 2)
  end

  return filename, name
end

--- File-type icon component from nvim-web-devicons.
--- @param bufnr integer
--- @param ctx BuffyContext
--- @return BuffyComponent?
function M.icon(bufnr, ctx)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  local filename = vim.fn.fnamemodify(name, ":t")
  local ext = vim.fn.fnamemodify(name, ":e")
  local icon, hl = devicons.get_icon(filename, ext, { default = true })
  if not icon or icon == "" then
    return nil
  end
  return { text = icon .. " ", hl = hl }
end

--- Tail filename, wrapped in parentheses if untracked.
--- @param bufnr integer
--- @param ctx BuffyContext
--- @return BuffyComponent?
function M.filename(bufnr, ctx)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local filename, _ = _get_name_parts(name)
  if ctx.is_untracked then
    filename = "(" .. filename .. ")"
  end
  return { text = filename }
end

--- Buffer state markers: [H] hidden, [+] modified, [=] readonly.
--- @param bufnr integer
--- @param ctx BuffyContext
--- @return BuffyComponent?
function M.markers(bufnr, ctx)
  local marks = ""
  if ctx.is_hidden then
    marks = marks .. "H"
  end
  if vim.bo[bufnr].modified then
    marks = marks .. "+"
  end
  if vim.bo[bufnr].readonly or not vim.bo[bufnr].modifiable then
    marks = marks .. "="
  end
  if #marks == 0 then
    return nil
  end
  return { text = " [" .. marks .. "]" }
end

--- Relative path, truncated and dimmed.
--- @param bufnr integer
--- @param ctx BuffyContext
--- @return BuffyComponent?
function M.path(bufnr, ctx)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local _, path = _get_name_parts(name)
  local max_path = 60
  if #path > max_path then
    path = path:sub(1, max_path - 3) .. "…"
  end
  return { text = path, hl = "BuffyPath" }
end

return M
