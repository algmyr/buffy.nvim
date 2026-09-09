local M = {}

--- A single resolved component ready for rendering.
--- @class BuffyResolvedComponent
--- @field text string
--- @field hl string|nil
--- @field priority number

--- A highlight range to apply to rendered text.
--- @class BuffyHighlight
--- @field col number Byte offset where highlight starts.
--- @field end_col number Byte offset where highlight ends (exclusive).
--- @field hl string Highlight group.
--- @field priority number Extmark priority.

--- A component returned by a layout function.
--- @class BuffyComponent
--- @field text string
--- @field hl string|nil Highlight group, or { hl_group, priority } tuple.

--- Context passed to layout functions.
--- @class BuffyContext
--- @field is_hidden boolean Whether the buffer is hidden.
--- @field is_untracked boolean Whether the buffer is untracked.

--- A function that returns a component or another layout spec.
--- @alias BuffyLayoutFn fun(bufnr: integer, ctx: BuffyContext): BuffyComponent?|BuffyInput?|string

--- A layout spec entry: component table, callable, or literal string.
--- @alias BuffyInput (BuffyComponent|BuffyLayoutFn|string)[]

--- Configuration for the picker or peek window.
--- @class BuffyPickerConfig
--- @field border string|string[] Window border style.
--- @field position string Window position: "top", "center", or "bottom".

--- Top-level plugin configuration.
--- @class BuffyConfig
--- @field max_height number Maximum number of visible lines in the picker.
--- @field auto_track boolean Automatically track buffers opened from the CLI.
--- @field quickpick_chars string Characters available for quickpick labels.
--- @field layout BuffyInput Component layout specification.
--- @field picker BuffyPickerConfig Configuration for the main picker window.
--- @field peek BuffyPickerConfig Configuration for the peek preview window.

--- Thin abstraction over vim.api for buffer queries, enabling mocking in tests.
--- @class BufProvider
--- @field get_all_bufs fun(): integer[]
--- @field is_valid fun(bufnr: integer): boolean
--- @field get_name fun(bufnr: integer): string
--- @field get_buftype fun(bufnr: integer): string
--- @field get_current_buf fun(): integer
--- @field set_current_buf fun(bufnr: integer)

return M
