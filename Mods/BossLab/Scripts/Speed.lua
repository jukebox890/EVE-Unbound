-- Reversible sprint multiplier using the current movement component.
local Speed={};Speed.__index=Speed
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e6 end
local function near(a,b) return finite(a) and finite(b) and math.abs(a-b)<=math.max(0.00001,math.abs(b)*0.00001) end
local function same(a,b)
    return a and b and a.path==b.path and a.address==b.address and a.owner==b.owner and a.owner_address==b.owner_address
end
function Speed.new(api,config)
    return setmetatable({api=api,active=false,saved=nil,multiplier=1,timeout=(config and config.SprintTimeoutSeconds) or 0,last="Sprint OFF"},Speed)
end
function Speed:restore(reason)
    self.active=false;self.multiplier=1
    local s=self.saved
    if not s then return true end
    local ok,r=pcall(self.api.read,s)
    if not ok then self.last="Sprint restore failed; press Reset again.";return false end
    if same(r,s) and not finite(r.value) then self.last="Sprint restore read failed; press Reset.";return false end
    if not same(r,s) or not near(r.value,s.applied) then
        -- Do not touch a replaced object or fight a different writer.
        self.saved=nil
        self.last="Sprint OFF: object gone/replaced or value changed externally."
        return true
    end
    local success,accepted=pcall(self.api.write,s,s.value)
    if not success or not accepted then self.last="Sprint restore failed; press Reset again.";return false end
    self.saved=nil;self.last="Sprint restored: "..tostring(reason)
    return true
end
function Speed:enable(context,multiplier)
    multiplier=multiplier or 5
    assert(multiplier==5 or multiplier==2,"Unsupported sprint multiplier")
    if self.saved and not self:restore("retry") then return false end
    local ok,r,why=pcall(self.api.inspect,context)
    if not ok or not r then self.last="Sprint unavailable: "..tostring(ok and why or r);return false end
    if not finite(r.value) or r.value<=0 or r.value>10 then self.last="Sprint unavailable: invalid baseline scale.";return false end
    r.applied=r.value*multiplier;r.token=context.token;r.started=self.api.now()
    self.saved=r
    local written,accepted=pcall(self.api.write,r,r.applied)
    if not written or not accepted then
        self:restore("enable failed")
        self.last=self.saved and "Sprint write/restore failed; press Reset." or "Sprint write rejected; no active boost."
        return false
    end
    self.active=true;self.multiplier=multiplier
    self.last=string.format("Sprint %dx | %.3f -> %.3f; stops on combat or context change",multiplier,r.value,r.applied)
    return true
end
function Speed:tick(context)
    if not self.active then return end
    local s=self.saved;local now=self.api.now()
    if not context or context.token~=s.token then self:restore("player/world changed");return end
    if now<s.started or (self.timeout>0 and now-s.started>=self.timeout) then self:restore("timeout");return end
    local ok,r,why=pcall(self.api.inspect,context)
    if not ok or not r then self:restore(ok and (why or "guard failed") or "read error");return end
    if not same(r,s) then self:restore("movement component changed");return end
    if not near(r.value,s.applied) then self:restore("game or another mod changed sprint scale") end
end
function Speed:cycle(context)
    local next_multiplier=not self.active and 5 or (self.multiplier==5 and 2 or 1)
    if self.saved and not self:restore("cycle") then return false end
    if next_multiplier==1 then self.last="Sprint OFF";return true end
    return self:enable(context,next_multiplier)
end
function Speed:label() return self.active and (tostring(self.multiplier).."x") or "OFF" end
return Speed
