#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-simulator}"
if [[ "$platform" == simulator ]]; then
 conf=moku-iossim; ffi=libffi-sim
elif [[ "$platform" == device ]]; then
 conf=moku-ios; ffi=libffi-device
else
 echo "Use simulator or device" >&2; exit 2
fi
source_build=".build/openjdk-source/build/$conf"
output=".build/openjdk-local/$platform"
rm -rf "$output"
mkdir -p "$output/Headers" "$output/lib/modules"
cp "$source_build/jdk/include/"*.h "$source_build/jdk/include/ios/"*.h "$output/Headers/"
xcrun libtool -static -o "$output/libopenjdk.a" \
 "$source_build/images/static-libs/lib/zero/libjvm.a" \
 "$source_build/images/static-libs/lib/libjava.a" \
 "$source_build/images/static-libs/lib/libverify.a" \
 "$source_build/images/static-libs/lib/libjimage.a" \
 "$source_build/images/static-libs/lib/libnet.a" \
 "$source_build/images/static-libs/lib/libnio.a" \
 "$source_build/images/static-libs/lib/libzip.a" \
 ".build/$ffi/libffi.a"
for module in java.base java.logging java.management java.naming java.security.jgss java.security.sasl java.xml jdk.crypto.ec jdk.unsupported jdk.zipfs; do
 cp -R "$source_build/jdk/modules/$module" "$output/lib/modules/"
done
# Standard TLS trust roots, needed for HTTPS source requests.
mkdir -p "$output/lib/security"
cp "$source_build/jdk/lib/security/cacerts" "$output/lib/security/"

cp -R "$source_build/jdk/conf" "$output/lib/"
mkdir -p "$output/lib/lib"
cp "$source_build/jdk/lib/tzdb.dat" "$output/lib/lib/"
