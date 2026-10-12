local UE = {}
function UE.valid(o)
    if o == nil then return false end
    local ok, value = pcall(function() return o:IsValid() end)
    return ok and value == true
end
function UE.read(o, key)
    if not UE.valid(o) then return nil end
    local ok, v = pcall(function() return o[key] end)
    if ok then return v end
end
function UE.full(o)
    if not UE.valid(o) then return nil end
    return o:GetFullName()
end
function UE.path(o)
    local f = UE.full(o)
    return f and f:match("^[^ ]+ (.+)$")
end
function UE.find(path)
    if not path then return nil end
    local o = StaticFindObject(path)
    if UE.valid(o) then return o end
end
function UE.all(class)
    return FindAllOf(class) or {}
end
function UE.log(message)
    print("[EVE Unbound] "..tostring(message).."\n")
end
function UE.record(o)
    if not UE.valid(o) then return nil end
    local Core=require("Core")
    -- Filter owner before touching any key-specific fields. Story mode has many
    -- unrelated cinematic time-scale objects; never inspect them for this tool.
    local owner=UE.path(o:GetOuter())
    if not Core.TARGETS[owner] then return nil end
    local class=o:GetClass():GetFName():ToString()
    if class~="SBShowTimeScaleKey" then return nil end
    return {path=UE.path(o),owner=owner,class=class,address=o:GetAddress(),
        enabled=UE.read(o,"bEnable"),TimeScale=UE.read(o,"TimeScale"),
        StartTime=UE.read(o,"StartTime"),Duration=UE.read(o,"Duration"),
        BlendInTime=UE.read(o,"BlendInTime"),BlendOutTime=UE.read(o,"BlendOutTime")}
end
-- Cache only the six exact dodge keys. Never retain row structs or load assets.
-- A missing optional form is retried every five seconds, or on a manual toggle.
local dodge_keys,dodge_missing={},{}
function UE.clear_dodge_cache() dodge_keys={};dodge_missing={} end
local function dodge_find(path,force,budget)
    local cached=dodge_keys[path]
    if cached and UE.valid(cached.object) and cached.object:GetAddress()==cached.address
        and UE.path(cached.object)==path then return cached.object end
    dodge_keys[path]=nil
    local now=os.time()
    if not force and dodge_missing[path] and now<dodge_missing[path] then return nil end
    if not force and budget then
        if budget.remaining<=0 then return nil end
        budget.remaining=budget.remaining-1
    end
    local object=UE.find(path)
    if object then
        dodge_keys[path]={object=object,address=object:GetAddress()};dodge_missing[path]=nil
    else dodge_missing[path]=now+5 end
    return object
