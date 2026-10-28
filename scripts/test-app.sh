#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$PROJECT_DIR/scripts/build-app.sh"
BUILD_DIR="$PROJECT_DIR/.build/xcode/Build/Products/Release"
CHECK_BINARY="$PROJECT_DIR/.build/app-integration-checks"

xcrun swiftc -parse-as-library \
    -I "$BUILD_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/ConversionNotifier.swift" \
    "$PROJECT_DIR/Tests/AppIntegrationChecks.swift" \
    -o "$CHECK_BINARY"
"$CHECK_BINARY" "$PROJECT_DIR/.build/diagnostics/result-copy-2026-10-26"

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
    "$PROJECT_DIR/App/UsageGuideIllustration.swift" \
    "$PROJECT_DIR/Tests/SupportIntegrationChecks.swift" \
    -o "$SUPPORT_CHECK_BINARY"
"$SUPPORT_CHECK_BINARY" "$BUILD_DIR/표로롱.app" "$PROJECT_DIR/.build/diagnostics/support-2026-10-28"

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
"$SHORTCUT_CHECK_BINARY" "$PROJECT_DIR/.build/diagnostics/shortcut-settings-2026-10-28"

MENU_CHECK_BINARY="$PROJECT_DIR/.build/menu-integration-checks"
xcrun swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx12.0" \
    -I "$BUILD_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/AppDelegate.swift" \
    "$PROJECT_DIR/App/ConversionNotifier.swift" \
    "$PROJECT_DIR/App/ShortcutSettingsController.swift" \
    "$PROJECT_DIR/App/UsageGuideController.swift" \
    "$PROJECT_DIR/App/UsageGuideIllustration.swift" \
    "$PROJECT_DIR/App/AboutController.swift" \
    "$PROJECT_DIR/Tests/MenuIntegrationChecks.swift" \
    "$PROJECT_DIR/App/SupportController.swift" \
    -o "$MENU_CHECK_BINARY"
"$MENU_CHECK_BINARY"

GUIDE_CHECK_BINARY="$PROJECT_DIR/.build/usage-guide-integration-checks"
xcrun swiftc -parse-as-library \
    -target "$(uname -m)-apple-macosx12.0" \
    -I "$BUILD_DIR" \
    "$BUILD_DIR/TableConverterMac.o" \
    "$BUILD_DIR/TableConverterCore.o" \
    "$BUILD_DIR/SwiftSoup.o" -lz \
    "$PROJECT_DIR/App/UsageGuideController.swift" \
    "$PROJECT_DIR/App/UsageGuideIllustration.swift" \
    "$PROJECT_DIR/App/AboutController.swift" \
    "$PROJECT_DIR/Tests/UsageGuideIntegrationChecks.swift" \
    "$PROJECT_DIR/App/SupportController.swift" \
    -o "$GUIDE_CHECK_BINARY"
"$GUIDE_CHECK_BINARY" "$PROJECT_DIR/.build/diagnostics/usage-guide" "$BUILD_DIR/표로롱.app"
