-- Protection uses scalar snapshots and fresh named-row views. No write occurs
-- inside a UDataTable enumeration callback; no row wrapper is retained in a lease.
local UE=require("UE")
local error_message=require("ProtectionError")
local describe=require("ProtectionValue")
local API={halt_on_failure=true}
local PATH="/Game/Local/Data/SkillActiveStepTable.SkillActiveStepTable"
local fields={"SkillAttackDamageRate","SkillShieldAttackDamageRate"}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<=100000 end
local function alive(c) return c and UE.valid(c.pawn) and c.pawn:IsA("/Script/SB.SBCharacter") end
local function table_object()
    local dt=UE.find(PATH)
    assert(UE.valid(dt) and dt:IsA("/Script/Engine.DataTable"),"SkillActiveStepTable unavailable")
    assert(type(dt.FindRow)=="function" and type(dt.GetRowNames)=="function","Named-row protection API unavailable; no bulk-write fallback")
    return dt
end
local function same_table(lease)
    return UE.valid(lease.object) and lease.object:GetAddress()==lease.address and UE.path(lease.object)==PATH
end
local function matches(mode,name)
    return (mode=="boss" and name:match("^P_")~=nil) or (mode=="player" and name:match("^P_")==nil)
end
local function diagnostic(lease,phase,r,field,expected,actual,address)
    return string.format("%s | mode=%s row=%s field=%s expected=%s actual=%s table=%s saved_row=%s current_row=%s",
        phase,lease.mode,r.name,tostring(field),describe(expected),describe(actual),tostring(lease.address),tostring(r.address),tostring(address))
end
local function expect(lease,phase,r,field,expected,actual,address)
    if actual~=expected then error(diagnostic(lease,phase,r,field,expected,actual,address)) end
end
local function resolve(lease,r,phase)
    local row=lease.object:FindRow(r.name)
    local address=row and row:GetStructAddress() or nil
    if not row or address~=r.address then error(diagnostic(lease,phase,r,"identity",r.address,address,address)) end
    return row
end
local function checked(lease,phase,fn)
    local ok,result=xpcall(fn,error_message)
    if not ok then
        UE.log("PROTECTION NAMED FAILURE | "..phase.." | "..tostring(result))
        return false,result
    end
    return result
end
function API.available(context,mode)
    if mode~="boss" and mode~="player" then return false,"unknown protection mode" end
    if not alive(context) then return false,"live Eve required" end
    local ok,dt=pcall(table_object)
    return ok,ok and "fresh named-row protection" or tostring(dt)
end
function API.prepare(context,mode)
    assert(alive(context),"Live Eve required")
    assert(mode=="boss" or mode=="player","Unknown protection mode")
    local dt=table_object()
    local lease={object=dt,address=dt:GetAddress(),token=context.token,mode=mode,rows={},by_name={},changed_fields=0,named_rows=true,verify_cursor=1}
    local names=dt:GetRowNames()
    assert(type(names)=="table","GetRowNames did not return an array")
    assert(#names>0 and #names<=50000,"Unexpected attack-step catalogue size")
    -- Retain catalogue order: alphabetical sorting has no gameplay purpose.
    -- Fetch new values on every activation; never reuse stale originals.
    local selected={}
    for _,name in ipairs(names) do
        assert(type(name)=="string","GetRowNames returned a non-string name")
        if matches(mode,name) then selected[#selected+1]=name end
    end
    for _,name in ipairs(selected) do
        local row=dt:FindRow(name)
        assert(row,"Snapshot row missing: "..name)
        local address=row:GetStructAddress()
        local a,b=row[fields[1]],row[fields[2]]
        if not (finite(a) and finite(b) and a>=0 and b>=0) then
            error("Invalid protection rates | mode="..mode.." row="..name..
                " damage="..describe(a).." shield="..describe(b)..
                " table="..tostring(lease.address).." row_address="..tostring(address))
        end
        if a>0 or b>0 then
            assert(address and address~=0 and not lease.by_name[name],"Invalid/duplicate protection row: "..name)
            local r={name=name,address=address,original={a,b},target={0.0,0.0},written={}}
            lease.rows[#lease.rows+1]=r;lease.by_name[name]=r
            for _,v in ipairs(r.original) do if v~=0 then lease.changed_fields=lease.changed_fields+1 end end
        end
    end
    assert(#lease.rows>0 and #lease.rows<=20000,"Unexpected protection row count")
    return lease
end
function API.apply(lease)
    return checked(lease,"apply",function()
        assert(same_table(lease),"Protection table identity changed")
        -- Validate ALL originals before the first write. Validate each again at
        -- its write site. Neither pass uses an enumeration callback.
        for _,r in ipairs(lease.rows) do
            local row=resolve(lease,r,"preflight")
            for i,field in ipairs(fields) do
                local actual=row[field]
                expect(lease,"preflight",r,field,r.original[i],actual,r.address)
            end
        end
        for _,r in ipairs(lease.rows) do
            local row=resolve(lease,r,"apply")
            for i,field in ipairs(fields) do
                local before=row[field]
                expect(lease,"before write",r,field,r.original[i],before,r.address)
                if before~=r.target[i] then
                    r.written[i]=true -- retain ownership even if setter fails after a write
                    row[field]=r.target[i]
                    local after=row[field]
                    expect(lease,"apply readback",r,field,r.target[i],after,row:GetStructAddress())
                end
            end
        end
        return true
    end)
end
function API.verify(lease,context)
    if not same_table(lease) then return false,"table identity changed/unloaded" end
    if not alive(context) or context.token~=lease.token then return false,"player/world identity changed" end
    return require("RowVerify").check(lease,fields,64,3)
end
function API.restore(lease)
    if not lease then return true end
    if not same_table(lease) then
        return true
    end
    if lease.restore_blocked then return false,"previous restore failed; restart game before more protection writes" end
    local restored,external,replaced=0,0,0
    local ok,why=checked(lease,"restore",function()
        for _,r in ipairs(lease.rows) do
            if next(r.written) then
                local row=lease.object:FindRow(r.name)
                local address=row and row:GetStructAddress() or nil
                if not row or address~=r.address then
                    -- The allocation we edited is gone. Never put its originals
                    -- into a replacement row, even when the name is identical.
                    replaced=replaced+1;r.written={}
                else
                    for i,field in ipairs(fields) do
                        if r.written[i] then
                            local current=row[field]
                            if not finite(current) then
                                error(diagnostic(lease,"restore invalid value",r,field,r.target[i],current,address))
                            end
                            if current==r.target[i] then
                                row[field]=r.original[i]
                                local after=row[field]
                                expect(lease,"restore readback",r,field,r.original[i],after,row:GetStructAddress())
                                restored=restored+1
                            elseif current~=r.original[i] then external=external+1 end
                            r.written[i]=nil
                        end
                    end
                end
            end
        end
        return true
    end)
    if not ok then lease.restore_blocked=true end -- stop at the FIRST failure; no repeat attempts
    return ok,why
end
return API
