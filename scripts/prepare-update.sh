#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_TOOLS="$PROJECT_DIR/.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin"
KEY_ACCOUNT="com.phronesis.pyororong"

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "사용법: bash scripts/prepare-update.sh <공증된 앱.app> <변경사항.md> <새 출력 폴더> [이전 appcast.xml]" >&2
    exit 1
fi
APP_PATH="$1"
NOTES_PATH="$2"
OUTPUT_PATH="$3"
PREVIOUS_FEED="${4:-$PROJECT_DIR/updates/appcast.xml}"
if [ "$#" -eq 4 ] && [ ! -f "$PREVIOUS_FEED" ]; then
    echo "이전 업데이트 안내 파일을 찾을 수 없습니다: $PREVIOUS_FEED" >&2
    exit 1
fi
if [ -e "$OUTPUT_PATH" ] || [ ! -f "$NOTES_PATH" ]; then
    echo "출력 폴더는 새 경로여야 하며, 읽을 수 있는 변경사항 파일이 필요합니다." >&2
    exit 1
fi
if [ ! -x "$SPARKLE_TOOLS/generate_appcast" ] || [ ! -x "$SPARKLE_TOOLS/sign_update" ]; then
    echo "먼저 Xcode에서 Sparkle 의존성을 해결하세요. scripts/build-app.sh로 준비할 수 있습니다." >&2
    exit 1
fi

# Reject unsafe release inputs before creating an archive or output directory.
METADATA="$(python3 - "$APP_PATH" "$PROJECT_DIR/App/Info.plist" "$PREVIOUS_FEED" <<'PY'
import base64
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

app, source, prior = map(Path, sys.argv[1:])
def fail(message):
    raise SystemExit(message)
try:
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    config = plistlib.loads(source.read_bytes())
except (OSError, plistlib.InvalidFileException) as error:
    fail(f'앱 메타데이터를 읽을 수 없습니다: {error}')
if info.get('CFBundleIdentifier') != 'com.phronesis.pyororong':
    fail('표로롱 Bundle ID가 일치하지 않습니다.')
key = info.get('SUPublicEDKey', '')
try:
    valid_key = len(base64.b64decode(key, validate=True)) == 32
except (ValueError, TypeError):
    valid_key = False
if not valid_key or key != config.get('SUPublicEDKey'):
    fail('앱의 Sparkle 공개 키가 없거나 형식이 잘못되었거나 프로젝트 키와 다릅니다.')
if info.get('SUFeedURL') != config.get('SUFeedURL'):
    fail('앱의 업데이트 안내 주소가 프로젝트 설정과 다릅니다.')
if info.get('SUAutomaticallyUpdate') is not False or info.get('SUAllowsAutomaticUpdates') is not False:
    fail('자동 다운로드·설치가 비활성화된 앱만 배포할 수 있습니다.')
version = str(info.get('CFBundleShortVersionString', ''))
build = str(info.get('CFBundleVersion', ''))
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', build):
    fail('버전과 빌드 번호는 숫자와 점으로 구성해야 합니다.')
def number(value):
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))
if number(build) <= (0, 0, 0):
    fail('빌드 번호는 0보다 커야 합니다.')
if prior.exists():
    try:
        root = ET.parse(prior).getroot()
    except (OSError, ET.ParseError) as error:
        fail(f'이전 업데이트 안내 파일을 읽을 수 없습니다: {error}')
    if root.tag != 'rss' or root.find('channel') is None:
        fail('이전 업데이트 안내 파일은 RSS channel 구조여야 합니다.')
    ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    for item in root.findall('./channel/item'):
        enclosure = item.find('enclosure')
        previous_build = item.findtext(ns + 'version') or (enclosure.get(ns + 'version') if enclosure is not None else None)
        previous_version = item.findtext(ns + 'shortVersionString') or (enclosure.get(ns + 'shortVersionString') if enclosure is not None else None)
        if not previous_build or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', previous_build):
            fail('이전 안내 파일에 비교할 수 있는 빌드 번호가 없습니다.')
        if number(build) <= number(previous_build):
            fail('새 빌드 번호는 이전 배포의 모든 빌드 번호보다 커야 합니다.')
        if previous_version:
            if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', previous_version):
                fail('이전 안내 파일에 비교할 수 없는 버전이 있습니다.')
            if number(version) <= number(previous_version):
                fail('새 버전은 이전 배포의 모든 버전보다 커야 합니다.')
