#!/bin/bash
set -euo pipefail
service_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$service_dir/scripts/prepare.sh"
cd "$service_dir"
python3 -m unittest discover -s tests -p 'test_*.py' -v
go test -race tsunagu/backend/mobile tsunagu/backend/internal/sandbox ./...
go vet ./... tsunagu/backend/mobile tsunagu/backend/internal/sandbox
"$service_dir/scripts/build.sh"
"$service_dir/scripts/test-video-engine.sh"
xcrun clang -target arm64-apple-macos14.0 -fobjc-arc -fmodules \
  -I .build/ffmpeg/macos/include -F .build/Tsunagu.xcframework/macos-arm64 \
  -c native/TSVideoEngine.m -o .build/TSVideoEngine-macos.o
xcrun swiftc -swift-version 6 -parse-as-library \
  -F .build/Tsunagu.xcframework/macos-arm64 -framework Tsunagu -lresolv \
  -import-objc-header native/TSVideoEngine.h \
  swift/*.swift tests/Smoke.swift .build/TSVideoEngine-macos.o .build/ffmpeg/macos/lib/*.a \
  -framework WebKit -framework Security -framework VideoToolbox -framework CoreMedia \
  -framework CoreVideo -framework AudioToolbox -lz -lxml2 -o .build/backend-smoke
.build/backend-smoke
for pair in 'iphoneos ios-arm64 arm64-apple-ios18.2' 'iphonesimulator ios-arm64-simulator arm64-apple-ios18.2-simulator'; do
  read -r sdk slice target <<< "$pair"
  xcrun --sdk "$sdk" swiftc -swift-version 6 -typecheck \
    -target "$target" -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -F ".build/Tsunagu.xcframework/$slice" -import-objc-header native/TSVideoEngine.h swift/*.swift
done
