"""Verify the current V1.0 files and, optionally, the original release ZIP."""
from pathlib import Path
import argparse
import hashlib
import json
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Original EVE-Unbound-V1.0.zip")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / "release-manifest.json").read_text(encoding="utf-8"))
    failed = []
    for group in ("release_files", "native_source_files"):
        for item in manifest[group]:
            path = root / item["path"]
            if not path.is_file():
                failed.append(item["path"] + ": missing")
                continue
            data = path.read_bytes()
            if len(data) != item["size_bytes"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
                failed.append(item["path"] + ": checksum/size mismatch")
    if args.archive:
        if not args.archive.is_file():
            failed.append(str(args.archive) + ": missing")
        else:
            data = args.archive.read_bytes()
            expected = manifest["release_archive"]
            if len(data) != expected["size_bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
                failed.append(str(args.archive) + ": archive checksum/size mismatch")
    if failed:
        print("Verification failed:\n" + "\n".join(failed), file=sys.stderr)
        return 1
    print("Verified %d V1.0 files and %d native source/build files." %
          (len(manifest["release_files"]), len(manifest["native_source_files"])))
    if args.archive:
        print("Original release archive checksum also matches.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
