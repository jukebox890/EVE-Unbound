-- Keep protection failures out of debug.traceback's native table traversal.
-- Preserve string errors exactly. Never invoke an error object's __tostring.
local value_type=type
return function(value)
    local kind=value_type(value)
    if kind=="string" then return value end
    return "Protection operation failed (non-string error: "..kind..")"
end
