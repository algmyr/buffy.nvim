local M = {}

--- Thin abstraction over vim.api for buffer queries, enabling mocking in tests.

--- Return a list of all open buffer handles.
--- @return integer[]
function M.get_all_bufs()
  return vim.api.nvim_list_bufs()
end

--- Check whether a buffer handle refers to a live buffer.
--- @param bufnr integer
--- @return boolean
function M.is_valid(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr)
end

--- Return the full file path associated with a buffer.
--- @param bufnr integer
--- @return string
function M.get_name(bufnr)
  return vim.api.nvim_buf_get_name(bufnr)
end

--- Return the buftype option for a buffer.
--- @param bufnr integer
--- @return string
function M.get_buftype(bufnr)
  return vim.bo[bufnr].buftype
end

--- Return the currently focused buffer handle.
--- @return integer
function M.get_current_buf()
  return vim.api.nvim_get_current_buf()
end

--- Switch focus to the given buffer handle.
--- @param bufnr integer
function M.set_current_buf(bufnr)
  vim.api.nvim_set_current_buf(bufnr)
end

return M
