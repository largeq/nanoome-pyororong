#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Build both Mac architectures. This produces a local, ad-hoc-signed app.
# Developer ID signing and notarization are separate release steps.
xcodebuild \
    -project PhronesisPyo.xcodeproj \
    -scheme PhronesisPyo \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$PROJECT_DIR/.build/xcode" \
    -onlyUsePackageVersionsFromResolvedFile \
    'ARCHS=arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    build

echo "앱 생성 완료: $PROJECT_DIR/.build/xcode/Build/Products/Release/프네 표변환.app"
