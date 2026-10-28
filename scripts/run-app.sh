#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/.build/xcode/Build/Products/Release/표로롱.app"

if [ ! -d "$APP_PATH" ]; then
    /bin/bash "$PROJECT_DIR/scripts/build-app.sh"
fi
/usr/bin/open "$APP_PATH"
