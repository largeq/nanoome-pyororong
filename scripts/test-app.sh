#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIAGNOSTICS_DIR="$PROJECT_DIR/.build/diagnostics/app-$(date +%Y%m%d-%H%M%S)"
echo "통합 검사 자료: $DIAGNOSTICS_DIR"
bash "$PROJECT_DIR/scripts/build-app.sh"
BUILD_DIR="$PROJECT_DIR/.build/xcode/Build/Products/Release"
SPARKLE_FRAMEWORK_DIR="$PROJECT_DIR/.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
CHECK_BINARY="$PROJECT_DIR/.build/app-integration-checks"

xcrun swiftc -parse-as-library \
    -I "$BUILD_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/ConversionNotifier.swift" \
    "$PROJECT_DIR/Tests/AppIntegrationChecks.swift" \
    -o "$CHECK_BINARY"
"$CHECK_BINARY" "$DIAGNOSTICS_DIR/result-copy"

SUPPORT_CHECK_BINARY="$PROJECT_DIR/.build/support-integration-checks"
xcrun swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx12.0" \
    -I "$BUILD_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/SupportController.swift" \
    "$PROJECT_DIR/App/AboutController.swift" \
    "$PROJECT_DIR/App/UsageGuideController.swift" \
    "$PROJECT_DIR/App/UsageGuideVideoView.swift" \
    "$PROJECT_DIR/Tests/SupportIntegrationChecks.swift" \
    -o "$SUPPORT_CHECK_BINARY"
"$SUPPORT_CHECK_BINARY" "$BUILD_DIR/표로롱.app" "$DIAGNOSTICS_DIR/support"

SHORTCUT_CHECK_BINARY="$PROJECT_DIR/.build/shortcut-settings-integration-checks"
xcrun swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx12.0" \
    -I "$BUILD_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/ShortcutSettingsController.swift" \
    "$PROJECT_DIR/Tests/ShortcutSettingsIntegrationChecks.swift" \
    -o "$SHORTCUT_CHECK_BINARY"
"$SHORTCUT_CHECK_BINARY" "$DIAGNOSTICS_DIR/settings"

MENU_CHECK_BINARY="$PROJECT_DIR/.build/menu-integration-checks"
xcrun swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx12.0" \
    -I "$BUILD_DIR" \
    -F "$SPARKLE_FRAMEWORK_DIR" -framework Sparkle \
    -Xlinker -rpath -Xlinker "$SPARKLE_FRAMEWORK_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/AppDelegate.swift" \
    "$PROJECT_DIR/App/UpdateController.swift" \
    "$PROJECT_DIR/App/ConversionNotifier.swift" \
    "$PROJECT_DIR/App/ShortcutSettingsController.swift" \
    "$PROJECT_DIR/App/UsageGuideController.swift" \
    "$PROJECT_DIR/App/UsageGuideVideoView.swift" \
    "$PROJECT_DIR/App/AboutController.swift" \
    "$PROJECT_DIR/Tests/MenuIntegrationChecks.swift" \
    "$PROJECT_DIR/App/SupportController.swift" \
    -o "$MENU_CHECK_BINARY"
"$MENU_CHECK_BINARY"

UPDATE_CHECK_BINARY="$PROJECT_DIR/.build/update-integration-checks"
xcrun swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx12.0" \
    -I "$BUILD_DIR" \
    -F "$SPARKLE_FRAMEWORK_DIR" -framework Sparkle \
    -Xlinker -rpath -Xlinker "$SPARKLE_FRAMEWORK_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/SupportController.swift" \
    "$PROJECT_DIR/App/UpdateController.swift" \
    "$PROJECT_DIR/Tests/UpdateIntegrationChecks.swift" \
    -o "$UPDATE_CHECK_BINARY"
"$UPDATE_CHECK_BINARY" "$BUILD_DIR/표로롱.app" "$DIAGNOSTICS_DIR/updates"

GUIDE_CHECK_BINARY="$PROJECT_DIR/.build/usage-guide-integration-checks"
xcrun swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx12.0" \
    -I "$BUILD_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/UsageGuideController.swift" \
    "$PROJECT_DIR/App/UsageGuideVideoView.swift" \
    "$PROJECT_DIR/App/AboutController.swift" \
    "$PROJECT_DIR/Tests/UsageGuideIntegrationChecks.swift" \
    "$PROJECT_DIR/App/SupportController.swift" \
    -o "$GUIDE_CHECK_BINARY"
"$GUIDE_CHECK_BINARY" "$DIAGNOSTICS_DIR/usage-guide" "$BUILD_DIR/표로롱.app"
