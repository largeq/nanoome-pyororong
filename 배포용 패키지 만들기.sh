#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$PROJECT_DIR/scripts/build-app.sh"

APP_PATH="$PROJECT_DIR/.build/xcode/Build/Products/Release/표로롱.app"
ARCHIVE_PATH="$PROJECT_DIR/.build/표로롱_v2.0.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"
echo "로컬 검증용 ZIP 생성 완료: $ARCHIVE_PATH"
echo "GitHub 공개 배포 전에는 Developer ID 서명과 Apple 공증을 진행하세요."
