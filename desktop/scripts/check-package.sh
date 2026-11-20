#!/bin/bash
# Unpacks a package made by package.sh into an empty folder and runs the app from there: the window must render
# (--screenshot) with only the files in the package.
#
#   bash scripts/check-package.sh <package file> <work folder>     (run from desktop/)
set -euo pipefail

package=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
rm -rf "$2"
mkdir -p "$2"
work=$(cd "$2" && pwd)
case $package in
  *.zip)
    if command -v unzip >/dev/null; then
      unzip -q "$package" -d "$work"
    else
      powershell.exe -NoProfile -Command "Expand-Archive -LiteralPath '$(cygpath -w "$package")' -DestinationPath '$(cygpath -w "$work")'"
    fi
    ;;
  *) tar -xzf "$package" -C "$work" ;;
esac
dir=$(echo "$work"/*/)
app="${dir}myupscaler"
[[ -f $app.exe ]] && app=$app.exe
for licence in LICENSE.txt MpVFX-Media-LICENSE.txt MpVFX-Media-NOTICE.txt; do
  test -s "${dir}$licence" || { echo "Missing $licence in the package" >&2; exit 1; }
done
# Run from the unpacked folder only: nothing beside the build tree is on the way.
(cd "$dir" && "$app" --screenshot "$work/package-check.png")
test -s "$work/package-check.png"
echo "package ok: $(basename "$package")"