end
function UE.list_keys(force_lookup)
    local Core=require("Core")
    local out={}
    local budget={remaining=1}
    for owner in pairs(Core.TARGETS) do
        for _,suffix in ipairs({":SBShowTimeScaleKey_0",":SBShowTimeScaleKey_2"}) do
            local path=owner..suffix
            local key=dodge_find(path,force_lookup,budget)
            if UE.valid(key) then
                local r=UE.record(key)
                if r then out[#out+1]=r end
            end
        end
    end
    return out
end
function UE.read_key(path) return UE.record(dodge_find(path,false)) end
function UE.write_key(path,address,enabled) return UE.patch_key(path,address,{enabled=enabled}) end
function UE.patch_key(path,address,patch)
    local Core=require("Core")
    local o=dodge_find(path,false);local r=UE.record(o)
    if not Core.is_target(r) or r.address~=address or type(patch)~="table" then return false end
    -- EndTime is not a reflected field on this game's keys. Do not write it.
    local fields={enabled="bEnable",TimeScale="TimeScale",StartTime="StartTime",Duration="Duration",BlendInTime="BlendInTime",BlendOutTime="BlendOutTime"}
    for key,prop in pairs(fields) do
        if patch[key]~=nil then
            local ok=pcall(function() o[prop]=patch[key] end)
            if not ok then return false end
        end
    end
    local after=UE.record(o);if not after then return false end
    for key,_ in pairs(fields) do
        local wanted=patch[key]
        if wanted~=nil then
            local got=after[key]
            if type(wanted)=="number" then
                if type(got)~="number" or math.abs(got-wanted)>0.0001 then return false end
            elseif got~=wanted then return false end
        end
    end
    return true
end
local cached_pc,cached_hud
local next_hud_scan_at=0
local function context_from(pc)
    if not UE.valid(pc) or pc:GetFullName():find("Default__",1,true) then return nil end
    local ok,local_pc=pcall(function() return pc:IsLocalController() end)
    local pawn=UE.read(pc,"Pawn")
    if not ok or not local_pc or not UE.valid(pawn) then return nil end
    local world=pc:GetWorld()
    if not UE.valid(world) then return nil end
    return {pc=pc,pawn=pawn,world=world,
        token=tostring(world:GetAddress())..":"..tostring(pc:GetAddress())..":"..tostring(pawn:GetAddress())}
end
function UE.context()
    -- FindAllOf walks the global UObject array. Reuse a live controller while
    -- re-reading its current pawn/world so possession and map changes still stop tools.
    local cached=context_from(cached_pc)
    if cached then return cached end
    cached_pc=nil
    -- Prefer a unique local controller with a currently possessed pawn.
    local candidates = {}
    for _, pc in ipairs(UE.all("SBPlayerController")) do
        local c=context_from(pc)
        if c then candidates[#candidates+1]=c end
    end
    if #candidates == 1 then cached_pc=candidates[1].pc;return candidates[1] end
end
local function hud_attached(h,context)
    if not context or not UE.valid(h) or h:GetFullName():find("Default__",1,true) then return false end
    local ok,w=pcall(function() return h:GetWorld() end)
    if not ok or not UE.valid(w) or w:GetAddress()~=context.world:GetAddress() then return false end
    return UE.valid(UE.read(h,"CanvasPanel_Root")) and UE.valid(UE.read(h,"WidgetTree"))
end
local function hud_visible_object(h)
    if not UE.valid(h) then return false end
    local ok,visible=pcall(function() return h:IsVisible() end)
    return ok and visible==true
end
function UE.hud_cached(context)
    if hud_attached(cached_hud,context) then
        return cached_hud
    end
end
function UE.hud(context)
    if not context then return nil end
    -- A hidden gameplay HUD is still the correct HUD while Esc/pause menus and boss
    -- intro sequences are covering it. Keep the same-world cache through visibility
    -- changes to avoid repeated global UObject scans.
    local cached=UE.hud_cached(context)
    if cached then return cached end
    cached_hud=nil
    local now=os.time()
    if now<next_hud_scan_at then return nil end
    next_hud_scan_at=now+2
    local visible_matches,hidden_matches={},{}
    for _,h in ipairs(UE.all("WB_MainHUD_Master_C")) do
        if hud_attached(h,context) then
            if hud_visible_object(h) then visible_matches[#visible_matches+1]=h
            else hidden_matches[#hidden_matches+1]=h end
        end
    end
    local chosen=(#visible_matches==1 and visible_matches[1]) or
        (#visible_matches==0 and #hidden_matches==1 and hidden_matches[1]) or nil
    if chosen then cached_hud=chosen;return chosen end
end
function UE.hud_visible(context)
    local h=UE.hud_cached(context) or UE.hud(context)
    return hud_visible_object(h)
end
function UE.paused(context)
    if not context or not UE.valid(context.world) then return false end
    local gm=UE.read(context.world,"AuthorityGameMode")
    if not UE.valid(gm) then return false end
    local ok,value=pcall(function() return gm:IsPaused() end)
    return ok and value==true
end
-- Some game HUD versions leave HpValue/MaxHPValue at zero. Fall back to
-- ProgressBar_HP.Percent, following the current HUD's owned child only.
function UE.health(context)
    local hud=UE.hud(context)
    if not UE.valid(hud) then return nil,"Gameplay HUD unavailable" end
    local info=UE.read(hud,"WB_MainHUD_PlayerInfo")
    local hp,max_hp=UE.read(info,"HpValue"),UE.read(info,"MaxHPValue")
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
    if finite(hp) and finite(max_hp) and max_hp>0 and hp>=0 and hp<=max_hp then
        return {percent=hp/max_hp,current=hp,maximum=max_hp,source="HpValue/MaxHPValue"}
    end
    local bar=UE.read(info,"ProgressBar_HP")
    local percent=UE.read(bar,"Percent")
    if UE.valid(bar) and finite(percent) and percent>=0 and percent<=1 then
        return {percent=percent,source="ProgressBar_HP.Percent"}
    end
    return nil,"HP fields unavailable; ProgressBar_HP.Percent="..tostring(percent)
end
return UE
