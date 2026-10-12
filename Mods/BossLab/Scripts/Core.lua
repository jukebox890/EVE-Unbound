-- Perfect-dodge slow-motion controller.
--
-- Num1 now cycles NORMAL -> OFF -> EXTENDED -> NORMAL.
-- OFF preserves the already-proven behavior: disable only SBShowTimeScaleKey objects
-- belonging to Eve's exact perfect-dodge show assets.
-- EXTENDED adjusts the loaded perfect-dodge keys at runtime.
-- EXTENDED now stretches the timing fields and multiplies each key's own vanilla
-- TimeScale by a configurable value (default 0.5) so the effect is genuinely slower.
local Core = {}
Core.__index = Core

Core.TARGETS = {
    ["/Game/Art/Show/CH_P_EVE_01/Skill/P_Eve_Sword_Normal_JustEvade1.P_Eve_Sword_Normal_JustEvade1"] = true,
    ["/Game/Art/Show/CH_P_EVE_01/Skill/Fusion/P_Eve_Fusion_Normal_JustEvade1.P_Eve_Fusion_Normal_JustEvade1"] = true,
    ["/Game/Art/Show/CH_P_EVE_01/Skill/P_Eve_Tachy_Normal_JustEvade1.P_Eve_Tachy_Normal_JustEvade1"] = true,
}
-- Backward-compatible constant used by older tests/helpers.
Core.TARGET = "/Game/Art/Show/CH_P_EVE_01/Skill/P_Eve_Sword_Normal_JustEvade1.P_Eve_Sword_Normal_JustEvade1"
local TIMING_FIELDS={"StartTime","Duration","BlendInTime","BlendOutTime"}

local function finite(v) return type(v)=="number" and v==v and math.abs(v)<1e6 end
local function near(a,b)
    if type(a)~=type(b) then return false end
    if type(a)=="number" then return math.abs(a-b)<0.0001 end
    return a==b
end

function Core.is_target(record)
    return record and record.class == "SBShowTimeScaleKey"
        and Core.TARGETS[record.owner] == true
        and type(record.enabled) == "boolean"
        and type(record.path) == "string" and record.path ~= ""
        and record.address ~= nil
end

function Core.new(api,config)
    local factor=tonumber(config and config.ExtendedDodgeSlowMoFactor) or 8.0
    if factor<1.25 then factor=1.25 end
    if factor>12.0 then factor=12.0 end
    local scale=tonumber(config and config.ExtendedDodgeTimeScaleMultiplier) or 0.5
    if scale<0.1 then scale=0.1 end
    if scale>1.0 then scale=1.0 end
    return setmetatable({api=api, mode="normal", active=false, saved={}, expected={}, matched=0, changed=0,
        extended_factor=factor,extended_timescale_multiplier=scale,last="Perfect Dodge slow-mo: NORMAL."}, Core)
end

function Core:mode_label()
    if self.mode=="off" then return "OFF" end
    if self.mode=="extended" then return "EXTENDED" end
    return "NORMAL"
end

local function snapshot_record(r)
    local s={address=r.address,enabled=r.enabled}
    if finite(r.TimeScale) then s.TimeScale=r.TimeScale end
    for _,field in ipairs(TIMING_FIELDS) do
        local v=r[field]
        if finite(v) then s[field]=v end
    end
    return s
end

local function desired_patch(self,saved)
    local patch={}
    if self.mode=="off" then
        patch.enabled=false
        return patch
    end
    if self.mode=="extended" then
        patch.enabled=saved.enabled
        local factor=self.extended_factor
        if finite(saved.TimeScale) then
            patch.TimeScale=saved.TimeScale*self.extended_timescale_multiplier
        end
        for _,field in ipairs(TIMING_FIELDS) do
            local v=saved[field]
            if finite(v) then
                if v>0 then patch[field]=v*factor else patch[field]=v end
            end
        end
        return patch
    end
    patch.enabled=saved.enabled
    if saved.TimeScale~=nil then patch.TimeScale=saved.TimeScale end
    for _,field in ipairs(TIMING_FIELDS) do if saved[field]~=nil then patch[field]=saved[field] end end
    return patch
end

local function matches_patch(r,patch)
    for k,v in pairs(patch) do
        local rv = (k=="enabled") and r.enabled or r[k]
        if not near(rv,v) then return false end
    end
    return true
end

