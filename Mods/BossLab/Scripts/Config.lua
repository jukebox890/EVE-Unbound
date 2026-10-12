-- EVE Unbound V1.0 defaults and shortcuts.
return {
    DamageKey=0x6B, DamageDurationKey=0x6F,
    SpeedKey=0x6A,
    MenuKey=0x42, MenuModifiers={"ALT"}, MenuBackupKey=nil,
    ToggleKey=0x61, RecordKey=0x62, MarkKey=0x63, ReturnKey=0x64,
    InputKey=0x65, ExportKey=0x68,
    ResetKey=0x60, BossInvulnKey=0x6D, PlayerInvulnKey=0x6E,

    -- Alt+Num5 refills Beta/Burst/Tachy on the game thread; OFF stops refills.
    ResourceAllKey=0x65, ResourceAllModifiers={"ALT"},
    KillKey=0x67, KillModifiers={},

    PanelX=32, PanelY=72, PanelWidth=1440, PanelHeight=810,
    -- Compact status area with room for every active mode.
    StatusX=34, StatusY=250, StatusWidth=850, StatusHeight=260, StatusFontSize=17,

    MoveHistoryDefaultOn=false,
    -- Focused E/Shift/W/S sampling shares the persistent game-thread loop.
    -- 33 ms is ~30 Hz; input and maintenance use one persistent game-thread loop.
    MoveHistoryPollMs=33,
    MoveHistorySlowPollMs=132,
    MoveHistoryLines=4, MoveHistoryStoredEvents=10,
    MoveHistoryCentered=true, MoveHistoryX=0, MoveHistoryY=240, MoveHistoryWidth=620, MoveHistoryHeight=180, MoveHistoryFontSize=16,
    MoveHistoryDefenseLookbackMs=800, MoveHistoryLateLookaheadMs=180, MoveHistoryOrderWindowMs=180,
    MoveHistoryDamageGroupMs=300, MoveHistoryHPEpsilon=0.0005,

    LoopMs=33,
    MonitorMs=500,
    PracticePollMs=200,
    SpeedPollMs=250,
    SprintTimeoutSeconds=0, -- persistent toggle; combat/context changes still restore it
    DamagePollMs=100,
    DodgeScanMs=1000,
    ProtectionPollMs=100,
    DeathPollMs=250,
    -- Keep the incoming-damage factor bounded for no-hit practice.
    NoDamageRunFactor=100,
    NoDamageRunAllowPrearm=true,
    NoDamageRunMinRate=100,
    NoDamageRunMaxRate=10000,
    ExtendedDodgeSlowMoFactor=8.0,
    ExtendedDodgeTimeScaleMultiplier=0.5, -- multiply the game's own perfect-dodge TimeScale by 0.5
    ResourcePollMs=250, -- native refill cadence while enabled and gameplay is ready
    MenuRefreshMs=1000,
    StatusRefreshMs=200,
    PreFightReturnLimit=1500,
    BattleEndDebouncePolls=2,

    MaxAttempts=100, SampleGapSeconds=1.5, HPDropEpsilon=0.05, HPDropGroupSeconds=0.3,
}
