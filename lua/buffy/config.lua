local M = {}

local components = require "buffy.components"
local _ = require "buffy.types"

local defaults = {
  max_height = 20,
  auto_track = false,
  quickpick_chars = "qwertyuiop1234567890",
  layout = {
    components.icon,
    components.filename,
    components.markers,
    "  ",
    components.path,
  },
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
  options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
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
