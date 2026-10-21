#!/bin/bash
set -euo pipefail

# Swift 앱을 실행합니다. 첫 실행에 앱이 없으면 Xcode로 빌드합니다.
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$PROJECT_DIR/scripts/run-app.sh"
