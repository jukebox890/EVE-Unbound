EVE UNBOUND V1.0
Gameplay modifiers and boss-practice tools for Stellar Blade on Windows PC.
Combined package with the full in-game menu.

INSTALL / UPGRADE
1. Close the game. Use a working Stellar Blade UE4SS installation. UE4SS is
   required separately and is not included in this ZIP.
2. If upgrading, back up your existing Mods/BossLab folder outside the active
   Mods directory. Save any BossLab-attempts.csv exports you want to keep.
3. Remove the old BossLab folder, then copy this ZIP's Mods/BossLab folder into
   your UE4SS Mods directory. Replace the folder completely rather than merging.
   Keep the folder name BossLab; it is the mod's existing install identifier.
4. Start the game and press Alt+B once normal gameplay is available.

Use one EVE Unbound/BossLab installation at a time. Do not run this combined
package alongside its standalone modules. Existing UE4SS files are unchanged.

CONTROLS
"Num" means the numeric keypad. Shortcuts work with the menu open or closed.

Alt+B       Open / close menu
Num .       Player invulnerability ON / OFF
Alt+Num 5   Beta / Burst / Tachy refill ON / OFF
Num *       Outside-combat sprint: OFF -> 5x -> 2x -> OFF
Num 3       Save current position
Num 4       Return to saved position
Num +       x1000 damage ON / OFF, using the selected duration
Num /       Damage duration: 2 s / 3 s / 5 s / Toggle (default 3 s)
Num 1       Dodge slow-mo: NORMAL -> OFF -> EXTENDED -> NORMAL
Num 7       No-hit run ON / OFF
Num -       Enemy / boss invulnerability ON / OFF
Num 5       Defense feed ON / OFF
Num 2       Automatic combat recording ON / OFF
Num 8       Export completed attempts to BossLab-attempts.csv
Num 0       Reset tools and clear the saved position

DEFAULTS AND USE
Optional modifiers start OFF; dodge slow-mo starts NORMAL. Automatic combat
recording starts ON. No settings carry over to a new game session.

Player invulnerability works in normal gameplay, including outside combat.
No-hit run is a combat practice mode that amplifies incoming attack damage;
it can be armed before combat. Turn player invulnerability off before using it.
Enemy invulnerability and x1000 damage replace one another when selected.

Sprint affects running outside combat and returns to normal on combat or a
player/world change. Saved positions belong to the current player/world;
combat entry refreshes a pre-fight mark. Return requires ground movement.

Tools may show WAITING/ARMED during loading, cutscenes or pauses and apply once
gameplay is stable. Very rapid key presses can fill the two-entry input queue;
additional presses are ignored. There is no fixed toggle delay.

The defense feed shows the latest four defense entries during combat. It reads
E / Left Shift / W / S. Input observations do not prove a successful defense.
Active-tool text and the feed are hidden while the menu is open.

FIGHT EXPORTS
Completed attempts are retained for the current session, up to 100. Export
before closing the game; Num 8 writes the current completed history into
Mods/BossLab/BossLab-attempts.csv and replaces the previous export. An active
attempt must finish before it appears in the CSV. See CSV_FIELDS.md for the
health recovery, damage, timing, sampling and input metrics.

COMPATIBILITY
Use the UE4SS setup that supports the game's reflected table APIs and
LoopInGameThreadWithDelay. If the required loop API is missing, the mod reports
DISPATCH UNAVAILABLE in UE4SS.log and does not start its tools.

The native resource bridge checks the game build and player identity before
refilling gauges. An unsupported build stops refill. Remove old passive gauge
regeneration PAKs if the refill tool reports REMOVE_REGEN_PAK; remove only their
matching .pak/.utoc/.ucas files, with the game closed. Avoid other mods editing
the same damage, dodge slow-mo or sprint values at the same time.

UNINSTALL
Close the game and remove Mods/BossLab. Keep your fight CSVs if desired.

V1.0
Based on the stable v0.3.41 gameplay implementation. Testing probes, trace
hooks, performance profiling and test log exports have been removed. The
menu artwork, controls, defaults and game-thread scheduling are retained.
Only runtime files and user documentation are distributed.

V1.0 RESOURCE PERFORMANCE UPDATE
Routine Beta/Burst/Tachy refills now use an in-memory native call. Request and
response files are used only to establish a fresh player/world binding, rather
than on every refill. The refill interval, native game/player validation,
readback checks and stable game-thread scheduling are unchanged. No background
worker, toggle delay, extra diagnostic logging or UE4SS change is introduced.
Install both the updated Lua script and DLL by replacing Mods/BossLab as above.

PROJECT NOTES
Developed with OpenAI Codex and iterative in-game feedback. Menu artwork was
created with OpenAI image generation. UE4SS is an external dependency; the
menu uses Stellar Blade's existing widgets and font. No loader, game files,
external font, build tools or development dependencies are bundled.
