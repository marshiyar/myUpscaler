#!/usr/bin/env python3
"""Enforce the user-requested ceiling for maintained application source."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1] / "myUpscaler"
extensions = {".swift", ".c", ".h", ".m", ".metal"}
files = [p for p in root.rglob("*") if p.is_file() and p.suffix in extensions
         and "ThirdParty" not in p.parts]
violations = [(p, len(p.read_text().splitlines())) for p in files
              if len(p.read_text().splitlines()) > 600]
for path, count in violations:
    print(f"FAIL {path.relative_to(root.parent)}: {count} lines (limit 600)")
if violations:
    sys.exit(1)
print(f"PASS source budget: {len(files)} maintained files, maximum "
      f"{max((len(p.read_text().splitlines()) for p in files), default=0)} lines")
