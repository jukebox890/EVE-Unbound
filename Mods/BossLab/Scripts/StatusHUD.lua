-- Tiny click-through status line for tools that matter while the full menu is closed.
local UE=require("UE")
local HUD={};HUD.__index=HUD

function HUD.new(config)
    return setmetatable({config=config,text=nil,owner=nil,last=nil,token=nil},HUD)
end

function HUD:forget()
    self.text=nil;self.heading=nil;self.owner=nil;self.last=nil;self.token=nil
end

function HUD:remove()
    if UE.valid(self.heading) then pcall(function() self.heading:RemoveFromParent() end) end
    if UE.valid(self.text) then pcall(function() self.text:RemoveFromParent() end) end
    self:forget()
end

local function construct_text(tree,config)
    local class=UE.find("/Script/UMG.TextBlock")
    assert(UE.valid(class) and UE.valid(tree),"Status TextBlock class/widget tree unavailable")
    local text=StaticConstructObject(class,tree)
    assert(UE.valid(text),"Status TextBlock construction failed")
    text:SetVisibility(3) -- HitTestInvisible
    text:SetColorAndOpacity({SpecifiedColor={R=0.55,G=1.0,B=0.68,A=1},ColorUseRule=0})
    text:SetShadowOffset({X=1,Y=1})
    text:SetShadowColorAndOpacity({R=0,G=0,B=0,A=0.95})
    pcall(function() text.Font.Size=config.StatusFontSize end)
    return text
end

function HUD:update(context,message)
    if not message or message=="" then
        if self.text then self:remove() end
        return true
    end
    if not context then self:remove();return false,"No player context" end
    local heading,body=message:match("^([^\n]+)\n(.*)$")
    heading=heading or message;message=body or ""
    local hud=(UE.hud_cached and UE.hud_cached(context)) or UE.hud(context)
    if not UE.valid(hud) then self:forget();return false,"Gameplay HUD unavailable" end
    local owner=UE.read(hud,"CanvasPanel_Root")
    local tree=UE.read(hud,"WidgetTree")
    if not UE.valid(owner) or not UE.valid(tree) then self:forget();return false,"HUD root unavailable" end
    local owner_id=owner:GetAddress()
    if not UE.valid(self.text) or self.owner~=owner_id or self.token~=context.token then
        self:forget() -- old root may already be torn down
        local text=construct_text(tree,self.config)
        local slot=owner:AddChildToCanvas(text)
        assert(UE.valid(slot),"Status Canvas slot unavailable")
        slot:SetPosition({X=self.config.StatusX,Y=self.config.StatusY+30})
        slot:SetSize({X=self.config.StatusWidth,Y=self.config.StatusHeight})
        slot:SetZOrder(950)
        local title=construct_text(tree,self.config)
        title:SetText(FText(heading))
        title:SetColorAndOpacity({SpecifiedColor={R=0.12,G=0.42,B=0.26,A=1},ColorUseRule=0})
        pcall(function() title.Font.TypefaceFontName=FName("Bold") end)
        local title_slot=owner:AddChildToCanvas(title)
        title_slot:SetPosition({X=self.config.StatusX,Y=self.config.StatusY})
        title_slot:SetSize({X=self.config.StatusWidth,Y=30});title_slot:SetZOrder(950)
        self.heading=title;self.text=text;self.owner=owner_id;self.token=context.token;self.last=nil
    end
    if self.last~=message then
        self.text:SetText(FText(message))
        self.last=message
    end
    return true
end

return HUD
