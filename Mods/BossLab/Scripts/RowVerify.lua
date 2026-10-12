-- Fresh named row views, bounded per visit. Never cache a row userdata/pointer.
local Verify={}
local describe=require("ProtectionValue")
function Verify.check(lease,fields,budget,fallback_seconds)
    local checked_first=false
    if lease.named_rows==nil then
        local ok,fn=pcall(function() return lease.object.FindRow end)
        lease.named_rows=ok and type(fn)=="function"
        if lease.named_rows then
            -- Some bundled runtimes expose a binding that rejects this signature.
            -- Check once; fall back without entering an endless restore/rebind loop.
            local callable,row=pcall(fn,lease.object,lease.rows[1].name)
            checked_first=true
            if not callable then lease.named_rows=false
            elseif not row or row:GetStructAddress()~=lease.rows[1].address then return false,"named row missing/replaced: "..lease.rows[1].name end
        end
        lease.verify_cursor=1

    end
    if lease.named_rows then
        local n=#lease.rows
        for _=1,math.min((budget or 64)-(checked_first and 1 or 0),n) do
            local index=lease.verify_cursor
            local expected=lease.rows[index]
            local row=lease.object:FindRow(expected.name)
            if not row or row:GetStructAddress()~=expected.address then return false,"named row missing/replaced: "..expected.name end
            for i,field in ipairs(fields) do
                local actual=row[field]
                if actual~=expected.target[i] then return false,"value mismatch: "..expected.name.."."..field.." expected="..describe(expected.target[i]).." actual="..describe(actual) end
            end
            lease.verify_cursor=index%n+1
        end
        return true -- complete rolling coverage; application already read back every write
    end
    -- Older UE4SS builds: retain the proven full verification at its old cadence.
    -- Capability is checked once per lease, without retaining a failed row view.
    local now=os.time()
    if lease.last_verified and now-lease.last_verified<(fallback_seconds or 1) then return true end
    local count,valid,reason=0,true,nil
    lease.object:ForEachRow(function(name,row)
        local r=lease.by_name[tostring(name)]
        if not r then return end
        count=count+1
        if row:GetStructAddress()~=r.address then valid=false;reason=reason or ("row replaced: "..tostring(name));return end
        for i,field in ipairs(fields) do
            local actual=row[field]
            if actual~=r.target[i] then valid=false;reason=reason or ("value mismatch: "..tostring(name).."."..field.." expected="..describe(r.target[i]).." actual="..describe(actual)) end
        end
    end)
    if not valid or count~=#lease.rows then return false,reason or ("row count mismatch: "..count.."/"..#lease.rows) end
    lease.last_verified=now
    return true
end
return Verify
