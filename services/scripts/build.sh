#!/bin/bash
set -euo pipefail
service_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$service_dir/scripts/prepare.sh"
cd "$service_dir"
mkdir -p .build/tools
# Tool versions live in go.mod/go.sum, not an unpinned global installation.
GOBIN="$service_dir/.build/tools" go install golang.org/x/mobile/cmd/gobind
export PATH="$service_dir/.build/tools:$PATH"
go tool gomobile bind \
  -target=ios/arm64,iossimulator/arm64,macos/arm64 \
  -iosversion=18.0 \
  -o .build/Tsunagu.xcframework .
