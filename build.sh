#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "test" ]; then
    swiftc -o /tmp/flick-checks Sources/Core.swift Sources/Strings.swift Widget/WidgetShared.swift Tests/checks.swift
    exec /tmp/flick-checks
fi

# DynamicLakeKit 은 바이너리 xcframework 다. 4.5MB 라 레포에 넣지 않고 한 번 받아 캐시한다.
KIT="Vendor/DynamicLakeKit.xcframework"
FW="$KIT/macos-arm64_x86_64"
if [ ! -d "$KIT" ]; then
    echo "fetching DynamicLakeKit..."
    rm -rf .kit
    git clone --depth 1 -q "https://github.com/rokach/DynamicLakeKit---Dynamic-Island-Kit-for-Mac.git" .kit
    mkdir -p Vendor && mv .kit/DynamicLakeKit.xcframework Vendor/ && rm -rf .kit
fi

# ExtensionKit 은 팀 ID 가 있는 서명을 요구한다. ad-hoc(-) 은 팀 ID 가 없어
# 앱은 돌아도 DynamicLake 확장 목록에 안 뜬다. Xcode 에 Apple ID 를 넣으면
# "Apple Development" 인증서가 생기고, 그러면 여기서 자동으로 집어 쓴다.
SIGN="${FLICK_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Developer ID Application|Apple Development/ {print $2; exit}')}"
if [ -z "$SIGN" ]; then
    SIGN="-"
    echo "warning: 코드서명 인증서가 없어 ad-hoc 으로 서명합니다 (DynamicLake 확장은 안 뜰 수 있음)"
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
mkdir -p "$TMP/Contents/Frameworks"
cp -R "$FW/DynamicLakeKit.framework" "$TMP/Contents/Frameworks/"
for ARCH in arm64 x86_64; do
    swiftc -O -target $ARCH-apple-macos14.0 \
        -F "$FW" -framework DynamicLakeKit \
        -Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
        Sources/*.swift Lake/Shared.swift Widget/WidgetShared.swift -o "$TMP/Flick-$ARCH"
done
lipo -create "$TMP"/Flick-* -output "$TMP/Contents/MacOS/Flick"
rm "$TMP"/Flick-*

# DynamicLake 확장(.appex). UI 만 들었고 로직은 앱에 있다.
APPEX="$TMP/Contents/Extensions/FlickLake.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp Lake/Info.plist "$APPEX/Contents/Info.plist"
for ARCH in arm64 x86_64; do
    swiftc -O -target $ARCH-apple-macos14.0 -parse-as-library \
        -F "$FW" -framework DynamicLakeKit \
        -Xlinker -rpath -Xlinker "@loader_path/../../../../Frameworks" \
        Lake/*.swift -o "$APPEX/FlickLake-$ARCH"
done
lipo -create "$APPEX"/FlickLake-* -output "$APPEX/Contents/MacOS/FlickLake"
rm "$APPEX"/FlickLake-*

# 바탕화면 위젯(.appex). 그리기만 하고 로직은 앱에 있다. 샌드박스라 앱이 App Group 컨테이너에
# 써 준 상태 파일만 읽는데, 그룹은 팀 ID 서명이라야 인정된다 — ad-hoc 이면 위젯만 빼고 만든다.
WIDGET="$TMP/Contents/PlugIns/FlickWidget.appex"
if [ "$SIGN" = "-" ]; then
    echo "warning: ad-hoc 서명이라 바탕화면 위젯은 빼고 만듭니다 (App Group 에 팀 ID 서명이 필요)"
else
    mkdir -p "$WIDGET/Contents/MacOS"
    cp Widget/Info.plist "$WIDGET/Contents/Info.plist"
    for ARCH in arm64 x86_64; do
        # Xcode 가 앱 확장에 하듯 진입점을 _NSExtensionMain 으로 둔다. @main 은 WidgetBundle 을 알리는 용도다.
        swiftc -O -target $ARCH-apple-macos14.0 -parse-as-library -application-extension \
            -Xlinker -e -Xlinker _NSExtensionMain \
            Widget/*.swift -o "$WIDGET/FlickWidget-$ARCH"
    done
    lipo -create "$WIDGET"/FlickWidget-* -output "$WIDGET/Contents/MacOS/FlickWidget"
    rm "$WIDGET"/FlickWidget-*
fi

# ad-hoc 서명의 기본 요구사항은 cdhash 라 빌드마다 바뀌고, 그러면 TCC 가 다른 앱으로 보고
# Downloads 권한을 다시 묻는다. 요구사항을 번들 ID 로 고정해 재빌드해도 같은 앱으로 알아보게 한다.
# ponytail: 같은 번들 ID 를 단 아무 ad-hoc 앱도 권한을 이어받는다. 배포 땐 Developer ID 서명으로 바꿀 것.
codesign --force --sign "$SIGN" "$TMP/Contents/Frameworks/DynamicLakeKit.framework"
codesign --force --sign "$SIGN" --entitlements Lake/FlickLake.entitlements "$APPEX"
if [ -d "$WIDGET" ]; then
    codesign --force --sign "$SIGN" --entitlements Widget/FlickWidget.entitlements "$WIDGET"
    # 그룹 이름이 팀 ID 로 시작해서, 다른 팀 인증서로 서명하면 macOS 가 그룹을 인정하지 않는다.
    GROUP=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' Widget/FlickWidget.entitlements)
    TEAM=$(codesign -dv "$WIDGET" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    if [ "$TEAM" != "${GROUP%%.*}" ]; then
        echo "warning: 서명 팀($TEAM)이 위젯 그룹($GROUP)과 달라 바탕화면 위젯은 뺍니다" \
             "(Widget/*.entitlements 와 Widget/WidgetShared.swift 의 그룹을 이 팀 ID 로 바꾸면 들어갑니다)"
        rm -rf "$TMP/Contents/PlugIns"
    fi
fi
if [ "$SIGN" = "-" ]; then
    codesign --force --sign - -r='designated => identifier "io.github.haewonkr.flick"' "$TMP"
elif [ -d "$WIDGET" ]; then
    codesign --force --sign "$SIGN" --options runtime --entitlements Widget/FlickApp.entitlements "$TMP"
else
    codesign --force --sign "$SIGN" --options runtime "$TMP"
fi

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
