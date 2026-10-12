-- EVE Unbound menu. Native UMG widgets with keyboard controls.
local UE=require("UE")
local Panel={};Panel.__index=Panel
local WHITE={R=0.87,G=0.92,B=0.88,A=1}
local MINT={R=0.42,G=0.86,B=0.64,A=1}
local MUTED={R=0.44,G=0.53,B=0.48,A=1}
local GOLD={R=0.77,G=0.70,B=0.45,A=1}
local rows={
    {"player_invuln","Num .","Player invulnerability",210,"general"},
    {"resources","Alt+Num 5","Resources",242,"general"},
    {"speed","Num *","Sprint · outside combat",274,"general"},
    {"position_save","Num 3","Save position",306,"general"},
    {"position_return","Num 4","Return to position",338,"general"},
    {"damage","Num +","Damage ×1000",370,"general"},
    {"damage_duration","Num /","Damage duration",402,"general"},
    {"dodge","Num 1","Dodge slow-mo",434,"general"},
    {"nohit","Num 7","No-hit run",534,"boss"},
    {"boss_invuln","Num -","Enemy invulnerability",566,"boss"},
    {"feed","Num 5","Defense feed",598,"boss"},
    {"record","Num 2","Auto record",630,"boss"},
    {"export","Num 8","Export fights",662,"boss"},
}
Panel.rows=rows
function Panel.new(config,directory,logger)
    return setmetatable({config=config,directory=directory,log=logger or function() end,widgets={},last={}},Panel)
end
local function construct(kind,tree)
    local class=UE.find("/Script/UMG."..kind);assert(UE.valid(class),"Missing UMG "..kind)
    local obj=StaticConstructObject(class,tree);assert(UE.valid(obj),"Cannot construct "..kind)
    obj:SetVisibility(3);return obj
end
local function place(canvas,obj,x,y,w,h,z)
    local slot=canvas:AddChildToCanvas(obj);assert(UE.valid(slot),"Cannot attach menu widget")
    slot:SetPosition({X=x,Y=y});slot:SetSize({X=w,Y=h});slot:SetZOrder(z or 2)
end
local function color(text,c) text:SetColorAndOpacity({SpecifiedColor=c,ColorUseRule=0}) end
local function text(canvas,tree,value,x,y,w,h,size,c,bold)
    local obj=construct("TextBlock",tree)
    pcall(function() obj.Font.Size=size end)
    if bold then pcall(function() obj.Font.TypefaceFontName=FName("Bold") end) end
    obj:SetText(FText(value));color(obj,c or WHITE)
    obj:SetShadowOffset({X=1,Y=1});obj:SetShadowColorAndOpacity({R=0,G=0,B=0,A=0.6})
    place(canvas,obj,x,y,w,h);return obj
end
-- Optional, read-only viewport sizing. Keep the whole menu visible without a
-- scroll container; use the normal layout if this engine helper is unavailable.
function Panel.fit_scale(context,config)
    local ok,scale=pcall(function()
        local lib=UE.find("/Script/UMG.Default__WidgetLayoutLibrary")
        if not UE.valid(lib) then return 1 end
        local size=lib:GetViewportSize(context.world)
        local x,y=size.X,size.Y -- copy the returned struct's scalar fields immediately
        local dpi=lib:GetViewportScale(context.world)
        if type(x)~="number" or type(y)~="number" or type(dpi)~="number"
            or x~=x or y~=y or dpi~=dpi or x<=0 or y<=0 or dpi<=0 then return 1 end
        local available_x=x/dpi-math.max(0,config.PanelX)-24
        local available_y=y/dpi-math.max(0,config.PanelY)-24
        if available_x<=0 or available_y<=0 then return 1 end
        return math.min(1,available_x/config.PanelWidth,available_y/config.PanelHeight)
    end)
    return ok and scale or 1
end
function Panel:remove()
    if UE.valid(self.border) then pcall(function() self.border:RemoveFromParent() end) end
    self.border=nil;self.canvas=nil;self.texture=nil;self.widgets={};self.last={};self.token=nil;self.owner=nil;self.root_owner=nil;self.scale=nil
