-- Focused defensive move history.
-- Scope is deliberately narrow: E block, standalone Shift dodge, W->Shift blue,
-- S->Shift violet. No LMB/RMB, jump, A/D, or ordinary movement entries.
-- Sampling remains in the single serialized BossLab game-thread dispatcher.
local Move={};Move.__index=Move
local SLOTS={"guard","evade","forward","back"}
local function round_ms(seconds) return math.floor(seconds*1000+0.5) end
local function safe_key(s,key) return (s[key] and s[key].key) or key end

function Move.new(api,config,logger)
    return setmetatable({api=api,config=config,log=logger or function() end,
        enabled=config.MoveHistoryDefaultOn==true,sampling=false,token=nil,context=nil,start_time=nil,
        held={},held_since={},events={},serial=0,last_hp=nil,damage=nil,last_defense=nil,recent_evade=nil,
        counters={block=0,dodge=0,blue=0,violet=0,reversed=0,ambiguous=0},
        binding_summary="bindings unavailable",last="Defense feed OFF",
        last_heartbeat_at=-1,dirty=false},Move)
end

local function compact(text)
    return (text:gsub("E BLOCK","Block"):gsub("SHIFT DODGE","Dodge")
        :gsub("BLUE INPUT","Blue"):gsub("VIOLET INPUT","Violet")
        :gsub("BLUE WRONG ORDER","Blue reversed"):gsub("VIOLET WRONG ORDER","Violet reversed")
        :gsub("SAME 33 ms SAMPLE / ORDER AMBIGUOUS","order unclear")
        :gsub("  •  ORDER OK",""):gsub("before HP drop","before hit")
        :gsub("after HP drop","after hit"):gsub("no recent E/Shift attempt","no defense input"))
