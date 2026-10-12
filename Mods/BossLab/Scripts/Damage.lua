-- Timer/controller independent of a game-specific verified damage writer.
-- Toggle mode keeps the user's request through fight-transition table rewrites:
-- request survives pawn/world replacement and is reapplied to the next valid
-- player context. Timed 2/3/5 second boosts remain one-shot.
local Damage={};Damage.__index=Damage
local durations={2,3,5,0} -- 0 = persistent toggle, never math.huge written into game stats
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
local function now_wall() return os.clock and os.clock() or os.time() end
function Damage.new(api,clock)
    return setmetatable({api=api,clock=clock,index=3,active=false,armed=false,lease=nil,remaining=nil,
        last="Damage boost OFF: 1000x Eve attack-step rates.",notice_until=0,retry_after=0},Damage)
end
function Damage:duration_label() return durations[self.index]==0 and "Toggle" or (durations[self.index].." seconds") end
function Damage:cycle()
    if self.lease or self.active or self.armed then self.last="Cancel the boost before changing duration.";return false end
    self.index=self.index%#durations+1
    self.last="Damage duration: "..self:duration_label().."."
    return true
end
function Damage:cancel(reason,disarm)
    if disarm==nil then disarm=true end
    self.active=false;self.remaining=nil;self.notice_until=0
    if disarm then self.armed=false end
    if not self.lease then
        self.last=(self.armed and "Infinite damage ARMED; waiting for a valid player context." or ("Damage boost OFF: "..tostring(reason or "cancelled")))
        return true
    end
    local ok,restored=xpcall(function() return self.api.restore(self.lease) end,debug.traceback)
    if not ok or restored~=true then
        self.last="DAMAGE RESTORE INCOMPLETE - press Num 0; send log."
        return false
    end
    self.lease=nil;self.token=nil
    self.last=self.armed and "Infinite damage ARMED; waiting for the next valid player context."
        or ("Damage boost OFF: "..tostring(reason or "cancelled"))
    return true
end
function Damage:_apply(context)
    if self.ready and not self.ready(context) then
        self.last=self.armed and "Infinite damage ARMED; waiting for stable gameplay."
            or "Damage boost unavailable: wait for stable gameplay."
        return false
    end
    local checked,ready,why=xpcall(function() return self.api.available(context) end,debug.traceback)
    if not checked or ready~=true then
        self.last="Damage boost unavailable: "..tostring(checked and why or ready)
        self.notice_until=os.time()+4
        return false
    end
    local ok,now=xpcall(function() return self.clock(context) end,debug.traceback)
    if not ok or not finite(now) or not context then self.last="Damage boost unavailable: game clock/player missing.";self.notice_until=os.time()+4;return false end
    local prepared,lease=xpcall(function() return self.api.prepare(context) end,debug.traceback)
    if not prepared or not lease then self.last="Damage snapshot unavailable: "..tostring(lease);self.notice_until=os.time()+4;return false end
    self.lease=lease;self.token=context.token
    local applied,result=xpcall(function() return self.api.apply(lease) end,debug.traceback)
    if not applied or result~=true then
        local restored=self:cancel("apply failed",not self.armed)
        if restored then self.last=self.armed and "Infinite damage ARMED; apply failed, will retry on a valid context."
            or "Damage boost failed to apply; originals restored." end
        return false
    end
    local verified,confirmed=xpcall(function() return self.api.verify(lease,context) end,debug.traceback)
    if not verified or confirmed~=true then self:cancel("initial verification failed",not self.armed);return false end
    self.active=true;self.started=now;self.last_time=now;self.started_wall=os.time()
    self.duration=durations[self.index];self.remaining=self.duration~=0 and self.duration or nil
    self.last=self.armed and "Infinite damage ON (persistent toggle)" or "Infinite damage ON"
    self.notice_until=0;self.retry_after=0
    return true
end

function Damage:rebind(context,reason)
    if not self.armed then return false end
    self.active=false;self.remaining=nil;self.notice_until=0
    if self.lease then
        local ok,restored=xpcall(function() return self.api.restore(self.lease) end,debug.traceback)
        if not ok or restored~=true then
            self.last="DAMAGE REBIND RESTORE INCOMPLETE - press Num 0; send log."
            return false
        end
    end
    self.lease=nil;self.token=nil;self.retry_after=0
    if not context then
        self.last="Infinite damage ARMED; waiting for the next valid player context."
        return true
    end
    local ok=self:_apply(context)
    if not ok then self.retry_after=now_wall()+0.5 end
    if ok and reason then self.last="Infinite damage ON (persistent toggle; rebound: "..tostring(reason)..")" end
    return ok
end

function Damage:trigger(context)
    -- Any explicit hotkey press while requested/active means OFF.
    if self.active or self.lease or self.armed then return self:cancel("hotkey",true) end
    self.duration=durations[self.index]
    self.armed=self.duration==0
    local ok=self:_apply(context)
    if not ok and self.armed then self.retry_after=now_wall()+0.5 end
    return ok
end
function Damage:tick(context)
    if context and self.ready and not self.ready(context) then return end
    -- Persistent Toggle may be between contexts. Retry only at a bounded rate.
    if self.armed and not self.active and not self.lease then
        local wall=now_wall()
        if wall>=self.retry_after and context then
            self.retry_after=wall+0.5
            self:_apply(context)
        end
        return
    end
    if not self.active then return end
    if not context or context.token~=self.token then
        if self.armed then
            if not self:rebind(context,"player/world changed") then self.retry_after=now_wall()+0.5 end
        else
            self:cancel("player/world changed",true)
        end
        return
    end
    local ok,now=xpcall(function() return self.clock(context) end,debug.traceback)
    if not ok or not finite(now) or now<self.last_time then self:cancel("clock unavailable/reset",not self.armed);return end
    self.last_time=now
    local checked,still_applied=xpcall(function() return self.api.verify(self.lease,context) end,debug.traceback)
    if not checked or still_applied~=true then
        if self.armed then
            if not self:rebind(context,"verification/table refresh") then self.retry_after=now_wall()+0.5 end
        else
            self:cancel("damage verification lost",true)
        end
        return
    end
    if self.duration~=0 then
        self.remaining=math.max(0,self.duration-(now-self.started))
        if self.remaining<=0 or os.time()<self.started_wall or os.time()-self.started_wall>=self.duration+10 then
            self:cancel("expired",true)
        end
    end
end
function Damage:banner()
    if self.lease and not self.active then return "DAMAGE RESTORE INCOMPLETE - Num 0" end
    if self.active then
        return self.remaining and string.format("Infinite damage ON - %.2fs",self.remaining)
            or "Infinite damage ON - persistent toggle"
    end
    if self.armed then return "Infinite damage ARMED - waiting for player context" end
    if os.time()<self.notice_until then return "Damage boost unavailable - capture Num 9" end
end
function Damage:busy() return self.active or self.armed or self.lease~=nil or os.time()<self.notice_until end
return Damage
