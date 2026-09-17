local M = {}

local _ = require "buffy.types"

--- Return name relative to directory when it is contained by that directory.
--- @param name string
--- @param directory string
--- @param prefix string
--- @return string|nil
local function _relative_to(name, directory, prefix)
  if name == directory then
    return ""
  end

  if directory == "/" then
    if name:sub(1, 1) == "/" then
      return name:sub(2)
    end
    return nil
  end

  local path_prefix = directory .. "/"
  if name:sub(1, #path_prefix) == path_prefix then
    return prefix .. name:sub(#path_prefix + 1)
  end
end

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
  local path = _relative_to(name, cwd, "")
  if path then
    return filename, path
  end

  local home = vim.fn.expand "~"
  path = _relative_to(name, home, "~/")
  if path then
    return filename, path
  end

  return filename, name
end

--- File-type icon component from nvim-web-devicons.
--- @param bufnr integer
--- @param ctx BuffyContext
--- @return BuffyComponent?
function M.icon(bufnr, _ctx)
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
function M.path(bufnr, _ctx)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local _, path = _get_name_parts(name)
  local max_path = 60
  if #path > max_path then
    path = path:sub(1, max_path - 3) .. "…"
  end
  return { text = path, hl = "BuffyPath" }
end

return M
