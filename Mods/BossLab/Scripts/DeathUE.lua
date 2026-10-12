-- No-hit practice: amplify incoming attack damage with bounded rates.
-- Restore originals on OFF, combat end, context change or Reset tools.
local UE=require("UE")
local API={}
local cfg={NoDamageRunFactor=100,NoDamageRunMinRate=100,NoDamageRunMaxRate=10000}
local logger=function(message) UE.log("NO DAMAGE RUN | "..tostring(message)) end
local active=nil
local prearmed_token=nil

local PATH="/Game/Local/Data/SkillActiveStepTable.SkillActiveStepTable"
local fields={"SkillAttackDamageRate","SkillShieldAttackDamageRate"}

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<=100000000 end
local function f32(n) return string.unpack("<f",string.pack("<f",n)) end
local function alive(context)
    return context~=nil and UE.valid(context.pawn) and context.pawn:IsA("/Script/SB.SBCharacter")
end
local function table_object()
    local dt=UE.find(PATH)
    assert(UE.valid(dt) and dt:IsA("/Script/Engine.DataTable"),"SkillActiveStepTable unavailable")
    return dt
end
local function same_table(lease)
    return lease and UE.valid(lease.object) and lease.object:GetAddress()==lease.address and UE.path(lease.object)==PATH
end
local function target_for(value)
    if value<=0 then return 0.0 end
    local factor=tonumber(cfg.NoDamageRunFactor) or 100
    local minimum=tonumber(cfg.NoDamageRunMinRate) or 100
    local maximum=tonumber(cfg.NoDamageRunMaxRate) or 10000
    local target=math.max(value*factor,minimum)
    target=math.min(target,maximum)
    return f32(target)
end

