#!/bin/bash
set -euo pipefail

# 표로롱 — 네이버 카페·블로그 표 변환 앱을 실행합니다. 앱이 없으면 Xcode로 빌드합니다.
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$PROJECT_DIR/scripts/run-app.sh"
