-- Reversible 1000x attack-step multiplier through reflected table fields.
local UE=require("UE")
local API={}
local PATH="/Game/Local/Data/SkillActiveStepTable.SkillActiveStepTable"
local fields={"SkillAttackDamageRate","SkillShieldAttackDamageRate"}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<=100000000 end
local function f32(n) return string.unpack("<f",string.pack("<f",n)) end
local function table_object()
    local dt=UE.find(PATH)
    assert(UE.valid(dt) and dt:IsA("/Script/Engine.DataTable"),"SkillActiveStepTable unavailable")
    return dt
end
local function alive(context)
    -- Table edits do not depend on the HUD. The Boss Challenge HUD is briefly
    -- unavailable at pre-area -> battle transitions. Pawn identity guards the lease.
    return context~=nil and UE.valid(context.pawn) and context.pawn:IsA("/Script/SB.SBCharacter")
end
function API.available(context)
    if not alive(context) then return false,"live Eve required" end
    local ok,dt=pcall(table_object)
    return ok,ok and "1000x Eve attack-step rates" or tostring(dt)
end
local function snapshot(context)
    local dt=table_object()
    local lease={object=dt,address=dt:GetAddress(),token=context and context.token,rows={},by_name={}}
    dt:ForEachRow(function(name,row)
        local key=tostring(name)
        -- Restrict the multiplier to Eve rows; leave unrelated player/NPC rows alone.
        if not key:match("^P_Eve_") then return end
        local a,b=row[fields[1]],row[fields[2]]
        assert(finite(a) and finite(b),"Invalid damage rates in "..key)
        if a<=0 and b<=0 then return end
        assert(a>=0 and b>=0 and a<=100000 and b<=100000,"Unexpected/already extreme rates in "..key)
        assert(not lease.by_name[key],"Duplicate step "..key)
        local entry={name=key,address=row:GetStructAddress(),original={a,b},
            target={f32(a*1000),f32(b*1000)},written={}}
        assert(entry.address~=0,"Missing row address")
        lease.rows[#lease.rows+1]=entry;lease.by_name[key]=entry
        assert(#lease.rows<=10000,"Unexpected row count")
    end)
    assert(#lease.rows>0,"No damaging P_Eve_ rows found")
    return lease
end
function API.prepare(context)
    assert(alive(context),"Live Eve required")
    return snapshot(context)
end
local function same_table(lease)
    return UE.valid(lease.object) and lease.object:GetAddress()==lease.address
        and UE.path(lease.object)==PATH
end
function API.apply(lease)
    assert(same_table(lease),"Damage table changed")
    local count=0
    -- Re-enumerate before mutation. Never write through a stale saved row wrapper.
    lease.object:ForEachRow(function(name,row)
        local r=lease.by_name[tostring(name)]
        if not r then return end
        assert(row:GetStructAddress()==r.address,"Damage row replaced: "..r.name)
        count=count+1
        for i,field in ipairs(fields) do
            assert(row[field]==r.original[i],"Damage row changed before apply: "..r.name)
            r.written[i]=true -- retain originals even if the setter throws after writing
            row[field]=r.target[i]
            assert(row[field]==r.target[i],"Damage readback mismatch: "..r.name.."."..field)
        end
    end)
    assert(count==#lease.rows,"Damage rows disappeared")
    return true
end
function API.verify(lease,context)
    if not same_table(lease) or not alive(context) or context.token~=lease.token then return false end
    return require("RowVerify").check(lease,fields,64)
end
function API.restore(lease)
    if not same_table(lease) then
        return true
    end
    local failed,restored,external=0,0,0
    lease.object:ForEachRow(function(name,row)
        local r=lease.by_name[tostring(name)]
        if not r then return end
        if row:GetStructAddress()~=r.address then
            -- A replacement row is not the allocation that we changed.
            UE.log("DAMAGE row replaced; left untouched: "..r.name)
            return
        end
        for i,field in ipairs(fields) do
            if r.written[i] then
                local ok,err=pcall(function()
                    local current=row[field]
                    if current==r.target[i] then
                        row[field]=r.original[i]
                        assert(row[field]==r.original[i],"original readback mismatch")
                        restored=restored+1
                    elseif current~=r.original[i] then external=external+1 end
                    r.written[i]=nil -- already original or now owned by another writer
                end)
                if not ok then failed=failed+1;UE.log("DAMAGE restore error "..r.name.."."..field..": "..tostring(err)) end
            end
        end
    end)
    return failed==0
end
return API
