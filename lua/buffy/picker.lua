local M = {}

local state = require "buffy.state"
local ui = require "buffy.ui"
local config = require "buffy.config"

local function _try_select_buf(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    M.close()
    vim.api.nvim_set_current_buf(bufnr)
    state.set_current(bufnr)
  end
end

--- Select the currently highlighted buffer and close the picker.
function M.select()
  _try_select_buf(state.selected_bufnr)
end

function M.select_label(label)
  _try_select_buf(ui.label_map[label])
end

function M.toggle_quickpick()
  state.quickpick = not state.quickpick
  ui.render()
end

function M.exit_quickpick()
  if state.quickpick then
    state.quickpick = false
    ui.render()
  end
end

--- Close the picker.
function M.close()
  ui.close()
end

function M.show_help()
  local lines = {
    "j/k       Move selection",
    "J/K       Reorder buffer",
    "<CR>      Select buffer",
    "<Space>   Quick-pick mode",
    "a         Add buffer to tracked list",
    "d         Remove from list",
    "D         Close buffer",
    "x         Toggle hide",
    "z         Toggle show all buffers",
    "Esc       Close",
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
  vim.keymap.set("n", "<Esc>", function()
    if state.quickpick then
      M.exit_quickpick()
    else
      M.close()
    end
  end, opts)
  vim.keymap.set("n", "<Space>", M.toggle_quickpick, opts)

  vim.keymap.set("n", "j", function()
    M.exit_quickpick()
    vim.api.nvim_feedkeys("j", "n", false)
  end, opts)
  vim.keymap.set("n", "k", function()
    M.exit_quickpick()
    vim.api.nvim_feedkeys("k", "n", false)
  end, opts)
  vim.keymap.set("n", "<Down>", function()
    M.exit_quickpick()
    vim.api.nvim_feedkeys("<Down>", "n", false)
  end, opts)
  vim.keymap.set("n", "<Up>", function()
    M.exit_quickpick()
    vim.api.nvim_feedkeys("<Up>", "n", false)
  end, opts)

  local quickpick_chars = config.get().quickpick_chars
  for i = 1, #quickpick_chars do
    local char = quickpick_chars:sub(i, i)
    vim.keymap.set("n", char, function()
      if state.quickpick then
        M.select_label(char)
      else
        vim.api.nvim_feedkeys(char, "n", false)
      end
    end, opts)
  end

  vim.keymap.set("n", "J", function()
    M.exit_quickpick()
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
    M.exit_quickpick()
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
    M.exit_quickpick()
    if not state.is_tracked(state.selected_bufnr) then
      return
    end
    state.mark_untracked(state.selected_bufnr)
    state.remove_buffer(state.selected_bufnr)
    ui.render()
  end, opts)
  vim.keymap.set("n", "D", function()
    M.exit_quickpick()
    if not state.is_tracked(state.selected_bufnr) then
      return
    end
    local bufnr = state.selected_bufnr
    state.mark_untracked(bufnr)
    state.remove_buffer(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    ui.render()
  end, opts)
  vim.keymap.set("n", "x", function()
    M.exit_quickpick()
    if state.is_tracked(state.selected_bufnr) then
      state.toggle_hidden(state.selected_bufnr)
      ui.render()
    end
  end, opts)
  vim.keymap.set("n", "a", function()
    M.exit_quickpick()
    if state.selected_bufnr and not state.is_tracked(state.selected_bufnr) then
      state.unmark_untracked(state.selected_bufnr)
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
