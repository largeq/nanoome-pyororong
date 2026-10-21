#!/bin/bash
set -euo pipefail

# Swift 앱은 터미널과 독립적으로 실행됩니다. 기존 실행 파일 이름을 유지합니다.
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$PROJECT_DIR/scripts/run-app.sh"
