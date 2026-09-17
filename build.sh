#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "test" ]; then
    swiftc -o /tmp/flick-checks Sources/Core.swift Sources/Strings.swift Tests/checks.swift
    exec /tmp/flick-checks
fi

APP="Flick.app"
# 최종 경로에서 조립하면 swiftc가 도는 수십 초 동안 "실행 파일 없는 앱"으로 보여서
# Finder가 금지 아이콘을 그려 캐시해 버린다. 옆에서 다 만들고 마지막에 갈아끼운다.
TMP=".build.app"
rm -rf "$TMP"
mkdir -p "$TMP/Contents/MacOS"
mkdir -p "$TMP/Contents/Resources"
cp Info.plist "$TMP/Contents/Info.plist"
xcrun actool --compile "$TMP/Contents/Resources" --app-icon Flick \
    --output-partial-info-plist /dev/null --platform macosx \
    --minimum-deployment-target 13.0 --target-device mac Flick.icon >/dev/null
# -target 없이 빌드하면 이 Mac 의 OS 버전이 최소 버전으로 박혀 구버전 macOS 에서 안 열린다.
# Apple Silicon · Intel 을 각각 macOS 13 기준으로 빌드해 하나로 합친다.
for ARCH in arm64 x86_64; do
    swiftc -O -target $ARCH-apple-macos13.0 Sources/*.swift -o "$TMP/Flick-$ARCH"
done
lipo -create "$TMP"/Flick-* -output "$TMP/Contents/MacOS/Flick"
rm "$TMP"/Flick-*

# ad-hoc 서명의 기본 요구사항은 cdhash 라 빌드마다 바뀌고, 그러면 TCC 가 다른 앱으로 보고
# Downloads 권한을 다시 묻는다. 요구사항을 번들 ID 로 고정해 재빌드해도 같은 앱으로 알아보게 한다.
# ponytail: 같은 번들 ID 를 단 아무 ad-hoc 앱도 권한을 이어받는다. 배포 땐 Developer ID 서명으로 바꿀 것.
codesign --force --sign - -r='designated => identifier "io.github.haewonkr.flick"' "$TMP"

rm -rf "$APP" && mv "$TMP" "$APP"

echo "built $APP"

if [ "${1:-}" = "dmg" ]; then
    # 앱 + Applications 바로가기만 담은 이미지. 열어서 끌어다 놓으면 설치 끝.
    STAGE=".dmg"
    rm -rf "$STAGE" Flick.dmg
    mkdir "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname Flick -srcfolder "$STAGE" -format UDZO -o Flick.dmg >/dev/null
    rm -rf "$STAGE"
    echo "built Flick.dmg"
fi
