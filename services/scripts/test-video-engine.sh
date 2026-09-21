#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-ffmpeg.sh macos
ffmpeg=.build/ffmpeg/macos
xcrun clang -target arm64-apple-macos14.0 -fobjc-arc -fmodules \
 -I"$ffmpeg/include" -Inative -F.build/Tsunagu.xcframework/macos-arm64 \
 native/TSVideoEngine.m tests/VideoEngineProbe.m "$ffmpeg"/lib/*.a \
 -framework Foundation -framework Security -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework AudioToolbox -lz -lxml2 -o .build/video-engine-probe
python3 tests/video_engine_acceptance.py
