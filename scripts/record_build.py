#!/usr/bin/env python3
"""Record source revision and exported bytes so stale builds cannot be relabeled."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
target = sys.argv[1]
if target not in {"web", "android"}:
    raise SystemExit("Expected web or android")
directory = root / "build" / target
commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
dirty = subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"], text=True).strip()
record = {
    "commit": commit,
    "source_clean": not bool(dirty),
    "files": {file.name: hashlib.sha256(file.read_bytes()).hexdigest()
              for file in sorted(directory.iterdir())
              if file.is_file() and file.name != "build-source.json"},
}
(directory / "build-source.json").write_text(json.dumps(record, indent=2) + "\n")
