#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

bash "$PROJECT_DIR/scripts/export-about-icons.sh"

# Build both Mac architectures. This produces a local, ad-hoc-signed app.
# Hardened runtime library validation requires a Developer ID signature to load Sparkle.
# Disable it only for this local ad-hoc build; distribution keeps the project's hardened runtime.
xcodebuild \
    -project Pyororong.xcodeproj \
    -scheme Pyororong \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$PROJECT_DIR/.build/xcode" \
    -onlyUsePackageVersionsFromResolvedFile \
    'ARCHS=arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_HARDENED_RUNTIME=NO \
    build

echo "앱 생성 완료: $PROJECT_DIR/.build/xcode/Build/Products/Release/표로롱.app"
