-- Compact defense feed centered below the boss HUD.
-- Redraws occur only from the serialized slow path. Every redraw revalidates the
-- current gameplay HUD/root before touching the cached TextBlock; there is no stale
-- fast path that writes directly to a previously cached widget.
local UE=require("UE")
local HUD={};HUD.__index=HUD

function HUD.new(config)
    return setmetatable({config=config,text=nil,owner=nil,token=nil,last=nil},HUD)
end

function HUD:forget()
    self.text=nil;self.owner=nil;self.token=nil;self.last=nil
end

function HUD:remove()
    if UE.valid(self.text) then pcall(function() self.text:RemoveFromParent() end) end
    self:forget()
end

-- Used when the gameplay HUD/root has disappeared or changed. Do not call a method
-- on a widget that may belong to a torn-down UMG tree; simply drop our Lua references.
function HUD:abandon()
    self:forget()
end

local function construct_text(tree,config)
    local class=UE.find("/Script/UMG.TextBlock")
    assert(UE.valid(class) and UE.valid(tree),"Move-history TextBlock class/widget tree unavailable")
    local text=StaticConstructObject(class,tree)
    assert(UE.valid(text),"Move-history TextBlock construction failed")
    text:SetVisibility(3) -- HitTestInvisible
    text:SetColorAndOpacity({SpecifiedColor={R=0.80,G=0.96,B=1.0,A=0.96},ColorUseRule=0})
    text:SetShadowOffset({X=1,Y=1})
    text:SetShadowColorAndOpacity({R=0,G=0,B=0,A=0.95})
    pcall(function() text.Font.Size=config.MoveHistoryFontSize or 16 end)
    return text
end

function HUD:set_suppressed(value,context)
    self.suppressed=value==true
    if not self.text then return end
    local hud=context and UE.hud_cached and UE.hud_cached(context) or nil
    local root=UE.read(hud,"CanvasPanel_Root")
    if not context or context.token~=self.token or not UE.valid(root) or root:GetAddress()~=self.owner then
        self:abandon();return
    end
    if UE.valid(self.text) then pcall(function() self.text:SetVisibility(self.suppressed and 1 or 3) end) end
end
function HUD:update(context,message)
    if self.suppressed then return true end
    if not message or message=="" then self:remove();return true end
    if not context then self:remove();return false,"No player context" end
    local hud=(UE.hud_cached and UE.hud_cached(context)) or UE.hud(context)
    if not UE.valid(hud) then self:abandon();return false,"Gameplay HUD unavailable" end
    local owner=UE.read(hud,"CanvasPanel_Root")
    local tree=UE.read(hud,"WidgetTree")
    if not UE.valid(owner) or not UE.valid(tree) then self:abandon();return false,"HUD root unavailable" end
    local owner_id=owner:GetAddress()
    if not UE.valid(self.text) or self.owner~=owner_id or self.token~=context.token then
        -- If the root/token changed, the previous widget may already belong to a dead
        -- tree. Drop the reference rather than invoking RemoveFromParent on it.
        self:abandon()
        local text=construct_text(tree,self.config)
        local slot=owner:AddChildToCanvas(text)
        assert(UE.valid(slot),"Move-history Canvas slot unavailable")
        if self.config.MoveHistoryCentered then
            slot:SetAnchors({Minimum={X=0.5,Y=0},Maximum={X=0.5,Y=0}})
            slot:SetAlignment({X=0.5,Y=0})
        end
        slot:SetPosition({X=self.config.MoveHistoryX or 0,Y=self.config.MoveHistoryY or 240})
        slot:SetSize({X=self.config.MoveHistoryWidth or 1050,Y=self.config.MoveHistoryHeight or 320})
        slot:SetZOrder(940)
        self.text=text;self.owner=owner_id;self.token=context.token;self.last=nil
    end
    if self.last~=message then
        self.text:SetText(FText(message))
        self.last=message
    end
    return true
end

return HUD
