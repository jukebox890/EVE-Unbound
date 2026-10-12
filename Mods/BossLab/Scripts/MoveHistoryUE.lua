-- Focused defensive input adapter.
-- Only E / LeftShift / W / S are sampled. LMB/RMB, jump, A/D and ordinary movement
-- are intentionally excluded. All reads run inside BossLab's ONE serialized game-thread
-- dispatcher; there is no independent ExecuteInGameThread sampler.
local UE=require("UE")
local Bridge={};Bridge.__index=Bridge

local FRIENDLY={LeftShift="Shift"}
local RAW_DEFAULTS={guard={"E"},evade={"LeftShift"},forward={"W"},back={"S"}}
local SLOTS={"guard","evade","forward","back"}
local function friendly(key) return FRIENDLY[key] or tostring(key) end

function Bridge.new(config,hud)
    return setmetatable({config=config,hud=hud,context=nil,pc=nil,pawn=nil,hpbar=nil,key_objects={}},Bridge)
end

function Bridge:stop()
    self.context=nil;self.pc=nil;self.pawn=nil;self.hpbar=nil;self.key_objects={}
    if self.hud then self.hud:remove() end
end

function Bridge:_resolve_hpbar(context)
    local hud=UE.hud_cached and UE.hud_cached(context) or UE.hud(context)
    local info=UE.valid(hud) and UE.read(hud,"WB_MainHUD_PlayerInfo") or nil
    local bar=UE.read(info,"ProgressBar_HP")
    if UE.valid(bar) then return bar end
end

function Bridge:start(context)
    assert(context and UE.valid(context.pc) and UE.valid(context.pawn),"Move history requires live player context")
    self.context=context;self.pc=context.pc;self.pawn=context.pawn
    self.hpbar=self:_resolve_hpbar(context)
    self.key_objects={}
    for _,slot in ipairs(SLOTS) do
        for _,key in ipairs(RAW_DEFAULTS[slot] or {}) do
            if not self.key_objects[key] then self.key_objects[key]={KeyName=FName(key)} end
        end
    end
    return self:binding_summary()
end

function Bridge:binding_summary()
    return "E block • Shift dodge • W→Shift blue • S→Shift violet | no mouse/jump/noise"
end

-- Lua-side monotonic process clock: no reflected call on each 33 ms sample.
function Bridge:time() return os.clock() end

function Bridge:_key_down(key)
    if not UE.valid(self.pc) then return false end
    local fk=self.key_objects[key]
    if not fk then return false end
    local ok,down=pcall(function() return self.pc:IsInputKeyDown(fk) end)
    return ok and down==true
end

function Bridge:inputs()
    assert(UE.valid(self.pc),"Move-history controller unavailable")
    local state={}
    for _,slot in ipairs(SLOTS) do
        local key=(RAW_DEFAULTS[slot] or {})[1]
        state[slot]={down=key and self:_key_down(key) or false,key=key and friendly(key) or slot}
    end
    return state
end

-- Cached HP bar read is intentionally tiny enough to run with the 33 ms input sample.
-- When Player Invulnerability prevents HP loss, there is simply no HP-drop timing event.
function Bridge:hp()
    if not UE.valid(self.hpbar) then return nil end
    local ok,p=pcall(function() return self.hpbar.Percent end)
    if ok and type(p)=="number" and p==p and p>=0 and p<=1 then return p end
end

-- Slow path only: repair the cached HP widget and redraw/revalidate the history HUD.
function Bridge:maintenance()
    if self.context and not UE.valid(self.hpbar) then self.hpbar=self:_resolve_hpbar(self.context) end
    return UE.valid(self.hpbar)
end

function Bridge:update(context,text) return self.hud:update(context or self.context,text) end
function Bridge:remove() self.hud:remove() end

return Bridge
