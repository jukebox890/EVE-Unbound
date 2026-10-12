"""Rebuild the V1.0 Windows DLL with Zig 0.16.0 and verify its checksum."""
from pathlib import Path
import argparse
import importlib.util
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zig", nargs="?", help="Path to a Zig 0.16.0 executable")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.zig:
        zig = Path(args.zig).expanduser().resolve()
    else:
        spec = importlib.util.find_spec("ziglang")
        if not spec or not spec.origin:
            parser.error("Install ziglang==0.16.0 or supply the path to zig.")
        zig = Path(spec.origin).parent / ("zig.exe" if sys.platform == "win32" else "zig")
    if not zig.is_file():
        parser.error("Zig executable not found: " + str(zig))
    version = subprocess.check_output([str(zig), "version"], text=True).strip()
    if version != "0.16.0":
        parser.error("Expected Zig 0.16.0; found " + version)
    print("Building with Zig " + version, flush=True)
    subprocess.run([sys.executable, str(root / "native-source/build.py"), str(zig)], check=True)
    subprocess.run([sys.executable, str(root / "tools/verify.py")], check=True)


if __name__ == "__main__":
    main()
