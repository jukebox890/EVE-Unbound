# EVE Unbound V1.0: compiled-code review

## Scope

The release includes one compiled file:
`Mods/BossLab/Native/BossLabGauge.dll` (Windows x64, 9,216 bytes).
All remaining code is plain-text Lua in `Mods/BossLab/Scripts`.

Complete native source and build inputs are in `native-source`:

| File | Purpose |
| --- | --- |
| `gauge.c` | Gauge-refill bridge and its validation checks |
| `signatures.h` | Expected executable bytes used to guard game compatibility |
| `kernel32.def` | Windows API import declarations |
| `msvcrt.def` | C-runtime import declarations |
| `build.py` | Original compiler and linker commands |
| `resource_fast.S` | In-memory resource transport and native status returns |
| `resource_transport.py` | Links the assembly and applies the checked transport extension |

## Runtime behavior

`NativeGaugeUE.lua` preloads the DLL at mod startup with `package.loadlib`;
resource refill starts disabled by default. When refill is enabled
for a new player/world context, the persistent game-thread loop writes a short
request to `Native/request.txt`, calls `BossLabRun` synchronously, then reads
`Native/response.txt`. Subsequent refills use `BossLabTick` with the verified
binding and return status in memory; they perform no request/response file access.
The Lua script checks current pawn/controller/world addresses and classes before
each call, and repeats the handshake when any bound address changes.
The native function checks the executable build/signatures, thread identity,
player/controller identity, readable pointers and gauge ranges before calling
the game's existing setter for the three current resource stats.

The DLL has no networking, process creation, external-process injection,
registry writes, executable patching on disk, hooks, worker threads or timers.
It reads the current game process. Lua writes `Native/request.txt`; the DLL reads
that request and writes `Native/response.txt` beside the DLL. The original
executable, player, pointer, value and
readback checks still run on every refill. It refuses the refill operation when
these checks fail. The refill interval and game-thread scheduling are unchanged.
Lua writes user-requested fight exports to `BossLab-attempts.csv` and reports
operational errors through UE4SS's log. These are separate from the native
request/response files.

Player invulnerability and the other gameplay modifiers are implemented in Lua;
the DLL's role is gauge refill.

## Reproduce and compare

Follow [BUILDING.md](../BUILDING.md). Python plus Zig 0.16.0 are sufficient;
the game and UE4SS are not needed to compile it.

The build compiles the included C implementation, assembles the transport source,
and applies three hash-checked DLL branch changes using the Python helper. The
transport extension preserves the C refill code and includes chained Windows
unwind metadata. No baseline DLL or opaque precompiled transport is required.

A Linux x64 rebuild with Zig 0.16.0 was compared byte-for-byte with the V1.0
release DLL and matched:

```text
409d00d74024296befcb74dc72790202bdc20d68b1604a6c939f208f8242cd16
```

The complete V1.0 archive supplied with this project has SHA-256:

```text
c69ff54b58f36f4998a560c47f98d7c0de9644e0e70c77ed65dde8859a8feae2
```

If the upload was repacked, use `release-manifest.json` to compare its extracted
files. Only V1.0 is presented for review. No loader binary, compiler, game
executable, nested archive or older development build is included in this
repository.
