#!/bin/bash
# Builds a separate disposable test app. Does not replace or launch the product app.
set -euo pipefail
cd "$(dirname "$0")/.."
device="${1:?Pass a connected device identifier}"
team="${MOKU_DEVELOPMENT_TEAM:-7D6BVN4W87}"
./scripts/build-ffmpeg.sh device
mkdir -p .build/device-media
ffmpeg -v error -y -f lavfi -i testsrc2=size=160x96:rate=10 -f lavfi -i sine=frequency=440:sample_rate=48000 -t 2 -c:v libx264 -pix_fmt yuv420p -c:a aac .build/device-media/input.mp4
ffmpeg -v error -y -i .build/device-media/input.mp4 -c:v mpeg4 -c:a pcm_s16le .build/device-media/convert.avi
python3 - "$team" <<'PY'
import json,sys
from pathlib import Path
service=Path.cwd();build=service/'.build/device-media'
config={'name':'MediaValidation','options':{'deploymentTarget':{'iOS':'18.2'}},'targets':{'MediaValidation':{'type':'application','platform':'iOS','sources':[str(service/'tests/NativeMediaDeviceProbe.m'),str(service/'native/TSVideoEngine.m'),{'path':str(build/'input.mp4'),'buildPhase':'resources'},{'path':str(build/'convert.avi'),'buildPhase':'resources'}],'settings':{'base':{'PRODUCT_BUNDLE_IDENTIFIER':'com.moku.media-validation','DEVELOPMENT_TEAM':sys.argv[1],'CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','HEADER_SEARCH_PATHS':f'{service}/native {service}/.build/ffmpeg/device/include','FRAMEWORK_SEARCH_PATHS':str(service/'.build/Tsunagu.xcframework/ios-arm64'),'CLANG_ENABLE_OBJC_ARC':'YES','OTHER_LDFLAGS':' '.join(str(p) for p in sorted((service/'.build/ffmpeg/device/lib').glob('*.a')))+' -framework UIKit -framework Foundation -framework Security -framework CoreMedia -framework CoreVideo -framework VideoToolbox -framework AudioToolbox -lz -lxml2'}}}}}
(build/'project.json').write_text(json.dumps(config))
PY
xcodegen generate --spec .build/device-media/project.json --project .build/device-media
xcodebuild -project .build/device-media/MediaValidation.xcodeproj -scheme MediaValidation -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/device-media/DerivedData -allowProvisioningUpdates build > .build/device-media-build.log 2>&1
xcrun devicectl device install app --device "$device" .build/device-media/DerivedData/Build/Products/Debug-iphoneos/MediaValidation.app > .build/device-media-install.log
trap 'xcrun devicectl device uninstall app --device "$device" com.moku.media-validation > .build/device-media-cleanup.log 2>&1 || true' EXIT
xcrun devicectl device process launch --device "$device" --console --timeout 60 com.moku.media-validation > .build/device-media-result.log 2>&1
python3 - <<'PY'
import json,pathlib
log=pathlib.Path('.build/device-media-result.log').read_text()
line=next(line for line in log.splitlines() if line.startswith('MEDIA_DEVICE_RESULT '))
rows=json.loads(line.removeprefix('MEDIA_DEVICE_RESULT '))
assert len(rows)==2 and all(row['passed'] for row in rows),rows
print('Physical-device embedded MP4 remux + VideoToolbox/AAC conversion: PASS')
PY
