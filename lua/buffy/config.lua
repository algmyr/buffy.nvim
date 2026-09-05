local M = {}

--- @class BuffyConfig
--- @field max_height number Maximum number of visible lines in the picker.
--- @field icons boolean Whether to show file-type icons.
--- @field auto_track boolean Automatically track buffers opened from the CLI.
local defaults = {
  max_height = 20,
  icons = true,
  auto_track = false,
  quickpick_chars = "qwertyuiop1234567890",
  picker = {
    border = "none",
    position = "top",
  },
  peek = {
    border = "none",
    position = "top",
  },
}

--- @type BuffyConfig|nil
local options = nil

--- Merge user options with defaults.
--- @param opts BuffyConfig|nil
function M.setup(opts)
  ---@diagnostic disable-next-line: param-type-mismatch
  options = vim.tbl_deep_extend("force", defaults, opts or {})
end

--- Return the current configuration.
--- @return BuffyConfig
function M.get()
  if not options then
    error "Buffy is not configured. Run setup function."
  end
  return options
end

return M
