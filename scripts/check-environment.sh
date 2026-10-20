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
for directory in third_party/mpvfx-media/lib third_party/CoreML; do
  if [[ ! -d "$directory" ]]; then
    echo "Not prepared: $directory (see CONTRIBUTING.md)"
  fi
done
command -v cargo > /dev/null || echo 'Not installed: Rust (rustup; the toolchain is pinned in rust-toolchain.toml)'
echo 'Xcode and Metal compiler are available. Prepare the media engine (scripts/prepare-media-engine.sh) and models before the full app build.'
