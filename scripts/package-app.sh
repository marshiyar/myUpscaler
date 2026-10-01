#!/bin/bash
set -euo pipefail

app=${1:?Supply the built app path}
output=${2:?Supply the delivery directory}
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
work_dir=$(mktemp -d)
mounted=0
cleanup() {
  if [[ $mounted == 1 ]]; then
    hdiutil detach "$work_dir/mount" >/dev/null || return
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

verify_app() {
  local bundle=$1
  for executable in "$bundle/Contents/MacOS/myUpscaler" \
      "$bundle/Contents/MacOS/up60p-ffmpeg-supervisor" \
      "$bundle/Contents/MacOS/ThirdParty/FFmpeg/ffmpeg"; do
    test -x "$executable"
    [[ $(xcrun lipo -archs "$executable") == arm64 ]]
    codesign --verify --strict "$executable"
  done
  codesign --verify --deep --strict "$bundle"
  bash "$repo_dir/scripts/validate-bundled-models.sh" "$bundle"
  cmp "$repo_dir/myUpscaler/ThirdParty/RealESRGAN-LICENSE.txt" "$bundle/Contents/Resources/RealESRGAN-LICENSE.txt"
}

verify_app "$app"
mkdir -p "$output" "$work_dir/image" "$work_dir/unzipped" "$work_dir/mount"
ditto "$app" "$work_dir/image/myUpscaler.app"
ln -s /Applications "$work_dir/image/Applications"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/MyUpscaler-arm64.zip"
# Actions artifacts do not preserve executable permissions on raw .app folders.
# Check the inner ZIP after extraction before delivering it.
ditto -x -k "$output/MyUpscaler-arm64.zip" "$work_dir/unzipped"
verify_app "$work_dir/unzipped/myUpscaler.app"
hdiutil create -volname MyUpscaler -srcfolder "$work_dir/image" \
  -format UDZO "$output/MyUpscaler-arm64.dmg"
hdiutil verify "$output/MyUpscaler-arm64.dmg"
hdiutil attach "$output/MyUpscaler-arm64.dmg" -readonly -nobrowse -mountpoint "$work_dir/mount"
mounted=1
verify_app "$work_dir/mount/myUpscaler.app"
hdiutil detach "$work_dir/mount"
mounted=0
(
  cd "$output"
  shasum -a 256 MyUpscaler-arm64.zip MyUpscaler-arm64.dmg > SHA256SUMS.txt
)
cat > "$output/BUILD-INFO.txt" <<INFO
MyUpscaler Actions test build (Apple Silicon; macOS 15.2+)
Commit: ${BUILD_COMMIT:-$(git -C "$repo_dir" rev-parse HEAD)}
Run: ${BUILD_RUN_URL:-local build}
Configuration: Release
Signing: ad hoc; not Developer ID signed or notarized.

This artifact includes the app, bundled FFmpeg, and validated CoreML models.
Use the DMG to copy myUpscaler.app into Applications, or extract the inner
MyUpscaler-arm64.zip to preserve the app's executable permissions.
macOS may require approval in System Settings > Privacy & Security > Open Anyway.
This build is retained as an Actions artifact and is not published to Releases.
INFO
echo 'Verified ZIP and DMG app bundles, signatures, architecture and model assets.'
