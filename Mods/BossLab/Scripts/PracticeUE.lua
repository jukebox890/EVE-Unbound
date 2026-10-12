-- Known, fixed engine APIs only. UE4SS marshals their reflected parameters.
local UE=require("UE")
local Bridge={}
local gameplay_statics=nil
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
local function get_time(context)
    assert(context,"No player")
    if not UE.valid(gameplay_statics) then gameplay_statics=UE.find("/Script/Engine.GameplayStatics") end
    assert(UE.valid(gameplay_statics),"GameplayStatics unavailable")
    local time=gameplay_statics:GetCDO():GetTimeSeconds(context.world)
    assert(finite(time),"Game clock unavailable")
    return time
end
local function sample(context)
    local health,why=UE.health(context)
    assert(health,why or "HUD HP unavailable")
    local hud=UE.hud_cached and UE.hud_cached(context) or nil
    local dead=UE.read(hud,"WB_MainHUD_Dead")
    return {hp=health.percent*100,max_hp=100,time=get_time(context),world=UE.path(context.world),
        health_source=health.source,unit="percentage points",raw_hp=health.current,raw_max_hp=health.maximum,
        battle=UE.read(context.pawn,"bBattleState"),lockon=UE.read(context.pawn,"bLockOn"),
        boss_challenge=UE.read(dead,"bBossChallengeMode")}
end
local function guarded(fn,...)
    local ok,a,b=xpcall(fn,debug.traceback,...)
    if ok then return a,b end
    UE.log("API ERROR "..tostring(a))
    return nil,tostring(a)
end
function Bridge.new(config)
    return {
        time=function(c) return guarded(get_time,c) end,
        sample=function(c) return guarded(sample,c) end,
    }
end
return Bridge
