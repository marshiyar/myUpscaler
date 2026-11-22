#!/bin/bash
# Downloads the sample clip used for the window pictures (Real-ESRGAN inputs/video, pinned to a commit) and checks its hash.
# The clip is not stored in this repository.
# Usage: scripts/fetch-sample-clip.sh <output.mp4>
set -euo pipefail

out=${1:?output file}
url=https://raw.githubusercontent.com/xinntao/Real-ESRGAN/a4abfb2979a7bbff3f69f58f58ae324608821e27/inputs/video/onepiece_demo.mp4
sha256=2f2084db2ca6b363b0857758ac99084775c7f40cd074bf7e23c35e2ce0477778

mkdir -p "$(dirname "$out")"
curl -fsSL --retry 3 "$url" -o "$out"
echo "$sha256  $out" | shasum -a 256 -c -
