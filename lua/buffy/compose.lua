local M = {}

--- @class BuffyComponent
--- @field text string
--- @field hl string|nil Highlight group, or { hl_group, priority } tuple.

--- @class BuffyContext
--- @field is_hidden boolean Whether the buffer is hidden.
--- @field is_untracked boolean Whether the buffer is untracked.

--- A layout spec entry: component table, callable, or literal string.
--- @alias BuffyInput (BuffyComponent|fun(bufnr: integer, ctx: BuffyContext): BuffyComponent?|BuffyInput?|string)[]

--- @class BuffyResolvedComponent
--- @field text string
--- @field hl string|nil
--- @field priority number

--- @class BuffyHighlight
--- @field col number Byte offset where highlight starts.
--- @field end_col number Byte offset where highlight ends (exclusive).
--- @field hl string Highlight group.
--- @field priority number Extmark priority.

--- Normalize a highlight spec into { hl, priority }.
--- @param hl string|nil|{[1]: string, [2]: number}?
--- @return {hl: string|nil, priority: number}
local function _normalize_hl(hl)
  if type(hl) == "table" then
    return { hl = hl[1], priority = hl[2] or 100 }
  end
  return { hl = hl, priority = 100 }
end

--- Normalize a single layout entry into resolved components.
--- @param item BuffyComponent|fun(bufnr: integer, ctx: BuffyContext): BuffyInput?|string
--- @param bufnr integer
--- @param ctx BuffyContext
--- @return BuffyResolvedComponent[]
local function _resolve(item, bufnr, ctx)
  local t = type(item)
  if t == "function" then
    local out = item(bufnr, ctx)
    if out == nil then
      return {}
    end
    if type(out) == "table" and out.text then
      local n = _normalize_hl(out.hl)
      return { { text = out.text, hl = n.hl, priority = n.priority } }
    end
    if type(out) == "table" then
      return M.evaluate(out, bufnr, ctx)
    end
    return {}
  elseif t == "string" then
    return { { text = item, priority = 100 } }
  elseif t == "table" then
    if item.text then
      local n = _normalize_hl(item.hl)
      return { { text = item.text, hl = n.hl, priority = n.priority } }
    end
    -- Nested list.
    local result = {}
    for _, sub in ipairs(item) do
      for _, c in ipairs(_resolve(sub, bufnr, ctx)) do
        table.insert(result, c)
      end
    end
    return result
  end
  return {}
end

--- Evaluate a layout spec into concrete components.
--- @param spec BuffyInput
--- @param bufnr integer
--- @param ctx BuffyContext
--- @return BuffyResolvedComponent[]
function M.evaluate(spec, bufnr, ctx)
  local result = {}
  for _, item in ipairs(spec) do
    for _, c in ipairs(_resolve(item, bufnr, ctx)) do
      table.insert(result, c)
    end
  end
  return result
end

--- Concatenate resolved components and compute highlight ranges.
--- @param components BuffyResolvedComponent[]
--- @return string, BuffyHighlight[]
function M.compose(components)
  local parts = {}
  local highlights = {}
  local col = 0

  for _, comp in ipairs(components) do
    local text = comp.text
    table.insert(parts, text)
    if comp.hl then
      table.insert(highlights, {
        col = col,
        end_col = col + #text,
        hl = comp.hl,
        priority = comp.priority,
      })
    end
    col = col + #text
  end

  return table.concat(parts), highlights
end

return M