local function prepare(context)
    assert(alive(context),"Live Eve required")
    local dt=table_object()
    local lease={object=dt,address=dt:GetAddress(),token=context.token,pawn_address=context.pawn:GetAddress(),rows={},by_name={},changed_fields=0}
    dt:ForEachRow(function(name,row)
        local key=tostring(name)
        -- Mirror Player Invulnerability's proven selection: all non-player attack steps.
        if key:match("^P_") then return end
        local a,b=row[fields[1]],row[fields[2]]
        if not finite(a) or not finite(b) then return end
        if a<=0 and b<=0 then return end
        assert(a>=0 and b>=0 and a<=100000 and b<=100000,"Unexpected/already extreme rates in "..key)
        assert(not lease.by_name[key],"Duplicate step "..key)
        local ta,tb=target_for(a),target_for(b)
        local entry={name=key,address=row:GetStructAddress(),original={a,b},target={ta,tb},written={}}
        assert(entry.address~=0,"Missing row address")
        lease.rows[#lease.rows+1]=entry;lease.by_name[key]=entry
        if ta~=a then lease.changed_fields=lease.changed_fields+1 end
        if tb~=b then lease.changed_fields=lease.changed_fields+1 end
        assert(#lease.rows<=20000,"Unexpected No Damage Run row count")
    end)
    assert(#lease.rows>0,"No matching incoming damaging rows found")
    assert(lease.changed_fields>0,"Incoming damage rows already at target values")
    return lease
end

local function apply(lease)
    assert(same_table(lease),"Damage table changed")
    local count,changed=0,0
    lease.object:ForEachRow(function(name,row)
        local r=lease.by_name[tostring(name)]
        if not r then return end
        assert(row:GetStructAddress()==r.address,"No Damage Run row replaced: "..r.name)
        count=count+1
        for i,field in ipairs(fields) do
            assert(row[field]==r.original[i],"No Damage Run row changed before apply: "..r.name.."."..field)
            if r.target[i]~=r.original[i] then
                r.written[i]=true
                row[field]=r.target[i]
                assert(row[field]==r.target[i],"No Damage Run readback mismatch: "..r.name.."."..field)
                changed=changed+1
            end
        end
    end)
    assert(count==#lease.rows,"No Damage Run rows disappeared")
    assert(changed==lease.changed_fields,"No Damage Run changed-field count mismatch")
    return true
end

local function restore(lease)
    if not lease then return true end
    if not same_table(lease) then
        return true
    end
    local failed,restored,external=0,0,0
    lease.object:ForEachRow(function(name,row)
        local r=lease.by_name[tostring(name)]
        if not r then return end
        if row:GetStructAddress()~=r.address then
            logger("restore: row replaced; left untouched: "..r.name)
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
                    elseif current~=r.original[i] then
                        external=external+1
                    end
                    r.written[i]=nil
                end)
                if not ok then
                    failed=failed+1
                    logger("restore error "..r.name.."."..field..": "..tostring(err))
                end
            end
        end
    end)
    return failed==0
end

function API.configure(config,log_fn)
    if type(config)=="table" then
        for _,k in ipairs({"NoDamageRunFactor","NoDamageRunMinRate","NoDamageRunMaxRate","NoDamageRunAllowPrearm"}) do
            if config[k]~=nil then cfg[k]=config[k] end
        end
    end
    if type(log_fn)=="function" then logger=log_fn end
end

function API.available(context)
    if not alive(context) then return false,"live Eve required" end
    local ok,dt=pcall(table_object)
    return ok,ok and "incoming attack-step amplification available" or tostring(dt)
end
function API.pending() return active~=nil or prearmed_token~=nil end
function API.banner() return active and "NO DAMAGE RUN  •  ON" or (prearmed_token and "NO-HIT RUN  •  ARMED" or nil) end

function API.cancel(reason)
    prearmed_token=nil
    if not active then return true,"No Damage Run OFF" end
    local lease=active
    active=nil
    local ok,result=xpcall(function() return restore(lease) end,debug.traceback)
    if not ok or result~=true then
        logger("RESTORE INCOMPLETE | "..tostring(ok and result or result).." | reason="..tostring(reason))
        return false,"No Damage Run restore incomplete; press Num0 and send log"
    end
    return true,"No Damage Run OFF"
end

function API.kill(context)
    if active then return false,"No Damage Run already ON" end
    if not alive(context) then return false,"live Eve required" end
    local prepared,lease=xpcall(function() return prepare(context) end,debug.traceback)
    if not prepared or not lease then
        logger("snapshot failed | "..tostring(lease))
        return false,"No Damage Run snapshot failed: "..tostring(lease)
    end
    active=lease
    local applied,result=xpcall(function() return apply(lease) end,debug.traceback)
    if not applied or result~=true then
        local why=tostring(applied and result or result)
        logger("apply failed | "..why)
        API.cancel("apply failed")
        return false,"No Damage Run apply failed: "..why
    end
    return true,"No Damage Run ON"
end

function API.toggle(context,battle)
    if API.pending() then return API.cancel("Num7 toggle off") end
    if battle~=true then
        if cfg.NoDamageRunAllowPrearm and alive(context) and battle==false then
            prearmed_token=context.token
            return true,"No-hit run ARMED; next combat activates the existing next-hit mode"
        end
        return false,"active combat required"
    end
    return API.kill(context)
end

function API.tick(context,ready)
    if prearmed_token then
        if not context or not alive(context) or context.token~=prearmed_token then
            return API.cancel("armed player/world changed")
        end
        if ready==false then return nil end
        if UE.read(context.pawn,"bBattleState")==true then
            prearmed_token=nil
            return API.kill(context)
        end
        return nil
    end
    if not active then return nil end
    if not context or not alive(context) or context.token~=active.token or context.pawn:GetAddress()~=active.pawn_address then
        local ok,msg=API.cancel("player/world changed")
        return ok,msg
    end
    local battle=UE.read(context.pawn,"bBattleState")
    if battle~=true then
        local ok,msg=API.cancel("boss fight ended/death transition")
        return ok,msg
    end
    return nil
end

return API
