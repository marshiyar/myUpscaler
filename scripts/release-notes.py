#!/usr/bin/env python3
"""Writes the "Smoke tests" section of a release's description: for each platform, whether the desktop app's smoke
test passed (desktop/scripts/smoke-test.sh) and its three screenshots, shown from the release's own assets.

The section sits between two markers, so it is added to a release's existing description, or replaces the section
of an earlier run, without touching the rest of the text.

  release-notes.py <repository> <tag> <folder with the smoke results> [<existing description file>]
"""

import pathlib
import sys

START = "<!-- smoke-tests:start -->"
END = "<!-- smoke-tests:end -->"
PLATFORMS = [("macos", "macOS (Apple silicon)"), ("windows", "Windows (x64)"), ("linux", "Linux (x64)")]
SHOTS = [("1-import", "Import view"), ("2-adjustments", "Adjustments on a test clip"), ("3-export", "Export finished")]


def section(repository: str, tag: str, results: pathlib.Path) -> str:
    lines = [
        START,
        "## Smoke tests",
        "",
        "Each platform's build of the desktop app was run headless on that platform: the import view, the "
        "adjustments panel on a generated clip, and the clip exported end to end (the exported file is checked).",
    ]
    for key, label in PLATFORMS:
        result = results / f"smoke-{key}.txt"
        status = f"passed: {result.read_text().strip().removeprefix('passed on ')}" if result.is_file() else (
            "**failed or did not run** (see the release workflow's log)")
        lines += ["", f"### {label}: {status}"]
        shots = [(s, alt) for s, alt in SHOTS if (results / f"smoke-{key}-{s}.png").is_file()]
        if shots:
            base = f"https://github.com/{repository}/releases/download/{tag}"
            images = " ".join(f'<img src="{base}/smoke-{key}-{s}.png" alt="{label}: {alt}" width="32%">'
                              for s, alt in shots)
            lines += ["", f"<p>{images}</p>"]
    lines.append(END)
    return "\n".join(lines)


def merge(existing: str, new: str) -> str:
    """The description with the section replaced, or appended when it has none."""
    start, end = existing.find(START), existing.find(END)
    if start != -1 and end > start:
        return existing[:start] + new + existing[end + len(END):]
    return (existing.rstrip() + "\n\n" + new) if existing.strip() else new


def main() -> None:
    repository, tag, results = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
    existing = pathlib.Path(sys.argv[4]).read_text() if len(sys.argv) > 4 else ""
    print(merge(existing, section(repository, tag, results)).rstrip("\n"))


if __name__ == "__main__":
    main()
