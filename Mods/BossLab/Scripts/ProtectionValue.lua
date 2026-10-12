-- Safety checks may receive an invalid userdata/function instead of a float.
-- Describe its type without dereferencing it or invoking __tostring.
return function(value)
    local kind=type(value)
    if kind=="number" or kind=="boolean" or kind=="nil" or kind=="string" then
        return tostring(value).." ("..kind..")"
    end
    return "<"..kind..">"
end
