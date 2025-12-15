#!/bin/sh

# Install FFmpeg using Homebrew
brew install ffmpeg

# Copy dylibs into the expected location for the app bundle and tests
"$(dirname "$0")/fetch_ffmpeg_dylibs.sh"
