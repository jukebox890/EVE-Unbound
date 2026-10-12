# Build and verify V1.0

The native DLL builds from the seven files in `native-source`. The Lua scripts
are already source code. No game executable, UE4SS SDK, Lua library or other
mod source is needed for this build.

## Requirements

- Python 3.8 or newer.
- Zig **0.16.0**, including its `lib` directory.

The compiler is available from the [Zig download page](https://ziglang.org/download/)
or the maintainers' [ziglang Python package](https://pypi.org/project/ziglang/0.16.0/).
Pin 0.16.0 when comparing with the published binary.

## Windows

Open a terminal in the repository folder. Install the pinned compiler and build:

```powershell
py -m pip install ziglang==0.16.0
py tools/rebuild.py
```

If your installation provides `python` instead of `py`, use `python` in both
commands. An optional virtual environment can keep the compiler installation
separate from your other Python packages.

## Linux or macOS

```sh
python3 -m pip install ziglang==0.16.0
python3 tools/rebuild.py
```

Both routes produce a **Windows x64 DLL**, including when the build host is Linux
or macOS. The script checks the compiler version, runs the original build script,
and verifies the result against the V1.0 checksum. The output replaces this
repository's `Mods/BossLab/Native/BossLabGauge.dll`; build in a source checkout,
with the game closed, rather than in your installed game folder.

## Using a downloaded Zig distribution

Pass the path to the compiler explicitly:

```powershell
py tools/rebuild.py "C:\Tools\zig-0.16.0\zig.exe"
```

Or invoke the original build script directly:

```powershell
py native-source/build.py "C:\Tools\zig-0.16.0\zig.exe"
py tools/verify.py
```

On Linux/macOS, use `python3` and the corresponding path to `zig`.

## What the build does

`native-source/build.py` compiles `gauge.c` with Zig's Clang, creates Windows
import libraries from `kernel32.def` and `msvcrt.def`, and links the native
refill implementation using LLD. Its options include optimization, warnings
as errors, ASLR, NX, and a zero PE timestamp.

It then assembles `resource_fast.S` with the same compiler. The standard-library
Python helper `resource_transport.py` resolves that object's relative references
and adds the V1.0 resource transport. It checks the C-built input hash, the three
instruction sites and the final output hash. No precompiled extension, older DLL,
GNU assembler/linker, game executable or private Lua-state layout is needed.

The original native refill and validation implementation stays byte-identical.
The transport adds RX code, RW binding storage and chained Windows x64 unwind
metadata. `DllMain` records the module handle; `BossLabRun` performs the initial
file handshake, and `BossLabTick` handles subsequent refills without file access.
Native errors select a result from the Lua caller's fixed stack arguments using
the standard Lua C callback result convention.

## Verify source and runtime

```powershell
py tools/verify.py
```

This checks all 32 published runtime/documentation files and the seven native
source/build files against `release-manifest.json`.

If you also have the original release ZIP, verify that exact archive:

```powershell
py tools/verify.py --archive "C:\Downloads\EVE-Unbound-V1.0.zip"
```

Published checksums:

```text
BossLabGauge.dll (9,216 bytes)
409d00d74024296befcb74dc72790202bdc20d68b1604a6c939f208f8242cd16

EVE-Unbound-V1.0.zip (3,990,654 bytes)
c69ff54b58f36f4998a560c47f98d7c0de9644e0e70c77ed65dde8859a8feae2
```

If your Nexus upload was repacked, its archive checksum will differ. Extract
it and compare the files with the manifest; an unchanged DLL still has the
checksum above. A successful rebuild proves binary correspondence, not an
independent antivirus certification or Nexus approval.
