#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD/.build/ffmpeg"
version=9.0.2
sha=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
archive="$PWD/.build/ffmpeg-$version.tar.xz"
mkdir -p "$root"
if [[ ! -f "$archive" ]]; then
  curl -fL --retry 3 "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" -o "$archive"
fi
printf '%s  %s\n' "$sha" "$archive" | shasum -a 256 -c -
[[ -d ".build/ffmpeg-$version" ]] || tar -xf "$archive" -C .build
source_dir="$PWD/.build/ffmpeg-$version"
for platform in "${@:-simulator}"; do
  case "$platform" in
    simulator) sdk=iphonesimulator; target=arm64-apple-ios18.2-simulator ;;
    device) sdk=iphoneos; target=arm64-apple-ios18.2 ;;
    macos) sdk=macosx; target=arm64-apple-macos14.0 ;;
    *) echo "unknown platform $platform" >&2; exit 2 ;;
  esac
  prefix="$root/$platform"
  [[ -f "$prefix/complete-$sha-dash1" ]] && continue
  mkdir -p "$prefix/build" "$prefix/pkgconfig"
  sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cat > "$prefix/pkgconfig/libxml-2.0.pc" <<PC
Name: libXML
Description: Apple SDK libxml2
Version: 2.9.4
Libs: -L$sdkpath/usr/lib -lxml2
Cflags: -I$sdkpath/usr/include/libxml2
PC
  export PKG_CONFIG_LIBDIR="$prefix/pkgconfig"
  export PKG_CONFIG_PATH=""
  pushd "$prefix/build" >/dev/null
  "$source_dir/configure" --prefix="$prefix" --target-os=darwin --arch=aarch64 \
    --enable-cross-compile --cc="$(xcrun --sdk "$sdk" -f clang)" \
    --sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)" \
    --extra-cflags="-target $target" --extra-ldflags="-target $target" \
    --disable-programs --disable-doc --disable-debug --disable-autodetect \
    --disable-gpl --disable-nonfree --disable-shared --enable-static \
    --disable-avdevice --disable-encoders \
    --enable-encoder=h264_videotoolbox,aac --enable-videotoolbox \
    --enable-securetransport --enable-zlib --enable-libxml2 --enable-network \
    --disable-protocols --enable-protocol=file,http,https,tcp,tls,crypto,data \
    > configure.log 2>&1
  make -j"${MOKU_BUILD_JOBS:-8}" > build.log 2>&1
  make install >> build.log 2>&1
  cp "$source_dir/COPYING.LGPLv2.1" "$prefix/"
  cp "$source_dir/LICENSE.md" "$prefix/"
  touch "$prefix/complete-$sha-dash1"
  popd >/dev/null
done
