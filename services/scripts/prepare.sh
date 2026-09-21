#!/bin/bash
set -euo pipefail
service_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$service_dir/.." && pwd)"
source_dir="$repo_dir/vendor/Tsunagu"
if [ ! -f "$source_dir/backend/go.mod" ]; then
  git -C "$repo_dir" submodule update --init --recursive -- vendor/Tsunagu
fi
patch_file="$service_dir/patches/0001-embedded-core.patch"
# Never reset the submodule or overwrite edits to make a patch fit.
if git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
  exit 0
fi
git -C "$source_dir" apply --check "$patch_file"
git -C "$source_dir" apply "$patch_file"
