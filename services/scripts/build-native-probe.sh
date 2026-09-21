#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-simulator}"
if [[ "$platform" == simulator ]]; then
 sdk=iphonesimulator; target=arm64-apple-ios18.2-simulator; slice=ios-arm64_x86_64-simulator; archive=libsim.a; go_slice=ios-arm64-simulator
elif [[ "$platform" == device ]]; then
 sdk=iphoneos; target=arm64-apple-ios18.2; slice=ios-arm64; archive=libdevice.a; go_slice=ios-arm64
else
 echo "Usage: $0 [simulator|device]" >&2; exit 2
fi
jdk=".build/openjdk/OpenJDK.xcframework/OpenJDK.xcframework/$slice"
if [[ "${MOKU_LOCAL_JDK:-1}" == 1 ]]; then
 jdk=".build/openjdk-local/$platform"; archive=libopenjdk.a
fi
./scripts/build-ffmpeg.sh "$platform"
ffmpeg=".build/ffmpeg/$platform"
output=".build/native-$platform"
app="$output/MokuBackendProbe.app"
rm -rf "$app"
mkdir -p "$app/lib/modules" "$app/ThirdPartyNotices/FFmpeg" .build/java/{probe,fixture}
cp "$ffmpeg/COPYING.LGPLv2.1" "$ffmpeg/LICENSE.md" "$app/ThirdPartyNotices/FFmpeg/"
cp THIRD_PARTY_MEDIA.md "$app/ThirdPartyNotices/FFmpeg/BUILD-AND-SOURCE.md"
javac --release 11 -d .build/java/probe java/RuntimeProbe.java
javac --release 11 -d .build/java/fixture tests/java/Extension.java
jar cf .build/java/RuntimeProbe.jar -C .build/java/probe .
jar cf .build/java/Fixture.jar -C .build/java/fixture .
cp .build/java/*.jar "$app/"
if [[ -f ../vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar ]]; then
 cp ../vendor/Tsunagu/sandbox/build/libs/sandbox-0.1.0-all.jar "$app/Sandbox.jar"
fi
if [[ "${MOKU_LOCAL_JDK:-1}" == 1 ]]; then
 cp -R "$jdk/lib/" "$app/lib/"
else
 cp -R ".build/openjdk/java.base-$platform/java.base" "$app/lib/modules/"
fi
sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
xcrun clang -target "$target" -isysroot "$sdkpath" -fobjc-arc -fmodules -I"$jdk/Headers" -c native/TSJavaRuntime.m -o "$output/TSJavaRuntime.o"
xcrun clang -target "$target" -isysroot "$sdkpath" -fobjc-arc -fmodules -I"$ffmpeg/include" -F".build/Tsunagu.xcframework/$go_slice" -c native/TSVideoEngine.m -o "$output/TSVideoEngine.o"
xcrun libtool -static -o "$output/libtsmedia.a" "$ffmpeg"/lib/*.a
xcrun libtool -static -o "$output/libtsunagu.a" "$output/TSJavaRuntime.o" "$output/TSVideoEngine.o" ".build/Tsunagu.xcframework/$go_slice/Tsunagu.framework/Tsunagu" "$jdk/$archive"
xcrun clang -target "$target" -isysroot "$sdkpath" -fobjc-arc -fmodules -Inative -F".build/Tsunagu.xcframework/$go_slice" tests/NativeProbe.m -Wl,-export_dynamic -Wl,-force_load,"$output/libtsunagu.a" "$output/libtsmedia.a" -framework Foundation -framework UIKit -framework Security -framework CoreFoundation -framework CFNetwork -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework AudioToolbox -lresolv -lz -lxml2 -lc++ -o "$app/MokuBackendProbe"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.moku.backendprobe</string>
<key>CFBundleExecutable</key><string>MokuBackendProbe</string>
<key>CFBundleName</key><string>MokuBackendProbe</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>MinimumOSVersion</key><string>18.2</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "$app"
