#!/usr/bin/env python3
"""Enforce the user-requested ceiling for maintained application source."""
from pathlib import Path
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

repo = Path(__file__).resolve().parents[1]
root = repo / "myUpscaler"
extensions = {".swift", ".rs", ".metal", ".slint"}
files = [p for base in (root, repo / "backend" / "src", repo / "desktop" / "src", repo / "desktop" / "ui") for p in base.rglob("*")
         if p.is_file() and p.suffix in extensions and "ThirdParty" not in p.parts]
def line_count(path):
    return len(path.read_text(encoding="utf-8", errors="replace").splitlines())


counts = {p: line_count(p) for p in files}
violations = [(p, n) for p, n in counts.items() if n > 600]
for path, count in violations:
    print(f"FAIL {path.relative_to(root.parent)}: {count} lines (limit 600)")
if violations:
    sys.exit(1)
print(f"PASS source budget: {len(files)} maintained files, maximum "
      f"{max(counts.values(), default=0)} lines")
