-- Grounded same-session position capture and return.
-- Capture deliberately does NOT depend on the gameplay HUD. Stellar Blade briefly
-- removes/rebuilds the HUD at combat entry. A valid controlled SBCharacter is enough
-- to capture a known-good location. Return keeps movement/collision guards.
local UE=require("UE")
local Bridge={}

local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<1e12
end
local function pawn_ok(context)
    assert(context and UE.valid(context.pawn),"No controlled player")
    assert(context.pawn:IsA("/Script/SB.SBCharacter"),"Controlled pawn is not an SBCharacter")
end
local function return_usable(context)
    pawn_ok(context)
    local movement=UE.read(context.pawn,"CharacterMovement")
    assert(UE.valid(movement),"CharacterMovement unavailable")
    assert(UE.read(movement,"MovementMode")==1,"Position return requires ground walking")
    assert(UE.read(context.pawn,"bActorEnableCollision")==true,"Player collision is not enabled")
end
local function capture(context)
    pawn_ok(context)
    local p=context.pawn:K2_GetActorLocation()
    assert(p and finite(p.X) and finite(p.Y) and finite(p.Z),"Invalid player position")
    return {X=p.X,Y=p.Y,Z=p.Z}
end
local function rotation(context)
    pawn_ok(context)
    local r=context.pawn:K2_GetActorRotation()
    assert(r and finite(r.Pitch) and finite(r.Yaw) and finite(r.Roll),"Invalid player rotation")
    return {Pitch=r.Pitch,Yaw=r.Yaw,Roll=r.Roll}
end
local function move(context,target)
    return_usable(context)
    assert(target and finite(target.X) and finite(target.Y) and finite(target.Z),"Invalid return target")
    context.pawn:K2_SetActorLocation({X=target.X,Y=target.Y,Z=target.Z},false,{},true)
    -- Post-read uses raw capture so a HUD transition cannot make a successful move look failed.
    local p=capture(context)
    local d=math.sqrt((p.X-target.X)^2+(p.Y-target.Y)^2+(p.Z-target.Z)^2)
    if d>10 then
        return false,"Return did not reach saved point; stopped "..string.format("%.1f",d).." uu away.",p
    end
    return true,"Eve returned to the stored position.",p
end
local function guarded(fn,...)
    local ok,a,b,c=xpcall(fn,debug.traceback,...)
    if ok then return a,b,c end
    UE.log("POSITION API ERROR "..tostring(a))
    return nil,tostring(a),nil
end
function Bridge.new()
    return {
        capture=function(c) return guarded(capture,c) end,
        position=function(c) return guarded(capture,c) end,
        rotation=function(c) return guarded(rotation,c) end,
        move=function(c,p) return guarded(move,c,p) end,
    }
end
return Bridge
