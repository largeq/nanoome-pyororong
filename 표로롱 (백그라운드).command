#!/bin/bash
set -euo pipefail

# 표로롱 앱은 터미널과 독립적으로 실행됩니다.
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$PROJECT_DIR/scripts/run-app.sh"