function Core:_apply(path,r,saved,owned)
    local patch=desired_patch(self,saved)
    if self.mode=="normal" and owned then
        for field in pairs(patch) do if owned[field]==nil then patch[field]=nil end end
    end
    if not self.api.patch then
        -- Older/dormant stages can still use OFF/NORMAL via the boolean writer.
        if self.mode=="extended" then return false,"extended patch API unavailable" end
        local ok,accepted=pcall(self.api.write,path,saved.address,patch.enabled)
        return ok and accepted or false, accepted
    end
    local ok,accepted=pcall(self.api.patch,path,saved.address,patch)
    return ok and accepted or false,accepted
end

function Core:restore(reason)
    local restored,missing,failed,external=0,0,0,0
    for path,saved in pairs(self.saved) do
        local ok,r=pcall(self.api.read,path)
        if not ok then
            failed=failed+1
        elseif not r or r.address~=saved.address or not Core.is_target(r) then
            self.saved[path]=nil;self.expected[path]=nil;missing=missing+1
        else
            local expected=self.expected[path]
            -- If another writer changed a value after Boss Lab patched it, leave it alone.
            if expected and not matches_patch(r,expected) then
                self.saved[path]=nil;self.expected[path]=nil;external=external+1
            else
                local old_mode=self.mode;self.mode="normal"
                local set_ok,accepted=self:_apply(path,r,saved,expected)
                self.mode=old_mode
                if set_ok and accepted then
                    self.saved[path]=nil;self.expected[path]=nil;restored=restored+1
                else failed=failed+1 end
            end
        end
    end
    self.mode="normal";self.active=false;self.matched,self.changed=0,0
    self.last = failed>0 and ("Restore incomplete: "..failed.." key(s). Press Reset again.")
        or "Perfect Dodge slow-mo: NORMAL."
    if failed>0 then self.api.log("DODGE RESTORE INCOMPLETE | "..failed.." key(s)") end
    return failed==0
end

function Core:scan()
    if not self.active then return false end
    local ok,records=pcall(self.api.list,not self.lookup_started)
    self.lookup_started=true
    if not ok then
        self:restore("scan error")
        self.last="Stopped: cannot inspect perfect-dodge time-scale keys. See UE4SS.log."
        return false
    end
    local matched,changed=0,0
    for _,r in ipairs(records or {}) do
        if Core.is_target(r) then
            matched=matched+1
            local saved=self.saved[r.path]
            if saved and saved.address~=r.address then
                self.saved[r.path]=nil;self.expected[r.path]=nil;saved=nil
            end
            if not saved then
                saved=snapshot_record(r);self.saved[r.path]=saved
            else
                local expected=self.expected[r.path]
                if expected and not matches_patch(r,expected) then
                    self:restore("external change")
                    self.last="Stopped: another mod changed the perfect-dodge slow-motion key."
                    return false
                end
            end
            local patch=desired_patch(self,saved)
            if not matches_patch(r,patch) then
                local success,accepted=self:_apply(r.path,r,saved)
                if not success or not accepted then
                    self:restore("write failed")
                    self.last="Stopped: perfect-dodge slow-motion write failed. Press Reset; send log."
                    return false
                end
            end
            self.expected[r.path]=patch
            changed=changed+1
        end
    end
    self.matched,self.changed=matched,changed
    if matched==0 then
        self.last="Waiting for a perfect-dodge show asset to load. Land one perfect dodge."
    elseif self.mode=="off" then
        self.last=string.format("Perfect Dodge slow-mo OFF (%d key%s).",matched,matched==1 and "" or "s")
    else
        self.last=string.format("Perfect Dodge slow-mo EXTENDED duration x%.1f / TimeScale x%.2f (%d key%s).",self.extended_factor,self.extended_timescale_multiplier,matched,matched==1 and "" or "s")
    end
    return true
end

function Core:set_mode(mode,reason)
    assert(mode=="normal" or mode=="off" or mode=="extended","invalid dodge slow-mo mode")
    if mode=="normal" then return self:restore(reason or "normal mode") end
    if next(self.saved) then
        if not self:restore("mode switch") then return false end
    end
    self.mode=mode;self.active=true;self.lookup_started=false
    self.last="Looking for loaded perfect-dodge time-scale keys."
    return self:scan()
end

function Core:cycle()
    if self.mode=="normal" then return self:set_mode("off","cycle") end
    if self.mode=="off" then return self:set_mode("extended","cycle") end
    return self:set_mode("normal","cycle")
end

-- Backward compatibility: enable() still means the original no-slow mode.
function Core:enable() return self:set_mode("off","enable") end

return Core
