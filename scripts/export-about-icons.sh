#!/bin/bash
set -euo pipefail

ICON_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_COMPOSER_TOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICON_COMPOSER_TOOL" ]]; then
    echo "Icon Composer의 ictool을 찾을 수 없습니다. Xcode 설치와 선택 경로를 확인해 주세요." >&2
    exit 1
fi

for stage in 0 6 7 8 9 10; do
    case "$stage" in
        0) source="Assets/AppIcons/Pyororong.icon"; name="AboutAppIcon" ;;
        6) source="Assets/IconComposerSVG 2/06-growth-1/6.icon"; name="AboutEasterEgg6" ;;
        7) source="Assets/IconComposerSVG 2/07-growth-2/7.icon"; name="AboutEasterEgg7" ;;
        8) source="Assets/IconComposerSVG 2/08-growth-3/8.icon"; name="AboutEasterEgg8" ;;
        9) source="Assets/IconComposerSVG 2/09-growth-4/9.icon"; name="AboutEasterEgg9" ;;
        10) source="Assets/IconComposerSVG 2/10-phne-only/10.icon"; name="AboutEasterEgg10" ;;
    esac
    imageset="$ICON_PROJECT_DIR/Assets/Images.xcassets/$name.imageset"
    mkdir -p "$imageset"
    for appearance in Default Dark; do
        if [[ "$appearance" == Default ]]; then file="light.png"; else file="dark.png"; fi
        "$ICON_COMPOSER_TOOL" "$ICON_PROJECT_DIR/$source" --export-image \
            --output-file "$imageset/$file" --platform macOS --rendition "$appearance" \
            --width 512 --height 512 --scale 2 > /dev/null
    done
    cat > "$imageset/Contents.json" <<'JSON'
{
  "images": [
    { "filename": "light.png", "idiom": "universal" },
    {
      "appearances": [{ "appearance": "luminosity", "value": "dark" }],
      "filename": "dark.png",
      "idiom": "universal"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
JSON
    echo "$name: 라이트·다크 이미지를 출력했습니다."
done
