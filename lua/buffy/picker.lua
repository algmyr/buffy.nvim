local M = {}

local state = require "buffy.state"
local ui = require "buffy.ui"

--- Select the currently highlighted buffer and close the picker.
function M.select()
  local bufnr = state.selected_bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    ui.close()
    vim.api.nvim_set_current_buf(bufnr)
    state.set_current(bufnr)
  end
end

--- Close the picker.
function M.close()
  ui.close()
end

function M.show_help()
  local lines = {
    "j/k     Move selection",
    "J/K     Reorder buffer",
    "<CR>/o  Select buffer",
    "a       Add buffer to tracked list",
    "d       Remove from list",
    "x       Toggle hide",
    "z       Toggle show all buffers",
    "q/Esc   Close",
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Set up buffer-local keymaps for the picker window.
function M.setup_keymaps()
  if not ui.buf or not vim.api.nvim_buf_is_valid(ui.buf) then
    return
  end

  local opts = { buffer = ui.buf, noremap = true, silent = true, nowait = true }

  vim.keymap.set("n", "<CR>", M.select, opts)
  vim.keymap.set("n", "o", M.select, opts)
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  vim.keymap.set("n", "j", "j", opts)
  vim.keymap.set("n", "k", "k", opts)

  vim.keymap.set("n", "J", function()
    if not state.is_tracked(state.selected_bufnr) then
      return
    end
    for i, b in ipairs(state.buf_list) do
      if b == state.selected_bufnr and i < #state.buf_list then
        state.move_buffer(i, i + 1)
        ui.render()
        return
      end
    end
  end, opts)
  vim.keymap.set("n", "K", function()
    if not state.is_tracked(state.selected_bufnr) then
      return
    end
    for i, b in ipairs(state.buf_list) do
      if b == state.selected_bufnr and i > 1 then
        state.move_buffer(i, i - 1)
        ui.render()
        return
      end
    end
  end, opts)

  vim.keymap.set("n", "d", function()
    if not state.is_tracked(state.selected_bufnr) then
      return
    end
    state.remove_buffer(state.selected_bufnr)
    ui.render()
  end, opts)
  vim.keymap.set("n", "x", function()
    if state.is_tracked(state.selected_bufnr) then
      state.toggle_hidden(state.selected_bufnr)
      ui.render()
    end
  end, opts)
  vim.keymap.set("n", "a", function()
    if state.selected_bufnr and not state.is_tracked(state.selected_bufnr) then
      state.add_buffer(state.selected_bufnr)
      ui.render()
    end
  end, opts)
  vim.keymap.set("n", "z", function()
    state.show_all = not state.show_all
    ui.render()
  end, opts)
  vim.keymap.set("n", "?", M.show_help, opts)
end

return M