end
function Move:_line(event) return string.format("%5.1fs  %s",event.rel or 0,compact(event.text or "")) end
function Move:_render()
    local lines={"DEFENSE FEED",""}
    if #self.events==0 then lines[#lines+1]="Block · Dodge · Blue · Violet" end
    local shown=0
    for i=#self.events,1,-1 do
        lines[#lines+1]=self:_line(self.events[i]);shown=shown+1
        if shown>=(self.config.MoveHistoryLines or 10) then break end
    end
    return table.concat(lines,"\n")
end
function Move:_redraw()
    if not self.sampling or not self.context then return end
    local ok,why=pcall(function() return self.api:update(self.context,self:_render()) end)
    if not ok or why==false then self.log("HUD ERROR | "..tostring(why)) end
end
function Move:_push(text,t,kind)
    local c=self.counters
    if kind=="guard" then c.block=c.block+1 elseif kind=="evade" then c.dodge=c.dodge+1
    elseif kind=="order" then
        if text:find("BLUE",1,true) then c.blue=c.blue+1 else c.violet=c.violet+1 end
        if text:find("AMBIGUOUS",1,true) then c.ambiguous=c.ambiguous+1 end
    end
    self.serial=self.serial+1
    local e={id=self.serial,time=t,rel=(self.start_time and t-self.start_time or 0),text=text,kind=kind}
    self.events[#self.events+1]=e
    local cap=self.config.MoveHistoryStoredEvents or self.config.MoveHistoryLines or 10
    if #self.events>cap then table.remove(self.events,1) end
    self.dirty=true;return e
end
function Move:_update(event,text)
    if not event or event.text==text then return end
    event.text=text;self.dirty=true
end
function Move:clear(reason)
    self.events={};self.serial=0;self.damage=nil;self.last_defense=nil;self.recent_evade=nil
    self.last="Move history cleared: "..tostring(reason or "manual");self.dirty=true
end
function Move:stop(reason)
    self.sampling=false;self.token=nil;self.context=nil;self.start_time=nil;self.held={};self.held_since={}
    self.last_hp=nil;self.damage=nil;self.last_defense=nil;self.recent_evade=nil;self.last_heartbeat_at=-1;self.dirty=false
    pcall(function() self.api:remove() end)
end
function Move:start(context)
    if not self.enabled then return false end
    local ok,summary=xpcall(function() return self.api:start(context) end,debug.traceback)
    if not ok then self.last="Move history start failed: "..tostring(summary);self.log("START ERROR | "..tostring(summary));return false end
    local okt,t=xpcall(function() return self.api:time() end,debug.traceback)
    if not okt or type(t)~="number" then self.last="Move history clock unavailable";return false end
    self.context=context;self.token=context.token;self.start_time=t;self.binding_summary=tostring(summary)
    self.held={};self.held_since={};self.events={};self.serial=0;self.damage=nil;self.last_defense=nil;self.recent_evade=nil
    self.last_heartbeat_at=t;self.dirty=true
    local okin,state=xpcall(function() return self.api:inputs() end,debug.traceback)
    if okin and type(state)=="table" then
        for _,slot in ipairs(SLOTS) do local down=state[slot] and state[slot].down==true;self.held[slot]=down;if down then self.held_since[slot]=t end end
    end
    pcall(function() self.api:maintenance() end)
    local okhp,hp=xpcall(function() return self.api:hp() end,debug.traceback);self.last_hp=okhp and hp or nil
    self.sampling=true;self.last="Defense feed LIVE | "..self.binding_summary
    return true
end
function Move:toggle(context,battle)
    self.enabled=not self.enabled
    if not self.enabled then self:stop("disabled by Num 5");self.last="Defense feed OFF";return false end
    self.last="Defense feed ON; waiting for combat."
    if battle==true and context then self:start(context) end
    return true
end
function Move:resync(reason)
    if not self.sampling then return false end
    local okt,t=xpcall(function() return self.api:time() end,debug.traceback)
    local okin,state=xpcall(function() return self.api:inputs() end,debug.traceback)
    if not okt or type(t)~="number" or not okin or type(state)~="table" then self.log("RESYNC ERROR | "..tostring(reason or "resume"));return false end
    self.held={};self.held_since={}
    for _,slot in ipairs(SLOTS) do local down=state[slot] and state[slot].down==true;self.held[slot]=down;if down then self.held_since[slot]=t end end
    self.damage=nil;self.last_defense=nil;self.recent_evade=nil;self.last_heartbeat_at=t
    local okhp,hp=xpcall(function() return self.api:hp() end,debug.traceback);self.last_hp=okhp and hp or nil
    self.dirty=true;return true
end
function Move:summary() return (self.enabled and "ON" or "OFF").." | "..(self.sampling and "LIVE" or "waiting").." | "..self.binding_summary end

-- HP-loss timing is deliberately factual. We do not infer a perfect-parry window.
function Move:_defense_text(hit_t)
    local d=self.last_defense
    if not d or hit_t-d.time>(self.config.MoveHistoryDefenseLookbackMs or 800)/1000 then return "no recent E/Shift attempt" end
    local before=round_ms(hit_t-d.time)
    return string.format("%s %d ms before HP drop",d.label,before)
end
function Move:_damage_text(d)
    local loss=math.max(0,(d.base-d.min)*100);local tail=d.timing or ""
    if d.late then tail=string.format("%s %d ms after HP drop",d.late.label,d.late.ms) end
    return string.format("HIT  -%.2f%%  •  %s",loss,tail)
end
function Move:_record_defense(action,state,t)
    local label=action=="guard" and "E BLOCK" or "SHIFT DODGE"
    self.last_defense={action=action,label=label,time=t,key=safe_key(state,action)}
    if self.damage and t>=self.damage.start and t-self.damage.start<=(self.config.MoveHistoryLateLookaheadMs or 180)/1000 then
        self.damage.late={label=label,ms=round_ms(t-self.damage.start)};self:_update(self.damage.event,self:_damage_text(self.damage))
    end
end
function Move:_classify_wrong_order(direction,state,t)
    local r=self.recent_evade
    if not r then return false end
    local ms=round_ms(t-r.time)
    local label=direction=="forward" and "BLUE" or "VIOLET"
    self.counters.reversed=self.counters.reversed+1
    -- Shift was already counted as a dodge input. Keep monotonic counters for
    -- attempt deltas; reversed direction is an additional observed classification.
    local key=safe_key(state,direction)
    self:_update(r.event,string.format("%s WRONG ORDER  %s → %s  +%d ms",label,r.key,key,ms))
    r.event.kind="order"
    if self.last_defense and self.last_defense.action=="evade" and self.last_defense.time==r.time then
        self.last_defense.label="SHIFT"
    end
    self.recent_evade=nil
    return true
end
function Move:_process_inputs(state,t)
    local rising={}
    for _,slot in ipairs(SLOTS) do
        local down=state[slot] and state[slot].down==true
        if down and not self.held[slot] then rising[slot]=true;self.held_since[slot]=t end
        if not down and self.held[slot] then self.held_since[slot]=nil end
    end

    if rising.guard then
        self:_record_defense("guard",state,t)
        self:_push("E BLOCK",t,"guard")
    end

    local order_window=(self.config.MoveHistoryOrderWindowMs or 180)/1000
    if self.recent_evade and t-self.recent_evade.time>order_window then self.recent_evade=nil end

    -- If Shift was pressed first and W/S follows quickly, convert that single Shift
    -- event into a wrong-order Blue/Violet diagnostic instead of adding duplicate noise.
    if self.recent_evade and not rising.evade then
        if rising.forward then self:_classify_wrong_order("forward",state,t)
        elseif rising.back then self:_classify_wrong_order("back",state,t) end
    end

    if rising.evade then
        local evade=safe_key(state,"evade")
        if rising.forward then
            self:_push(string.format("BLUE INPUT  %s + %s  •  SAME 33 ms SAMPLE / ORDER AMBIGUOUS",safe_key(state,"forward"),evade),t,"order")
            self.recent_evade=nil
        elseif state.forward and state.forward.down and self.held_since.forward and self.held_since.forward<t then
            local held=round_ms(t-self.held_since.forward)
            self:_push(string.format("BLUE INPUT  %s → %s  +%d ms  •  ORDER OK",safe_key(state,"forward"),evade,held),t,"order")
            self.recent_evade=nil
        elseif rising.back then
            self:_push(string.format("VIOLET INPUT  %s + %s  •  SAME 33 ms SAMPLE / ORDER AMBIGUOUS",safe_key(state,"back"),evade),t,"order")
            self.recent_evade=nil
        elseif state.back and state.back.down and self.held_since.back and self.held_since.back<t then
            local held=round_ms(t-self.held_since.back)
            self:_push(string.format("VIOLET INPUT  %s → %s  +%d ms  •  ORDER OK",safe_key(state,"back"),evade,held),t,"order")
            self.recent_evade=nil
        else
            self:_record_defense("evade",state,t)
            local event=self:_push("SHIFT DODGE",t,"evade")
            self.recent_evade={time=t,key=evade,event=event}
        end
    end

    for _,slot in ipairs(SLOTS) do self.held[slot]=state[slot] and state[slot].down==true or false end
end
function Move:_process_hp(hp,t)
    if type(hp)~="number" then return end
    local eps=(self.config.MoveHistoryHPEpsilon or 0.0005)
    if self.last_hp==nil then self.last_hp=hp;return end
    if hp<self.last_hp-eps then
        if not self.damage or t-self.damage.last_drop>(self.config.MoveHistoryDamageGroupMs or 300)/1000 then
            local d={start=t,last_drop=t,base=self.last_hp,min=hp,timing=self:_defense_text(t)};d.event=self:_push(self:_damage_text(d),t,"damage");self.damage=d
        else self.damage.min=math.min(self.damage.min,hp);self.damage.last_drop=t;self:_update(self.damage.event,self:_damage_text(self.damage)) end
    elseif self.damage and t-self.damage.last_drop>(self.config.MoveHistoryDamageGroupMs or 300)/1000 then self.damage=nil end
    self.last_hp=hp
end

-- Serialized 33 ms path: four key reads + one cached HP-bar scalar read only.
function Move:tick()
    if not self.sampling then return false end
    local t=self.api:time();if type(t)~="number" then self:stop("clock unavailable");return false end
    local okin,state=xpcall(function() return self.api:inputs() end,debug.traceback)
    if not okin or type(state)~="table" then self.log("INPUT ERROR | "..tostring(state));self:stop("input unavailable");return false end
    self:_process_inputs(state,t)
    local okhp,hp=xpcall(function() return self.api:hp() end,debug.traceback)
    if okhp then self:_process_hp(hp,t) end
    return true
end

-- Low-rate maintenance/redraw path only; no second input sampler.
function Move:slow_tick()
    if not self.sampling then return false end
    local t=self.api:time();if type(t)~="number" then return false end
    pcall(function() if self.api.maintenance then self.api:maintenance() end end)
    if self.dirty or self.last_heartbeat_at<0 or t-self.last_heartbeat_at>=0.5 then
        self.last_heartbeat_at=t;self.dirty=false;self:_redraw()
    end
    return true
end
return Move
