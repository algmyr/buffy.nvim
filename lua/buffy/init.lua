local M = {}

local config = require "buffy.config"
local state = require "buffy.state"
local buf_provider = require "buffy.buf_provider"
local ui = require "buffy.ui"
local picker = require "buffy.picker"

--- @param opts BuffyConfig|nil
function M.setup(opts)
  config.setup(opts)
  state.set_buf_provider(buf_provider)

  local group = vim.api.nvim_create_augroup("Buffy", { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      state.init_from_cli()
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(args)
      state.remove_buffer(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local cfg = config.get()
      if cfg.auto_track then
        local bufnr = args.buf
        if
          vim.bo[bufnr].buftype == ""
          and vim.api.nvim_buf_get_name(bufnr) ~= ""
        then
          state.add_buffer(bufnr)
        end
      end
    end,
  })
end

--- Toggle the floating picker window.
function M.open_picker()
  if ui.is_open() then
    ui.close()
  else
    ui.open()
    picker.setup_keymaps()
  end
end

--- Switch to the next tracked buffer and show a peek preview.
function M.next()
  local bufnr = state.get_next()
  if bufnr then
    vim.api.nvim_set_current_buf(bufnr)
    ui.peek(bufnr)
  end
end

--- Switch to the previous tracked buffer and show a peek preview.
function M.prev()
  local bufnr = state.get_prev()
  if bufnr then
    vim.api.nvim_set_current_buf(bufnr)
    ui.peek(bufnr)
  end
end

--- Add the current buffer to the tracked list.
function M.add_current()
  local bufnr = vim.api.nvim_get_current_buf()
  if state.add_buffer(bufnr) then
    vim.notify("Buffer added to tracked list", vim.log.levels.INFO)
  else
    vim.notify("Buffer already tracked or invalid", vim.log.levels.WARN)
  end
end

--- Remove the current buffer from the tracked list.
function M.remove_current()
  local bufnr = vim.api.nvim_get_current_buf()
  if state.remove_buffer(bufnr) then
    vim.notify("Buffer removed from tracked list", vim.log.levels.INFO)
  else
    vim.notify("Buffer not in tracked list", vim.log.levels.WARN)
  end
end

return M
