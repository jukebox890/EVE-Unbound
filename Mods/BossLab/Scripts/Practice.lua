-- Original engine-independent practice state. No combat-stat writes.
local Practice={};Practice.__index=Practice
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
function Practice.new(api,config)
    return setmetatable({api=api,config=config,attempt=nil,history={},serial=0,last="Recorder idle."},Practice)
end
function Practice:busy() return self.attempt~=nil end
function Practice:finish(reason,now)
    local a=self.attempt
    if not a then return end
    if finite(now) and now>=a.last_time then a.last_time=now end
    a.seconds=math.max(0,a.last_time-a.started)
    a.clean_seconds=math.max(a.clean_seconds,a.last_time-a.clean_start)
    a.reason=reason or "manual stop"
    a.hp_end=a.last_hp;a.raw_hp_end=a.last_raw_hp
    a.average_hp=a.observed_seconds>0 and a.hp_area/a.observed_seconds or a.hp_start
    a.net_hp_change=a.hp_end-a.hp_start
    a.healing_per_minute=a.observed_seconds>0 and a.hp_recovered*60/a.observed_seconds or 0
    a.loss_per_minute=a.observed_seconds>0 and a.hp_lost*60/a.observed_seconds or 0
    a.last_time=nil;a.last_hp=nil;a.max_hp=nil;a.clean_start=nil;a.last_drop=nil
    self.history[#self.history+1]=a
    while #self.history>self.config.MaxAttempts do table.remove(self.history,1) end
    self.attempt=nil
    self.last="Attempt "..a.id.." ended: "..a.reason..". Num 8 exports history."
end
function Practice:reset(reason)
    self:finish(reason or "reset")
end
function Practice:start(context)
    local s,err=self.api.sample(context)
    if not s or not finite(s.time) or not finite(s.hp) or not finite(s.max_hp)
        or s.max_hp<=0 or s.hp<=0 or s.hp>s.max_hp then
        self.last=err or "Recording unavailable: live HUD HP / game clock not readable."
        return false
    end
    self.serial=self.serial+1
    self.attempt={id=self.serial,token=context.token,world=s.world or "",started=s.time,
        last_time=s.time,last_hp=s.hp,max_hp=s.max_hp,drops=0,hp_lost=0,
        hp_start=s.hp,hp_end=s.hp,hp_min=s.hp,hp_max=s.hp,hp_recovered=0,recovery_events=0,
        samples=1,observed_seconds=0,hp_area=0,low_hp_seconds=0,combat_seconds=0,lockon_seconds=0,max_sample_gap=0,
        raw_hp_start=s.raw_hp,last_raw_hp=s.raw_hp,raw_max_hp=s.raw_max_hp,
        health_source=s.health_source or "unknown",health_source_last=s.health_source or "unknown",
        unit=s.unit or "percentage points",boss_challenge=s.boss_challenge,
        tools_start=s.tools or "",tools_end=s.tools or "",tools_seen={},
        tool_action_requests=0,manual_marks=0,teleports=0,
        defense_start=s.defense or {},defense_end=s.defense or {},last_battle=s.battle,last_lockon=s.lockon,
        clean_start=s.time,clean_seconds=0,gaps=0,started_utc=os.date("!%Y-%m-%dT%H:%M:%SZ")}
    self.attempt.tools_seen[self.attempt.tools_start]=true
    self.last="Recording grouped HUD damage events; these are not exact hit counts."
    return true
end
function Practice:tick(context)
    local a=self.attempt
    if a then
        if not context or context.token~=a.token then self:reset("context changed");return end
        local s,err=self.api.sample(context)
        if not s or not finite(s.time) or not finite(s.hp) or not finite(s.max_hp)
            or s.max_hp<=0 or s.hp<0 or s.hp>s.max_hp then
            self:finish("HUD/clock unavailable")
            self.last=self.last.." "..tostring(err or "Invalid HP/time sample")
            return
        end
        if s.time<a.last_time then self:reset("game clock reset");return end
        local gap=s.time-a.last_time
        a.samples=a.samples+1;a.max_sample_gap=math.max(a.max_sample_gap,gap)
        a.hp_min=math.min(a.hp_min,s.hp);a.hp_max=math.max(a.hp_max,s.hp)
        a.tools_end=s.tools or a.tools_end;a.tools_seen[a.tools_end]=true
        a.defense_end=s.defense or a.defense_end;a.last_raw_hp=s.raw_hp
        local source=s.health_source or "unknown"
        local discontinuity=gap>self.config.SampleGapSeconds or s.max_hp~=a.max_hp
            or source~=a.health_source_last or (s.raw_max_hp~=nil and a.raw_max_hp~=nil and s.raw_max_hp~=a.raw_max_hp)
        if not discontinuity then
            a.observed_seconds=a.observed_seconds+gap
            a.hp_area=a.hp_area+(a.last_hp+s.hp)*0.5*gap
            if a.last_hp<25 and s.hp<25 then a.low_hp_seconds=a.low_hp_seconds+gap end
            if a.last_battle==true and s.battle==true then a.combat_seconds=a.combat_seconds+gap end
            if a.last_lockon==true and s.lockon==true then a.lockon_seconds=a.lockon_seconds+gap end
        end
        if discontinuity then
            -- A load/pause in sampling or changed maximum must not masquerade as a hit.
            a.gaps=a.gaps+1
            a.clean_seconds=math.max(a.clean_seconds,a.last_time-a.clean_start)
            a.clean_start=s.time;a.last_drop=nil;a.last_recovery=nil
        elseif s.hp<a.last_hp-self.config.HPDropEpsilon then
            local window=self.config.HPDropGroupSeconds or 0.3
            local new_event=not a.last_drop or s.time-a.last_drop>window+1e-6
            if new_event then
                a.drops=a.drops+1
                a.clean_seconds=math.max(a.clean_seconds,a.last_time-a.clean_start)
            end
            -- Count every observed decrement, but merge animation-sized steps.
            a.hp_lost=a.hp_lost+(a.last_hp-s.hp)
            a.last_drop=s.time;a.clean_start=s.time;a.last_recovery=nil
        elseif s.hp>a.last_hp+self.config.HPDropEpsilon then
            if not a.last_recovery or s.time-a.last_recovery>(self.config.HPDropGroupSeconds or 0.3)+1e-6 then a.recovery_events=a.recovery_events+1 end
            a.hp_recovered=a.hp_recovered+s.hp-a.last_hp;a.last_recovery=s.time
            a.last_drop=nil -- recovery separates the next loss from this event
        end
        a.last_time=s.time;a.last_hp=s.hp;a.max_hp=s.max_hp
        a.health_source_last=source;a.raw_max_hp=s.raw_max_hp;a.last_battle=s.battle;a.last_lockon=s.lockon
        if s.hp==0 then self:finish("observed zero HP",s.time) end
    end
end
local function quote(value)
    return '"'..tostring(value or ""):gsub('"','""')..'"'
end
function Practice:note(name)
    if self.attempt and (name=="manual_marks" or name=="teleports" or name=="tool_action_requests") then
        self.attempt[name]=self.attempt[name]+1
    end
end
local function number(v) return finite(v) and string.format("%.3f",v) or "" end
local function defense(a,key) return math.max(0,(a.defense_end[key] or 0)-(a.defense_start[key] or 0)) end
function Practice:csv()
    local lines={"attempt,started_utc,world,seconds,observed_damage_events,observed_hp_lost_percentage_points,longest_observed_clean_seconds,sampling_gaps,end_reason,observed_hp_recovered_percentage_points,observed_recovery_events,start_hp_percent,end_hp_percent,min_hp_percent,max_hp_percent,net_hp_change_pp,average_observed_hp_percent,samples,observed_seconds,max_sample_gap_seconds,observed_seconds_below_25pct,observed_combat_seconds,observed_lockon_seconds,hp_loss_pp_per_minute,hp_recovery_pp_per_minute,health_source_start,health_source_end,raw_hp_start,raw_hp_end,raw_max_hp_end,boss_challenge,tools_start,tools_end,tool_action_requests,manual_marks,teleports,block_inputs,dodge_inputs,blue_inputs,violet_inputs,reversed_inputs,ambiguous_inputs,tools_seen"}
    for _,a in ipairs(self.history) do
        local seen={};for state in pairs(a.tools_seen) do seen[#seen+1]=state end;table.sort(seen)
        lines[#lines+1]=table.concat({a.id,quote(a.started_utc),quote(a.world),number(a.seconds),
            a.drops,number(a.hp_lost),number(a.clean_seconds),a.gaps,quote(a.reason),
            number(a.hp_recovered),a.recovery_events,number(a.hp_start),number(a.hp_end),number(a.hp_min),number(a.hp_max),
            number(a.net_hp_change),number(a.average_hp),a.samples,number(a.observed_seconds),number(a.max_sample_gap),
            number(a.low_hp_seconds),number(a.combat_seconds),number(a.lockon_seconds),number(a.loss_per_minute),number(a.healing_per_minute),
            quote(a.health_source),quote(a.health_source_last),number(a.raw_hp_start),number(a.raw_hp_end),number(a.raw_max_hp),
            a.boss_challenge==nil and "unknown" or tostring(a.boss_challenge),quote(a.tools_start),quote(a.tools_end),
            a.tool_action_requests,a.manual_marks,a.teleports,defense(a,"block"),defense(a,"dodge"),defense(a,"blue"),defense(a,"violet"),defense(a,"reversed"),defense(a,"ambiguous"),quote(table.concat(seen," | "))},",")
    end
    return table.concat(lines,"\n").."\n"
end
return Practice
