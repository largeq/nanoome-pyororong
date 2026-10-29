#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMGBUILD="$PROJECT_DIR/.build/dmg-tools/bin/dmgbuild"
if [ "$#" -ne 2 ]; then
    echo "사용법: bash scripts/build-dmg.sh <공증된 앱.app> <새 출력.dmg>" >&2
    exit 1
fi
APP_PATH="$1"
OUTPUT_PATH="$2"
if [ ! -d "$APP_PATH/Contents" ] || [ -e "$OUTPUT_PATH" ]; then
    echo "읽을 수 있는 앱과 아직 존재하지 않는 출력 경로가 필요합니다." >&2
    exit 1
fi
if [ ! -x "$DMGBUILD" ]; then
    echo "먼저 DMG 빌드 도구를 준비하세요:" >&2
    echo "python3 -m venv .build/dmg-tools" >&2
    echo ".build/dmg-tools/bin/python -m pip install -r scripts/requirements-dmg.txt" >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
codesign --verify --deep --strict "$APP_PATH"
mkdir -p "$(dirname "$OUTPUT_PATH")"
"$DMGBUILD" -s "$PROJECT_DIR/scripts/dmg-settings.py" \
    -D "app=$APP_PATH" -D "background=$PROJECT_DIR/Assets/DMG/background.png" \
    "표로롱 $VERSION" "$OUTPUT_PATH"

# dmgbuild does not propagate ditto's exit status; verify the completed copy before publishing.
MOUNT_PATH="$(mktemp -d "${TMPDIR:-/tmp}/pyororong-dmg-check.XXXXXX")"
MOUNTED=0
cleanup() {
    if [ "$MOUNTED" -eq 1 ]; then hdiutil detach "$MOUNT_PATH" >/dev/null; fi
    rmdir "$MOUNT_PATH"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_PATH" "$OUTPUT_PATH" >/dev/null
MOUNTED=1
codesign --verify --deep --strict "$MOUNT_PATH/표로롱.app"
python3 - "$APP_PATH" "$MOUNT_PATH/표로롱.app" <<'PY'
import hashlib
import os
import stat
import sys
import unicodedata
from pathlib import Path

def manifest(directory):
    entries = {}
    for path in Path(directory).rglob('*'):
        name = unicodedata.normalize('NFC', str(path.relative_to(directory)))
        mode = stat.S_IMODE(path.lstat().st_mode)
        if path.is_symlink():
            value = ('symlink', mode, os.readlink(path))
        elif path.is_file():
            value = ('file', mode, hashlib.sha256(path.read_bytes()).hexdigest())
        else:
            value = ('directory', mode)
        entries[name] = value
    return entries

if manifest(sys.argv[1]) != manifest(sys.argv[2]):
    raise SystemExit('완성된 DMG의 앱이 원본과 다릅니다. 배포를 중단합니다.')
PY
hdiutil detach "$MOUNT_PATH" >/dev/null
MOUNTED=0