executable = str(info.get('CFBundleExecutable', ''))
if not executable or '/' in executable or any(c in executable for c in '\t\r\n'):
    fail('앱 실행 파일 이름이 올바르지 않습니다.')
print(f'{version}\t{build}\t{executable}')
PY
)"
IFS=$'\t' read -r VERSION BUILD EXECUTABLE <<< "$METADATA"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE="$(LC_ALL=C codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if [[ "$SIGNATURE" != *"Authority=Developer ID Application:"* ]] || \
   ! printf '%s\n' "$SIGNATURE" | /usr/bin/grep -Eq '^CodeDirectory .*flags=0x[[:xdigit:]]+\([^)]*runtime[^)]*\)'; then
    echo "Developer ID 서명과 hardened runtime이 필요합니다. 로컬 ad-hoc 빌드는 배포할 수 없습니다." >&2
    exit 1
fi
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/$EXECUTABLE")"
if ! [[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]]; then
    echo "Apple Silicon과 Intel을 포함한 Universal 앱이 필요합니다." >&2
    exit 1
fi
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

mkdir -p "$PROJECT_DIR/.build"
STAGING_DIR="$(mktemp -d "$PROJECT_DIR/.build/update-preparation.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ARCHIVE_NAME="Pyororong-${VERSION}-${BUILD}.zip"
DOWNLOAD_PREFIX="https://github.com/largeq/nanoome-pyororong/releases/download/v${VERSION}/"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$STAGING_DIR/$ARCHIVE_NAME"
cp "$NOTES_PATH" "$STAGING_DIR/Pyororong-${VERSION}-${BUILD}.md"
if [ -f "$PREVIOUS_FEED" ]; then cp "$PREVIOUS_FEED" "$STAGING_DIR/appcast.xml"; fi
"$SPARKLE_TOOLS/generate_appcast" \
    --account "$KEY_ACCOUNT" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --embed-release-notes \
    --link "https://github.com/largeq/nanoome-pyororong" \
    --versions "$BUILD" \
    --maximum-deltas 0 \
    --maximum-versions 0 \
    "$STAGING_DIR"
SIGNATURE="$(python3 - "$STAGING_DIR/appcast.xml" "$BUILD" "$DOWNLOAD_PREFIX$ARCHIVE_NAME" <<'PY'
import sys
import xml.etree.ElementTree as ET
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
for item in ET.parse(sys.argv[1]).getroot().findall('./channel/item'):
    enclosure = item.find('enclosure')
    if enclosure is not None and (item.findtext(ns + 'version') or enclosure.get(ns + 'version')) == sys.argv[2]:
        signature = enclosure.get(ns + 'edSignature')
        if enclosure.get('url') != sys.argv[3] or not signature:
            raise SystemExit('생성된 안내 파일의 다운로드 주소 또는 전자서명이 올바르지 않습니다.')
        print(signature)
        break
else:
    raise SystemExit('생성된 안내 파일에 새 버전 항목이 없습니다.')
PY
)"
"$SPARKLE_TOOLS/sign_update" --account "$KEY_ACCOUNT" --verify "$STAGING_DIR/$ARCHIVE_NAME" "$SIGNATURE"
mkdir -p "$(dirname "$OUTPUT_PATH")"
if [ -e "$OUTPUT_PATH" ]; then
    echo "출력 경로가 이미 존재합니다: $OUTPUT_PATH" >&2
    exit 1
fi
mv "$STAGING_DIR" "$OUTPUT_PATH"
trap - EXIT
printf '배포 준비 완료: %s\nGitHub Release 태그: v%s\n파일과 appcast는 아직 게시하지 않았습니다.\n' "$OUTPUT_PATH" "$VERSION"
