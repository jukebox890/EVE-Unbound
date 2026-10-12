-- One persistent engine-thread loop; input callbacks only put literal action
-- names into a bounded mailbox. No recurring cross-thread registry ref/unref.
local error_message=require("ProtectionError")
local Dispatch={};Dispatch.__index=Dispatch
function Dispatch.new(action,poll,log,loop)
    return setmetatable({action=action,poll=poll,log=log,loop=loop,
        slots={false,false},head=1,tail=1,count=0,dropped=0,
        running=false,started=false},Dispatch)
end
function Dispatch:enqueue(kind)
    -- Called on the input thread: no engine APIs, logging, function creation,
    -- scheduling, or native registry manipulation here.
    if self.count>=2 then self.dropped=self.dropped+1;return false end
    self.slots[self.tail]=kind
    self.tail=self.tail==2 and 1 or 2
    self.count=self.count+1
    return true
end
function Dispatch:pump()
    if self.running then return false end
    self.running=true
    local ok,why=xpcall(function()
        local dropped=self.dropped;self.dropped=0
        if dropped>0 then self.log("BUSY | ignored "..dropped.." queued key presses") end
        local acted=self.count>0
        if acted then
            local kind=self.slots[self.head]
            self.slots[self.head]=false
            self.head=self.head==2 and 1 or 2
            self.count=self.count-1
            local safe,err=xpcall(function() self.action(kind) end,error_message)
            if not safe then self.log("ACTION ERROR "..kind.." | "..err) end
        end
        -- Cadence accounting still advances on action ticks; optional maintenance
        -- waits until the next idle tick instead of sharing a bulk toggle's frame.
        self.poll(acted)
    end,error_message)
    if not ok then
        -- Keep the busy guard through reporting, including a re-entrant logger.
        pcall(self.log,"DISPATCH ERROR | "..why)
    end
    self.running=false
    return false -- UE4SS looping action: false keeps this registered callback alive
end
function Dispatch:start(milliseconds)
    if self.started then return false,"dispatcher already started" end
    if type(self.loop)~="function" then
        return false,"LoopInGameThreadWithDelay unavailable in this UE4SS build"
    end
    local ok,handle=pcall(self.loop,milliseconds,function() return self:pump() end)
    if not ok then return false,error_message(handle) end
    self.started=true;self.handle=handle
    return true
end
return Dispatch