end
function Panel:open(context,hud,data)
    self:remove()
    local tree=UE.read(hud,"WidgetTree");local root=UE.read(hud,"CanvasPanel_Root")
    assert(UE.valid(tree) and UE.valid(root),"HUD tree unavailable")
    local border=construct("Border",tree);self.border=border
    border:SetBrushColor({R=0.012,G=0.025,B=0.019,A=0})
    border:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
    local canvas=construct("CanvasPanel",tree);border:SetContent(canvas);self.canvas=canvas
    local width,height=self.config.PanelWidth,self.config.PanelHeight
    -- Assemble off-tree, then attach once. Generated Eve stays right of text.
    local ok,why=pcall(function()
        local lib=UE.find("/Script/Engine.Default__KismetRenderingLibrary")
        assert(UE.valid(lib),"image importer unavailable")
        local texture=lib:ImportFileAsTexture2D(context.world,self.directory.."Assets/EveDivineMenu.png")
        assert(UE.valid(texture),"image import failed")
        local image=construct("Image",tree);image:SetBrushFromTexture(texture,false)
        image:SetColorAndOpacity({R=1,G=1,B=1,A=0.70})
        place(canvas,image,0,0,width,height,0);self.texture=texture
    end)
    if not ok then border:SetBrushColor({R=0.012,G=0.025,B=0.019,A=0.70});self.log("MENU ART | "..tostring(why).." | using plain translucent panel") end
    local shade=construct("Border",tree);shade:SetBrushColor({R=0.008,G=0.019,B=0.013,A=0})
    place(canvas,shade,0,0,width*0.58,height,1)
    local rule=construct("Border",tree);rule:SetBrushColor({R=0.3,G=0.7,B=0.46,A=0.7})
    place(canvas,rule,34,82,752,1,2)
    text(canvas,tree,"EVE UNBOUND",32,22,650,48,32,WHITE,true)
    text(canvas,tree,"V1.0",580,38,210,24,12,MUTED)
    text(canvas,tree,"ACTIVE",34,94,740,20,12,GOLD,true)
    self.widgets.active=text(canvas,tree,"",34,118,752,50,15,MINT)
    text(canvas,tree,"GENERAL",34,176,740,24,14,GOLD,true)
    local divider=construct("Border",tree);divider:SetBrushColor({R=0.30,G=0.45,B=0.36,A=0.55})
    place(canvas,divider,34,480,752,1,2)
    text(canvas,tree,"BOSS PRACTICE",34,494,210,24,14,GOLD,true)
    text(canvas,tree,"Also works in story encounters",265,496,520,24,12,MUTED)
    for _,row in ipairs(rows) do
        text(canvas,tree,row[3],34,row[4],355,30,18,WHITE)
        self.widgets[row[1]]=text(canvas,tree,"",405,row[4],225,30,18,MINT)
        text(canvas,tree,row[2],645,row[4]+3,145,26,13,MUTED)
    end
    self.widgets.footer=text(canvas,tree,"",34,738,752,50,13,MUTED)
    self.scale=Panel.fit_scale(context,self.config)
    if self.scale<1 then
        local scaled=pcall(function()
            border:SetRenderTransformPivot({X=0,Y=0})
            border:SetRenderScale({X=self.scale,Y=self.scale})
        end)
        if not scaled then self.scale=1 end
    end
    place(root,border,self.config.PanelX,self.config.PanelY,width,height,900)
    self.token=context.token;self.owner=hud:GetAddress();self.root_owner=root:GetAddress()
    self:update(data)
    return true
end
function Panel:valid(context,hud)
    return context and context.token==self.token and UE.valid(hud) and hud:GetAddress()==self.owner and UE.valid(self.border) and UE.valid(UE.read(hud,"CanvasPanel_Root"))
        and UE.read(hud,"CanvasPanel_Root"):GetAddress()==self.root_owner
end
function Panel:update(data)
    for key,widget in pairs(self.widgets) do
        assert(UE.valid(widget),"Menu widget no longer valid")
        local item=data[key] or ""
        local value=type(item)=="table" and item.text or tostring(item)
        local enabled=nil
        if type(item)=="table" then enabled=item.on end
        local signature=value..":"..tostring(enabled)
        if self.last[key]~=signature then
            widget:SetText(FText(value))
            if enabled~=nil then color(widget,enabled and MINT or MUTED) end
            self.last[key]=signature
        end
    end
end
return Panel
