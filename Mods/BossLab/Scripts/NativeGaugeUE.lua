-- Bind through files once per player/world context; subsequent refills are in memory.
-- Native refill and safety checks remain on the persistent game-thread loop.
-- No native thread or timer. OFF never invokes this module's fill function.
local UE=require("UE")
local API={}
local directory,run,tick,sequence=nil,nil,nil,0
local bound_pawn,bound_pc,bound_world
local logger=function() end
local function load_bridge()
    if run and tick then return true end
    if not directory then return false,"NATIVE_NOT_CONFIGURED" end
    if not package or type(package.loadlib)~="function" then return false,"LUA_LOADLIB_UNAVAILABLE" end
    local fn,err=package.loadlib(directory.."BossLabGauge.dll","BossLabRun")
    if type(fn)~="function" then return false,"DLL_LOAD_FAILED: "..tostring(err) end
    local fast,fast_error=package.loadlib(directory.."BossLabGauge.dll","BossLabTick")
    if type(fast)~="function" then return false,"RESOURCE_DLL_UPDATE_REQUIRED: "..tostring(fast_error) end
    run=fn;tick=fast;return true
end
function API.configure(mod_directory,log_fn)
    local target=mod_directory.."Native/"
    if target~=directory then run=nil;tick=nil end
    bound_pawn,bound_pc,bound_world=nil,nil,nil
    directory=target;logger=log_fn or logger
    -- LoadLibrary/GetProcAddress only. DllMain stores its module handle and returns.
    -- BossLabRun is NOT invoked, so no player reads, writes or thread binding occur.
    local safe,ok,why=pcall(load_bridge)
    if not safe then why=ok;ok=false end
    if not ok then logger("RESOURCE DLL PRELOAD DEFERRED | "..tostring(why)) end
end
local function address(object)
    if not UE.valid(object) then return nil end
    local v=object:GetAddress()
    if type(v)~="number" or v<=0 or v%1~=0 then return nil end
    return v
end
local function invoke(context)
    if not directory then return false,"NATIVE_NOT_CONFIGURED" end
    if not context or UE.paused(context) then return false,"LIVE_UNPAUSED_EVE_REQUIRED" end
    local pawn,pc,world=address(context.pawn),address(context.pc),address(context.world)
    if not pawn or not pc or not world then return false,"INVALID_CONTEXT" end
    if not context.pawn:IsA("/Script/SB.SBCharacter") or not context.pc:IsA("/Script/SB.SBPlayerController") then
        return false,"UNSUPPORTED_PLAYER_CLASS"
    end
    local loaded,why=load_bridge()
    if not loaded then return false,why end
    if pawn==bound_pawn and pc==bound_pc and world==bound_world then
        -- Standard Lua C return convention: the callback selects its result from
        -- these existing stack arguments. No private Lua layout or registry access.
        local result=tick("BUSY","NOT_BOUND","NATIVE_REFILL_FAILED",
            "BAD_REQUEST","WRONG_THREAD","NATIVE_EXCEPTION","UNSUPPORTED_EXECUTABLE",
            "CONTEXT_MISMATCH","PLAYER_UNAVAILABLE","ACTOR_IDENTITY_MISMATCH",
            "INVALID_STATS","PLAYER_NOT_ALIVE","SETTER_EXCEPTION","READBACK_MISMATCH",
            "UNREADABLE_POINTER",true)
        if result~=true then
            bound_pawn,bound_pc,bound_world=nil,nil,nil
            return false,type(result)=="string" and result or "NATIVE_BRIDGE_NO_RESULT"
        end
        return true,"REFILLED"
    end
    -- Context changed: do not reuse an old binding if this handshake fails.
    bound_pawn,bound_pc,bound_world=nil,nil,nil
    sequence=sequence+1
    local file,err=io.open(directory.."request.txt","wb")
    if not file then return false,"REQUEST_WRITE_FAILED: "..tostring(err) end
    local written,write_error=file:write(string.format("1 %d 1 %x %x %x\n",sequence,pawn,pc,world))
    local closed,close_error=file:close()
    if not written or not closed then return false,"REQUEST_WRITE_FAILED: "..tostring(write_error or close_error) end
    -- Remove old output so a failed native invocation cannot reuse a matching
    -- sequence from a previous Lua session.
    local removed= os.remove(directory.."response.txt")
    if not removed then
        local old=io.open(directory.."response.txt","rb")
        if old then old:close();return false,"NATIVE_RESPONSE_CLEAR_FAILED" end
    end
    run()
    local response=io.open(directory.."response.txt","rb")
    if not response then return false,"NATIVE_RESPONSE_MISSING" end
    local text=response:read(1024) or "";response:close()
    local seq,status,detail=text:match("^(%d+) (%u+) ([^\r\n]+)")
    if tonumber(seq)~=sequence then return false,"STALE_NATIVE_RESPONSE" end
    if status~="OK" then return false,detail or "MALFORMED_NATIVE_RESPONSE" end
    bound_pawn,bound_pc,bound_world=pawn,pc,world
    return true,detail
end
function API.fill(context)
    local ok,result,detail=pcall(invoke,context)
    if not ok then
        bound_pawn,bound_pc,bound_world=nil,nil,nil
        return false,"NATIVE_BRIDGE_ERROR: "..tostring(result)
    end
    return result,detail
end
return API
