-- Native resource refill; starts OFF.
local UE=require("UE")
local Native=require("NativeGaugeUE")
local Resource={};Resource.__index=Resource
local KINDS={"beta","burst","tachy"}
local EFFECT_PATH="/Game/Local/Data/EffectTable.EffectTable"
local GAUGE_NAMES={"Mod_BetaGaugeRegen","Mod_BurstGaugeRegen","Mod_TachyGaugeRegen"}
local GAUGE_ROWS={Mod_BetaGaugeRegen=true,Mod_BurstGaugeRegen=true,Mod_TachyGaugeRegen=true}
local DATA_LIBRARY="/Script/Engine.Default__DataTableFunctionLibrary"
local function resolve_table(path,label)
    local dt=UE.find(path)
    if not UE.valid(dt) then return nil,label.." missing" end
    if not dt:IsA("/Script/Engine.DataTable") then return nil,label.." is not DataTable" end
    return dt
end
function Resource.new(config,logger)
    return setmetatable({config=config or {},log=logger or function() end,
        enabled={beta=false,burst=false,tachy=false},all=false,active=false,
        last="PRACTICE RESOURCES OFF"},Resource)
end
function Resource:busy() return self.all end
function Resource:_state(on)
    self.all=on;self.active=on
    for _,kind in ipairs(KINDS) do self.enabled[kind]=on end
end
-- Query only the needed names. Do not construct Lua row wrappers for the entire
-- EffectTable. A known stock row verifies the reflected query works before its
-- negative answers are trusted. Keep the proven scan only as a compatibility fallback.
function Resource:_package_conflict(dt)
    local ok,conflict=pcall(function()
        local lib=UE.find(DATA_LIBRARY)
        assert(UE.valid(lib),"DataTableFunctionLibrary unavailable")
        local stock=lib:DoesDataTableRowExist(dt,FName("ImmediateDeath"))
        assert(stock==true,"stock-row compatibility check failed")
        for _,alias in ipairs(GAUGE_NAMES) do
            local exists=lib:DoesDataTableRowExist(dt,FName(alias))
            assert(type(exists)=="boolean","row query returned non-boolean")
            if exists then return true end
        end
        return false
    end)
    if ok then return conflict end
    local found=false
    dt:ForEachRow(function(name,row) if GAUGE_ROWS[tostring(name)] then found=true end end)
    return found
end
function Resource:_check_package(context)
    if not context or not context.token then return false,"live Eve required" end
    if self.checked_token==context.token then return true end
    local dt,why=resolve_table(EFFECT_PATH,"EffectTable")
    if not dt then return false,why end
    if self:_package_conflict(dt) then
        return false,"REMOVE_REGEN_PAK: close game, remove its .pak/.utoc/.ucas triplet, restart"
    end
    self.checked_token=context.token
    return true
end
function Resource:_fill(context)
    if not context or UE.paused(context) then return false,"live unpaused Eve required" end
    local ok,why=self:_check_package(context)
    if not ok then return false,why end
    return Native.fill(context)
end
function Resource:_off(reason)
    self:_state(false)
    self.last=reason or "PRACTICE RESOURCES OFF • refill stopped"
    return true
end
function Resource:set_all(on,context)
    if not on then return self:_off(),self.last end
    if self.ready and not self.ready(context) then
        self:_state(true);self.active=false
        self.last="RESOURCES ARMED • waiting for stable gameplay"
        return true,self.last
    end
    local safe,ok,why=pcall(self._fill,self,context)
    if not safe then why=ok;ok=false end
    if not ok then
        self:_off("PRACTICE RESOURCES OFF • "..tostring(why))
        self.log("RESOURCE BLOCKED | "..tostring(why));return false,why
    end
    self:_state(true)
    self.last="RESOURCES ON • Beta/Burst/Tachy refill"
    return true,self.last
end
function Resource:restore(context) return self:set_all(false,context) end
function Resource:discover(context)
    if not self.all then return true,self.last end
    return self:tick(context)
end
function Resource:tick(context,battle)
    if not self.all then return true end
    -- A missing/paused context suspends writes. Other failures disarm immediately.
    if not context or UE.paused(context) or (self.ready and not self.ready(context)) then
        self.active=false;self.last="PRACTICE RESOURCES ARMED • waiting for live gameplay";return false,self.last
    end
    local safe,ok,why=pcall(self._fill,self,context)
    if not safe then why=ok;ok=false end
    if not ok then
        self:_off("PRACTICE RESOURCES OFF • "..tostring(why))
        self.log("RESOURCE STOPPED | "..tostring(why));return false,why
    end
    self.active=true
    self.last="RESOURCES ON • Beta/Burst/Tachy refill"
    return true
end
function Resource:details() return self.last end
function Resource:banner()
    if not self.all then return nil end
    return self.active and "RESOURCES • ON" or "RESOURCES • WAITING"
end
return Resource
