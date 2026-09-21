#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-simulator}"
if [[ "$platform" == simulator ]]; then
 sdk=iphonesimulator; conf=moku-iossim; ffi=libffi-sim; flags='-target arm64-apple-ios-simulator -mios-simulator-version-min=18.2'
elif [[ "$platform" == device ]]; then
 sdk=iphoneos; conf=moku-ios; ffi=libffi-device; flags='-target arm64-apple-ios -miphoneos-version-min=18.2'
else
 echo 'Use simulator or device' >&2; exit 2
fi
pin=dfd62e275c0970f75595f8bfe91eff34923fa896
source_dir="$PWD/.build/openjdk-source"
if [[ ! -d "$source_dir/.git" ]]; then
 git init "$source_dir"
 git -C "$source_dir" remote add origin https://github.com/openjdk/mobile.git
 git -C "$source_dir" fetch --depth 1 origin "$pin"
 git -C "$source_dir" checkout --detach FETCH_HEAD
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$pin" ]] || { echo 'OpenJDK checkout differs from pinned revision' >&2; exit 1; }
python3 scripts/fetch-build-inputs.py
patch_file="$PWD/patches/0002-openjdk-ios.patch"
if ! git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
 git -C "$source_dir" apply --check "$patch_file"
 git -C "$source_dir" apply "$patch_file"
fi
ffi_dir="$PWD/.build/$ffi"
cd "$source_dir"
bash configure --with-conf-name="$conf" --disable-warnings-as-errors \
 --openjdk-target=aarch64-macos-ios \
 --with-boot-jdk="${MOKU_BOOT_JDK:-/opt/homebrew/opt/openjdk@25}" \
 --with-sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)" \
 --with-libffi-include="$ffi_dir/include/ffi" --with-libffi-lib="$ffi_dir" \
 --with-extra-cflags="$flags" --with-extra-cxxflags="$flags" \
 --with-cups-include="$(xcrun --sdk macosx --show-sdk-path)/usr/include"
make JOBS=8 CONF="$conf" static-libs-image java java.base-gendata
cd ../..
./scripts/package-openjdk.sh "$platform"
