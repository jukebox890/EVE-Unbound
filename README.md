# EVE Unbound V1.0

Optional power-ups and boss-practice tools for Stellar Blade on Windows PC.

**General:** player invulnerability, x1000 damage, Beta/Burst/Tachy refill,
perfect-dodge slow motion, outside-combat sprint speed, and save position/teleport.

**Boss practice:** no-hit runs, enemy invulnerability, defense history,
attempt recording, and fight statistics/CSV export.

Install with a working Stellar Blade UE4SS setup; SB UE4SS 1.3 is recommended.
See [installation and shortcuts](README.txt) and [CSV fields](CSV_FIELDS.md).
Keep the installation folder named `BossLab`.

## Source and Nexus review

This repository contains the V1.0 runtime files and the corresponding source
for its only compiled component, `Mods/BossLab/Native/BossLabGauge.dll`.

- [Native C source](native-source/gauge.c)
- [Executable signature guards](native-source/signatures.h)
- [Build instructions](BUILDING.md)
- [Reviewer notes](docs/NEXUS_REVIEW.md)
- [Release and source checksums](release-manifest.json)

The DLL refills Beta, Burst and Tachy gauges through an in-process game setter.
The other gameplay tools and menu are implemented in the Lua scripts under
`Mods/BossLab/Scripts`.

Rebuilding with Zig 0.16.0 produced the exact DLL distributed in V1.0:

```text
SHA-256: 887b364acf5ae07c1b8d320ad693957f20a6df9220b17bbe13a718fde1d83b01
```

Only the current V1.0 source and runtime are included; no earlier builds or
development history are required for review. Source is available for inspection;
this repository does not grant an open-source licence. Reuse permissions are
set by the author on the mod page.

## Thanks

Thank you to SHIFT UP for Stellar Blade, the Stellar Blade modding community
for guides and inspiration, and the UE4SS developers and loader maintainers.
Development was assisted by OpenAI Codex; menu artwork was created with OpenAI
image generation. UE4SS and build tools are separate dependencies.
