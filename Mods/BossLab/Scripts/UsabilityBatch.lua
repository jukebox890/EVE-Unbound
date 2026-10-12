-- EVE Unbound V1.0: gameplay tools, menu and combat recording.
local Batch={}

function Batch.start(config,directory)
    local UE=require("UE")
    local position_api=require("PositionUE35").new()
    local practice_api=require("PracticeUE").new(config)
    local practice=require("Practice").new(practice_api,config)
    local speed=require("Speed").new(require("SpeedUE"),config)
    local damage=require("Damage").new(require("DamageUE"),practice_api.time)
    damage.index=2 -- 3 seconds by default
    local protection_api=require("DamageZeroUE")
    local boss_invuln=require("Invulnerability").new(protection_api,"boss","BOSS INVULN")
    local player_invuln=require("Invulnerability").new(protection_api,"player","PLAYER INVULN",{battle_only=false})
    local death=require("DeathUE")
    local ResourceInfinite=require("ResourceInfinite")
    local Core=require("Core")
    local core=Core.new({list=UE.list_keys,read=UE.read_key,write=UE.write_key,patch=UE.patch_key,log=UE.log},config)
    local status_hud=require("StatusHUD").new(config)
    local move_hud=require("MoveHistoryHUD").new(config)

    local attempts_path=directory.."BossLab-attempts.csv"

    local visible=false
    local bookmark=nil
    local dispatch
    local auto_record=true
    local monitor_token=nil
    local stable_observations=0
    local gameplay_observations=0
    local stability_battle=nil
    local previous_battle=nil
    local pending_battle_end_checks=0
    local pending_battle_end_time=nil
    local pending_auto_mark=false
    local gameplay_ready=false
    local history_suspended=false

    local elapsed={monitor=0,practice=0,speed=0,damage=0,dodge=0,protection=0,death=0,resource=0,menu=0,status=0,history=0,history_input=0}

    -- Operational errors use the loader log.
    local function log(message)
        print("[EVE Unbound V1.0] "..tostring(message).."\n")
    end

    require("NativeGaugeUE").configure(directory,log)
    local panel_view=require("PanelView").new(config,directory,log)
    local resources=ResourceInfinite.new(config,log)
    resources.last="PRACTICE RESOURCES OFF • toggle with Alt+Num5"
    death.configure(config,function(message) log("NO DAMAGE RUN | "..tostring(message)) end)

    local move_api=require("MoveHistoryUE").new(config,move_hud)
    local move_history=require("MoveHistory").new(move_api,config,function(message)
        log("DEFENSE FEED | "..tostring(message))
    end)

    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
    local function point(p) return p and finite(p.X) and finite(p.Y) and finite(p.Z) end
    local function distance(a,b)
        if not point(a) or not point(b) then return nil end
        return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)
    end

    local function context_now()
        local ok,c=pcall(UE.context)
        return ok and c or nil
    end

    local function hud_now(context)
        if not context then return nil end
        local ok,h=pcall(UE.hud,context)
        return ok and h or nil
    end

    local function battle_state(context,include_hud)
        if not context or not UE.valid(context.pawn) then return {challenge=nil,battle=nil,lockon=nil,hud=nil} end
        -- bBattleState/bLockOn are pawn-local and cheap. The Boss Challenge HUD flag is
        -- informational only, so the normal 500 ms monitor must never force a global
        -- HUD search merely to read it.
        local hud=include_hud and hud_now(context) or UE.hud_cached(context)
        local challenge=nil
        if UE.valid(hud) then
            local dead=UE.read(hud,"WB_MainHUD_Dead")
            challenge=UE.read(dead,"bBossChallengeMode")
        end
        return {
            hud=hud,
            challenge=challenge,
            battle=UE.read(context.pawn,"bBattleState"),
            lockon=UE.read(context.pawn,"bLockOn"),
        }
    end

    local function gameplay_gate(context,state)
        if not context then return false,false,false end
        local paused=UE.paused(context)
        local hud_visible=UE.hud_visible(context)
        return hud_visible and not paused,hud_visible,paused
    end

    -- Only monitor observations advance this gate. Hotkeys/maintenance can close
    -- it immediately but cannot make a returning HUD count as stable by polling it.
    -- bBattleState transitions also close it even when the HUD never disappears.
    local function toggle_ready(context)
        if not context or context.token~=monitor_token then
            gameplay_observations=0;return false
        end
        if stable_observations<2 then return false end
        local battle=UE.read(context.pawn,"bBattleState")
        if battle==nil or battle~=stability_battle or not gameplay_gate(context) then
            gameplay_observations=0;return false
        end
        return gameplay_observations>=2
    end
    player_invuln.ready=toggle_ready
    boss_invuln.ready=toggle_ready
    damage.ready=toggle_ready
    resources.ready=toggle_ready
    player_invuln.log=log
    boss_invuln.log=log

    local function remove_panel()
        panel_view:remove()
        move_hud:set_suppressed(false,context_now())
        visible=false
    end

    local function active_tool_names()
        local out={}
        if damage.active then out[#out+1]="Damage x1000" elseif damage.armed then out[#out+1]="Damage pending" end
        if player_invuln.active then out[#out+1]="Player invuln" elseif player_invuln.armed then out[#out+1]="Player invuln pending" end
        if boss_invuln.active then out[#out+1]="Enemy invuln" elseif boss_invuln.armed then out[#out+1]="Enemy invuln pending" end
        if death.pending() then out[#out+1]="No-hit run" end
        if resources.all then out[#out+1]="Resources" end
        if core.active then out[#out+1]="Dodge "..core:mode_label() end
        if speed.active then out[#out+1]="Sprint "..speed:label() end
        if move_history.enabled then out[#out+1]="Defense feed" end
        return out
    end
    local function wrapped_active()
        local lines,line={},""
        for _,name in ipairs(active_tool_names()) do
            if #line+#name>68 then lines[#lines+1]=line;line="" end
            line=line=="" and name or line.."  /  "..name
        end
        if line~="" then lines[#lines+1]=line end
        return #lines>0 and table.concat(lines,"\n") or "No practice modifiers active"
    end
    local function panel_data()
        local function state(active,armed) return active and "ON" or (armed and "WAITING" or "OFF") end
        local a=practice.attempt
        return {
            active=wrapped_active(),
            damage={text=state(damage.active,damage.armed)..(damage.remaining and string.format(" · %.1fs",damage.remaining) or ""),on=damage.active or damage.armed},
            damage_duration={text=damage:duration_label():gsub(" seconds"," s"),on=true},
            player_invuln={text=state(player_invuln.active,player_invuln.armed),on=player_invuln.active or player_invuln.armed},
            boss_invuln={text=state(boss_invuln.active,boss_invuln.armed),on=boss_invuln.active or boss_invuln.armed},
            nohit={text=death.banner() and (death.banner():find("ARMED",1,true) and "ARMED" or "ON · next hit") or "OFF",on=death.pending()},
            resources={text=state(resources.active,resources.all),on=resources.all},
            dodge={text=core:mode_label(),on=core.active},speed={text=speed:label(),on=speed.active},
            position_save={text=bookmark and "Saved" or "No mark",on=bookmark~=nil},
            position_return={text=bookmark and "Ready" or "Save first",on=bookmark~=nil},
            feed={text=move_history.enabled and (move_history.sampling and "LIVE" or "READY") or "OFF",on=move_history.enabled},
            record={text=auto_record and "ON" or "OFF",on=auto_record},
            export={text=tostring(#practice.history).." completed",on=#practice.history>0},
            footer="Num 0  Reset tools     /     Alt+B  Close".."\n"..(a and string.format("Fight #%d · %.1f s · HP lost %.1f pp · healed %.1f pp",a.id,a.last_time-a.started,a.hp_lost,a.hp_recovered or 0) or "Use the shortcuts to change options."),
        }
    end
    local function open_panel()
        local context=context_now();local hud=hud_now(context)
        if not context or not UE.valid(hud) then log("MENU REFUSED | wait for gameplay HUD/player control");return false end
        remove_panel()
        local ok,why=xpcall(function() return panel_view:open(context,hud,panel_data()) end,debug.traceback)
        if not ok or why~=true then panel_view:remove();log("MENU ERROR | "..tostring(why));return false end
        visible=true;move_hud:set_suppressed(true,context);pcall(function() status_hud:remove() end);return true
    end
    local function refresh_panel(context,state,force)
        if not visible then return end
        local hud=hud_now(context)
        if not panel_view:valid(context,hud) then remove_panel();return end
        panel_view:update(panel_data())
    end

    -- Extra export metadata is sampled with the existing 200 ms recorder, using
    -- already-held tool state and cumulative input counters. No extra engine scan.
    local base_sample=practice_api.sample
    practice_api.sample=function(context)
        local sample,why=base_sample(context)
        if sample then
            sample.tools=table.concat(active_tool_names(),";")
            sample.defense={};for key,value in pairs(move_history.counters) do sample.defense[key]=value end
        end
        return sample,why
    end

    local function status_message(state)
        if visible then return nil end
        local parts={}
        if damage.active then
            if damage.remaining then parts[#parts+1]=string.format("1000x DAMAGE  •  %.1fs",damage.remaining)
            else parts[#parts+1]="1000x DAMAGE  •  ON (toggle)" end
        elseif damage.armed then parts[#parts+1]="1000x DAMAGE  •  ARMED" end
        if speed.active and state and state.battle==false then parts[#parts+1]="SPRINT "..speed:label().."  •  ON" end
        if boss_invuln.active then parts[#parts+1]="BOSS INVULN  •  ON"
        elseif boss_invuln.armed then parts[#parts+1]="BOSS INVULN  •  ARMED" end
        if player_invuln.active then parts[#parts+1]="PLAYER INVULN  •  ON"
        elseif player_invuln.armed then parts[#parts+1]="PLAYER INVULN  •  WAITING" end
        if core.active then parts[#parts+1]="DODGE SLOW-MO  •  "..core:mode_label() end
        if move_history.enabled then parts[#parts+1]="DEFENSE FEED  •  "..(move_history.sampling and "LIVE" or "READY") end
        local rb=resources:banner();if rb then parts[#parts+1]=rb end
        local db=death.banner and death.banner() or nil;if db then parts[#parts+1]=db end
        if #parts==0 then return nil end
        local lines={"EVE UNBOUND"}
        for _,part in ipairs(parts) do lines[#lines+1]=part end
        return table.concat(lines,"\n")
    end

    local function refresh_status(context,state)
        local message=status_message(state)
        local ok,why=pcall(function() return status_hud:update(context,message) end)
        if not ok then log("STATUS HUD ERROR | "..tostring(why));pcall(function() status_hud:remove() end) end
    end

    local function store_bookmark(context,state,reason)
        local p,why=position_api.position(context)
        if not point(p) then log("MARK REFUSED | "..tostring(why));return false end
        local r=position_api.rotation(context)
        bookmark={token=context.token,pawn_address=context.pawn:GetAddress(),position={X=p.X,Y=p.Y,Z=p.Z},rotation=r,
            pre_fight=not (state and state.battle==true)}
        return true
    end

    local function mark_position(context,state)
        local ok=store_bookmark(context,state,"MARK STORED")
        if ok and state and state.battle==true then pending_auto_mark=false end
        return ok
    end

    local function rebase_prefight_mark(context,state,reason)
        if not bookmark or not bookmark.pre_fight then return false end
        if bookmark.token~=context.token or bookmark.pawn_address~=context.pawn:GetAddress() then return false end
        return store_bookmark(context,state,reason or "MARK REBASED")
    end

    local function return_position(context,state)
        if not bookmark then log("RETURN REFUSED | no stored mark");return false end
        if bookmark.token~=context.token or bookmark.pawn_address~=context.pawn:GetAddress() then
            bookmark=nil;log("RETURN REFUSED | mark expired due to pawn/world transition");return false
        end
        local current,why=position_api.position(context)
        if not point(current) then log("RETURN REFUSED | "..tostring(why));return false end
        local d=distance(current,bookmark.position)
        -- A mark made before battle can become dangerous during the short arena
        -- entry window before bBattleState flips true. Only that pre-fight mark
        -- gets a safety range; real fight marks remain unlimited.
        if bookmark.pre_fight and not (state and state.battle==true) and d and d>(config.PreFightReturnLimit or 1500) then
            log("RETURN PREFIGHT SAFETY | distance_uu="..string.format("%.1f",d).." limit="..tostring(config.PreFightReturnLimit or 1500).."; rebasing mark to current arena-side position")
            store_bookmark(context,state,"MARK REBASED | pre-fight safety")
            return false
        end
        local ok,result=position_api.move(context,bookmark.position)
        if ok==true then practice:note("teleports")
        else log("RETURN REFUSED | "..tostring(result)) end
        return ok==true
    end

    local function export_attempts()
        local file,why=io.open(attempts_path,"w")
        if not file then log("EXPORT FAILED | "..tostring(why));return false end
        local written,write_error=file:write(practice:csv())
        local closed=file:close()
        local ok=written and closed
        log((ok and "EXPORT PASS | " or "EXPORT FAILED | ")..(ok and ("Exported "..#practice.history.." attempt(s)") or tostring(write_error)))
        return ok
    end

    local function restore_tools(reason)
        local damage_ok=damage:cancel(reason or "manual tools restore")
        local speed_ok=speed:restore(reason or "manual tools restore")
        local dodge_ok=core:restore(reason or "manual tools restore")
        local boss_ok=boss_invuln:cancel(reason or "manual tools restore")
        local player_ok=player_invuln:cancel(reason or "manual tools restore",true)
        local resource_context=context_now()
        local resource_ok,resource_msg=resources:set_all(false,resource_context)
        if not resource_ok then log("RESOURCE RESTORE ERROR | "..tostring(resource_msg)) end
        death.cancel(reason or "manual tools restore")
        practice:reset(reason or "manual tools restore")
        move_history:clear(reason or "manual tools restore")
        bookmark=nil;pending_auto_mark=false
        pending_battle_end_checks=0;pending_battle_end_time=nil
        pcall(function() status_hud:remove() end)
        if not (damage_ok and speed_ok and dodge_ok and boss_ok and player_ok) then
            log("TOOLS RESTORE INCOMPLETE | check the loader log before using modifiers again")
        end
    end

    local function start_auto_attempt(context,reason)
        if not auto_record or practice.attempt or not context then return false end
        local ok=practice:start(context)
        if not ok then log("AUTO ATTEMPT START REFUSED | "..tostring(practice.last)) end
        return ok
    end

    local function finish_attempt(reason,context,captured_time)
        if not practice.attempt then return end
        local now=captured_time
        if now==nil and context then local ok,v=pcall(practice_api.time,context);if ok then now=v end end
        practice:finish(reason,now)
    end

    local function begin_fight(context,state,reason)
        if speed.active then speed:restore("boss fight started");log("SPEED | active=false | "..tostring(speed.last)) end
        -- Existing leases remain owned by the regular controller ticks. A combat
        -- flag change alone never restores/reapplies an otherwise valid table.
        if bookmark and bookmark.pre_fight then bookmark=nil;log("MARK CLEARED | pre-fight mark discarded at fight start") end
        pending_auto_mark=not store_bookmark(context,state,"AUTO MARK | boss fight start")
        if pending_auto_mark then log("AUTO MARK PENDING | will retry while battle is active") end
    end

    local function update_gameplay_gate(context,state)
        local ready=gameplay_gate(context,state)
        local battle=state and state.battle
        if not ready or battle==nil or battle~=stability_battle then gameplay_observations=0 end
        stability_battle=battle
        if ready and battle~=nil then gameplay_observations=math.min(2,gameplay_observations+1) end
        gameplay_ready=ready
        if move_history.sampling then
            if not ready and not history_suspended then
                history_suspended=true
            elseif ready and history_suspended then
                history_suspended=false
                local ok,why=xpcall(function() return move_history:resync("gameplay resumed") end,debug.traceback)
                if not ok then log("MOVE HISTORY RESYNC ERROR | "..tostring(why)) end
            end
        else
            history_suspended=not ready
        end
        return ready
    end

    local function monitor(context,state)
        if not context then
            finish_attempt("player unavailable",nil)
            if boss_invuln.armed then boss_invuln:rebind(nil,"player unavailable",false)
            elseif boss_invuln:busy() then boss_invuln:cancel("player unavailable",true) end
            if player_invuln.armed then player_invuln:rebind(nil,"player unavailable",false)
            elseif player_invuln:busy() then player_invuln:cancel("player unavailable",true) end
            if damage.armed then damage:rebind(nil,"player unavailable")
            elseif damage:busy() then damage:tick(nil) end
            move_history:stop("player unavailable")
            stable_observations=0;gameplay_observations=0;stability_battle=nil
            if UE.clear_dodge_cache then UE.clear_dodge_cache() end
            monitor_token=nil;previous_battle=nil;pending_auto_mark=false
            pending_battle_end_checks=0;pending_battle_end_time=nil
            gameplay_ready=false;history_suspended=true
            return
        end
        state=state or battle_state(context,false)
        local in_battle=state.battle==true
        local token_changed=monitor_token~=context.token
        if token_changed then
            stable_observations=1;gameplay_observations=0;stability_battle=nil
            if UE.clear_dodge_cache then UE.clear_dodge_cache() end
            finish_attempt("player/world changed",nil)
            if bookmark and bookmark.token~=context.token then bookmark=nil;pending_auto_mark=false;log("MARK EXPIRED | pawn/world transition") end
            if speed.active then speed:tick(context) end
            -- Do not synchronously restore/reapply DataTable modes on a transition frame.
            -- Their armed states are preserved; regular ticks handle a necessary
            -- context rebind once normal gameplay is stable again.
            move_history:stop("player/world changed")
            monitor_token=context.token;previous_battle=in_battle
            pending_battle_end_checks=0;pending_battle_end_time=nil
            if in_battle then begin_fight(context,state,"entered active battle on new context") end
            update_gameplay_gate(context,state)
            return
        end

        stable_observations=math.min(2,stable_observations+1)
        if in_battle then
            local resumed_transient=pending_battle_end_checks>0
            if resumed_transient then
                pending_battle_end_checks=0;pending_battle_end_time=nil
            end
            if previous_battle~=true and not resumed_transient then begin_fight(context,state,"battle false->true") end
            local ready=update_gameplay_gate(context,state)
            if pending_auto_mark and (not bookmark or bookmark.pre_fight) then
                local ok=store_bookmark(context,state,"AUTO MARK RETRY | boss fight start")
                if ok then pending_auto_mark=false end
            end
            if ready then
                if move_history.enabled and not move_history.sampling then
                    local okcall,result=xpcall(function() return move_history:start(context) end,debug.traceback)
                    local ok=okcall and result==true
                    history_suspended=not ok
                end
                if auto_record and not practice.attempt then
                    local okcall,why=xpcall(function() return start_auto_attempt(context,"gameplay ready") end,debug.traceback)
                    if not okcall then log("AUTO ATTEMPT START ERROR | "..tostring(why)) end
                end
            end
        else
            update_gameplay_gate(context,state)
            -- Outside-combat protection is maintained by the normal gated poll.
            -- Do not restore/reapply the table merely because bBattleState is false.
            if practice.attempt and previous_battle==true then
                pending_battle_end_checks=1
                local ok,v=pcall(practice_api.time,context);pending_battle_end_time=ok and v or nil
            elseif practice.attempt and pending_battle_end_checks>0 then
                pending_battle_end_checks=pending_battle_end_checks+1
                if pending_battle_end_checks>=(config.BattleEndDebouncePolls or 2) then
                    finish_attempt("battle ended",context,pending_battle_end_time)
                    move_history:stop("boss fight ended")
                    history_suspended=true
                    pending_battle_end_checks=0;pending_battle_end_time=nil
                end
            end
        end
        previous_battle=in_battle
    end

    local function do_action(kind)
        if kind=="menu" then
            if visible then
                remove_panel()
                local c=context_now();local st=c and battle_state(c) or nil
                refresh_status(c,st)
            else
                pcall(function() status_hud:remove() end)
                open_panel()
            end
            return
        end
        if kind=="damage_duration" then
            if not damage:cycle() then log("DAMAGE DURATION | "..damage.last) end
            return
        end
        if kind=="export" then export_attempts();return end
        if kind=="restore" then restore_tools("Num 0");return end

        local context=context_now()
        if not context then log(string.upper(kind).." REFUSED | no controlled player");return end
        local state=battle_state(context)

        if kind=="mark" then mark_position(context,state);practice:note("manual_marks")
        elseif kind=="return" then return_position(context,state)
        elseif kind=="record" then
            auto_record=not auto_record
            if not auto_record then finish_attempt("auto recording disabled",context)
            elseif state.battle==true then start_auto_attempt(context,"auto recording enabled mid-fight") end
        elseif kind=="inputs" then
            move_history:toggle(context,state.battle==true and gameplay_ready)
        elseif kind=="speed" then
            if not speed:cycle(context) then log("SPRINT | "..tostring(speed.last)) end
        elseif kind=="damage" then
            if boss_invuln:busy() and not boss_invuln:cancel("1000x damage enabled") then
                log("DAMAGE REFUSED | boss-invulnerability restore incomplete")
            elseif not damage:trigger(context) then log("DAMAGE | "..tostring(damage.last)) end
        elseif kind=="boss_invuln" then
            local ready=true
            if not boss_invuln.armed and damage:busy() then ready=damage:cancel("boss invulnerability enabled",true) end
            if ready then
                if not boss_invuln:trigger(context) then log("BOSS INVULN | "..tostring(boss_invuln.last)) end
            else log("BOSS INVULN REFUSED | 1000x-damage restore incomplete") end
        elseif kind=="player_invuln" then
            if not player_invuln.armed and death.pending() then
                log("PLAYER INVULN REFUSED | turn No Damage Run OFF with Num7 first")
                return
            end
            if not player_invuln:trigger(context,state.battle) then log("PLAYER INVULN | "..tostring(player_invuln.last)) end
        elseif kind=="kill" then
            if not death.pending() and player_invuln:busy() then log("NO DAMAGE RUN REFUSED | turn Player Invulnerability OFF with Num . first");return end
            local ok,msg=death.toggle(context,state.battle)
            if not ok then log("NO-HIT RUN | "..tostring(msg)) end
        elseif kind=="resource_all" then
            local requested=not resources.all
            local ok,msg=resources:set_all(requested,context)
            if not ok then log("RESOURCES | "..tostring(msg)) end
        elseif kind=="dodge" then
            if not toggle_ready(context) then log("DODGE REFUSED | wait for stable live gameplay");return end
            local safe,ok=xpcall(function() return core:cycle() end,debug.traceback)
            if not safe then error(ok) end
            if not ok then log("DODGE SLOW-MO | "..tostring(core.last)) end
        else log("UNKNOWN ACTION | "..tostring(kind)) end

        if kind=="speed" or kind=="damage" or kind=="boss_invuln" or kind=="player_invuln" or kind=="kill" or kind=="resource_all" or kind=="dodge" then practice:note("tool_action_requests") end
        local latest=context_now()
        local latest_state=latest and battle_state(latest) or state
        if visible then refresh_panel(latest,latest_state,true) end
        refresh_status(latest,latest_state)
    end

    local function queue(kind)
        return dispatch:enqueue(kind)
    end

    local poll
    dispatch=require("GameThreadDispatch").new(function(kind)
        do_action(kind)
    end,function(acted) return poll(acted) end,log,LoopInGameThreadWithDelay)

    local keys={}
    local function bind(code,kind,modifiers)
        assert(type(code)=="number" and code>=1 and code<=255 and code%1==0,"Invalid key code for "..kind)
        local names={}
        for _,name in ipairs(modifiers or {}) do names[#names+1]=tostring(name) end
        table.sort(names)
        local signature=tostring(code)..":"..table.concat(names,"+")
        assert(not keys[signature],"Duplicate BossLab key signature: "..signature);keys[signature]=true
        local callback=function() queue(kind) end
        if modifiers and #modifiers>0 then
            local resolved={}
            for _,name in ipairs(modifiers) do assert(ModifierKey and ModifierKey[name],"Unknown modifier "..tostring(name));resolved[#resolved+1]=ModifierKey[name] end
            RegisterKeyBind(code,resolved,callback)
        else RegisterKeyBind(code,callback) end
    end

    bind(config.MenuKey,"menu",config.MenuModifiers);if config.MenuBackupKey then bind(config.MenuBackupKey,"menu") end
    bind(config.ToggleKey,"dodge")
    bind(config.RecordKey,"record")
    bind(config.MarkKey,"mark")
    bind(config.ReturnKey,"return")
    bind(config.InputKey,"inputs")
    bind(config.ExportKey,"export")
    bind(config.SpeedKey,"speed")
    bind(config.DamageDurationKey,"damage_duration")
    bind(config.DamageKey,"damage")
    bind(config.ResetKey,"restore")
    bind(config.BossInvulnKey,"boss_invuln")
    bind(config.PlayerInvulnKey,"player_invuln")
    bind(config.ResourceAllKey,"resource_all",config.ResourceAllModifiers)
    if config.KillKey then bind(config.KillKey,"kill",config.KillModifiers) end

    local base=config.LoopMs
    poll=function(acted)
        for k,v in pairs(elapsed) do elapsed[k]=v+base end
        if acted then return false end
        local due_monitor=elapsed.monitor>=config.MonitorMs
        local due_practice=(practice.attempt~=nil) and elapsed.practice>=config.PracticePollMs
        local due_speed=speed.active and elapsed.speed>=config.SpeedPollMs
        local due_damage=damage:busy() and elapsed.damage>=config.DamagePollMs
        local due_dodge=core.active and elapsed.dodge>=config.DodgeScanMs
        local due_protection=(boss_invuln:busy() or player_invuln:busy()) and elapsed.protection>=config.ProtectionPollMs
        local due_death=(death.pending()) and elapsed.death>=config.DeathPollMs
        local due_resource=resources:busy() and elapsed.resource>=config.ResourcePollMs
        if due_resource then
            due_dodge=false;due_protection=false
        elseif due_protection and (not due_dodge or elapsed.protection>=elapsed.dodge) then
            due_dodge=false
        elseif due_dodge then due_protection=false end
        local due_history_input=move_history.sampling and (not history_suspended) and elapsed.history_input>=(config.MoveHistoryPollMs or 100)
        local due_history=move_history.sampling and (not history_suspended) and elapsed.history>=(config.MoveHistorySlowPollMs or 200)
        local due_menu=visible and elapsed.menu>=config.MenuRefreshMs
        local status_present=status_hud.text~=nil
        local due_status=(damage.active or damage.armed or speed.active or boss_invuln.active or boss_invuln.armed or player_invuln.active or player_invuln.armed or resources:busy() or death.pending() or status_present) and elapsed.status>=config.StatusRefreshMs
        if not (due_monitor or due_practice or due_speed or due_damage or due_dodge or due_protection or due_death or due_resource or due_history_input or due_history or due_menu or due_status) then return false end
        if due_monitor then elapsed.monitor=0 end
        if due_practice then elapsed.practice=0 end
        if due_speed then elapsed.speed=0 end
        if due_damage then elapsed.damage=0 end
        if due_dodge then elapsed.dodge=0 end
        if due_protection then elapsed.protection=0 end
        if due_death then elapsed.death=0 end
        if due_resource then elapsed.resource=0 end
        if due_history_input then elapsed.history_input=0 end
        if due_history then elapsed.history=0 end
        if due_menu then elapsed.menu=0 end
        if due_status then elapsed.status=0 end
        local ok,err=xpcall(function()
            local context=context_now()
            -- Keep pawn-local state reads bounded. HUD visibility is
            -- sampled by the 500 ms monitor and becomes a gate for optional work.
            local need_state=due_monitor or due_speed or due_damage or due_protection or due_death or due_resource or due_menu or due_status
            local state=(need_state and context) and battle_state(context,false) or nil
            if due_monitor then monitor(context,state) end
            local tools_ready=false
            if due_damage or due_death or due_dodge or due_protection or due_resource then
                tools_ready=toggle_ready(context)
            end
            -- Do not spend game-thread time on practice/UI/table maintenance while the
            -- game is paused or the boss-intro HUD is hidden. Values already applied
            -- remain applied; only verification/rebinding waits for visible gameplay.
            if due_damage and tools_ready then damage:tick(context) end
            if due_speed and gameplay_ready then speed:tick(context) end
            if due_practice and gameplay_ready then practice:tick(context) end
            if due_death then
                local result,msg=death.tick(context,tools_ready)
                if result==false then log("NO-HIT RUN | "..tostring(msg)) end
            end
            if due_dodge and tools_ready then core:scan() end
            if due_protection and tools_ready then
                local function pending_apply(tool)
                    return tool.armed and ((not tool.active and not tool.lease and os.clock()>=tool.retry_after)
                        or (tool.active and context.token~=tool.token))
                end
                -- Snapshot/apply only one newly armed or replaced-context mode
                -- per dispatch. Normal bounded verification keeps its cadence.
                if pending_apply(player_invuln) then
                    player_invuln:tick(context,state and state.battle)
                elseif pending_apply(boss_invuln) then
                    boss_invuln:tick(context,state and state.battle)
                else
                    boss_invuln:tick(context,state and state.battle)
                    player_invuln:tick(context,state and state.battle)
                end
            end
            if due_resource and tools_ready then resources:tick(context,state and state.battle) end
            -- History input sampling is serialized here, after protection
            -- verification has fully returned. Engine APIs run only when work is due;
            -- history has no separate callback owner.
            if due_history_input and gameplay_ready then
                local hok,herr=xpcall(function() return move_history:tick() end,debug.traceback)
                if not hok then
                    log("DEFENSE FEED POLL ERROR | "..tostring(herr))
                    move_history:stop("serialized poll error")
                end
            end
            if due_history and gameplay_ready then move_history:slow_tick() end
            if due_menu and gameplay_ready then
                local menu_state=battle_state(context,true)
                refresh_panel(context,menu_state,false)
            end
            if due_status and gameplay_ready then refresh_status(context,state) end
        end,require("ProtectionError"))
        if not ok then log("POLL ERROR | "..err) end
        return false
    end
    local started,why=dispatch:start(base)
    if not started then
        log("DISPATCH UNAVAILABLE | "..why.."; no async scheduling fallback")
        return false,why
    end

    -- History and tools share this one persistent game-thread loop.

    log("Loaded. Press Alt+B for the menu.")
end

return Batch
