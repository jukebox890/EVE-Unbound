local UE=require("UE")
local API={now=os.time,log=UE.log}
local function record(m)
    if not UE.valid(m) or not m:IsA("/Script/SB.SBCharacterMovementComponent") then return nil end
    local pawn=m:GetOuter()
    if not UE.valid(pawn) or not pawn:IsA("/Script/SB.SBCharacter") then return nil end
    return {object=m,path=UE.path(m),address=m:GetAddress(),owner=UE.path(pawn),owner_address=pawn:GetAddress(),
        value=UE.read(m,"SprintSpeedScale")}
end
function API.read(saved) return record(saved.object) end
function API.write(saved,value)
    local m=saved.object;local r=record(m)
    if not r or r.address~=saved.address or r.owner~=saved.owner or r.owner_address~=saved.owner_address then return false end
    m.SprintSpeedScale=value
    local actual=UE.read(m,"SprintSpeedScale")
    return type(actual)=="number" and math.abs(actual-value)<=math.max(0.00001,math.abs(value)*0.00001)
end
function API.inspect(context)
    if not context or not UE.valid(context.pawn) then return nil,"No controlled player" end
    local pawn=context.pawn
    if not pawn:IsA("/Script/SB.SBCharacter") then return nil,"Not an SBCharacter" end
    if UE.read(pawn,"bBattleState")~=false then return nil,"Combat active or combat flag unavailable" end
    if UE.read(pawn,"bLockOn")~=false then return nil,"Lock-on active or flag unavailable" end
    local hud=UE.hud(context)
    if not UE.valid(hud) then return nil,"Gameplay HUD unavailable" end
    local health,why=UE.health(context)
    if not health or health.percent<=0 then return nil,why or "Player HP is zero" end
    local m=UE.read(pawn,"CharacterMovement")
    if UE.read(m,"MovementMode")~=1 then return nil,"Ground walking required" end
    local r=record(m)
    if not r or r.owner_address~=pawn:GetAddress() then return nil,"Owned SB movement component unavailable" end
    return r
end
return API
