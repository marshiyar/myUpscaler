#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
  echo 'This app requires an Apple Silicon Mac.' >&2
  exit 1
fi
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if ! xcrun metal -v > "$work/metal.log" 2>&1; then
  cat "$work/metal.log" >&2
  echo 'Install/select the Metal compiler component in Xcode before building. This check does not download it.' >&2
  exit 1
fi
for directory in myUpscaler/ThirdParty/ffmpeg third_party/CoreML; do
  if [[ ! -d "$directory" ]]; then
    echo "Not prepared: $directory (see CONTRIBUTING.md)"
  fi
done
echo 'Xcode and Metal compiler are available. Prepare FFmpeg/models before the full app build.'
