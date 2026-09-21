#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/prepare.sh
python3 scripts/fetch-build-inputs.py
export JAVA_HOME="$PWD/.build/toolchains/jdk-21.0.12.1+1/Contents/Home"
.build/toolchains/gradle-8.14.4/bin/gradle -p ../vendor/Tsunagu/sandbox --no-daemon shadowJar
