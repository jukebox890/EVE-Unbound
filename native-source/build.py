"""Build with a Zig 0.16 distribution: python native-source/build.py /path/to/zig
No UE4SS SDK, Lua library, game executable or third-party mod source is required.
"""
from pathlib import Path
import subprocess,sys,tempfile
from resource_transport import apply_transport
zig=Path(sys.argv[1]).resolve();src=Path(__file__).resolve().parent
out=src.parent/'Mods/BossLab/Native/BossLabGauge.dll'
def run(*args):subprocess.run([str(zig),*map(str,args)],check=True)
with tempfile.TemporaryDirectory() as td:
 tmp=Path(td)
 run('clang','-target','x86_64-w64-windows-gnu','-fms-extensions',
     '-isystem',zig.parent/'lib/include','-isystem',zig.parent/'lib/libc/include/any-windows-any',
     '-O2','-Wall','-Wextra','-Werror','-c',src/'gauge.c','-o',tmp/'gauge.obj')
 for name in ['kernel32','msvcrt']:
  run('dlltool','-m','i386:x86-64','-d',src/(name+'.def'),'-l',tmp/(name+'.lib'))
 run('lld-link','/dll','/entry:DllMain','/nodefaultlib','/machine:x64','/dynamicbase','/nxcompat',
     '/timestamp:0','/out:'+str(out),'/implib:'+str(tmp/'gauge.lib'),tmp/'gauge.obj',tmp/'kernel32.lib',tmp/'msvcrt.lib')
 # Assemble and apply only the resource transport extension. The C-built
 # refill implementation and validation remain unchanged.
 run('clang','-target','x86_64-unknown-linux-gnu','-c',src/'resource_fast.S','-o',tmp/'resource_fast.o')
 apply_transport(out,tmp/'resource_fast.o')
print(out)
