# Flick

Downloads(또는 지정한 감시 폴더)에 파일이 들어오면 팝업을 띄워 어디로 옮길지 물어보는 macOS 메뉴바 앱입니다.

*A macOS menu bar app that pops up when a file lands in Downloads (or any watched folder) and moves it to a preset folder with a single key. Korean, English and German(Prototype) UI.*

## 설치 · Install

[Releases](https://github.com/Haewonkr/Flick/releases/latest) 에서 `Flick.dmg` 를 받아 열고 `Flick` 을 Applications 로 끌어다 놓습니다. macOS 14 이상, Apple Silicon · Intel 모두 지원합니다.

Apple 공증을 받지 않은 앱이라 처음 열 때 macOS 가 막습니다. 한 번 열기를 시도한 뒤 시스템 설정 > 개인정보 보호 및 보안 아래의 "그래도 열기" 를 누르거나, 터미널에서 다음을 실행하세요.

*The app is not notarized, so macOS blocks the first launch. Try opening it once, then click **Open Anyway** in System Settings > Privacy & Security, or run:*

```bash
xattr -dr com.apple.quarantine /Applications/Flick.app
```

Flick 은 실행 시와 하루에 한 번 GitHub API(`api.github.com`)로 최신 릴리즈 버전만 확인합니다.


## 빌드 · 실행 · Build

```bash
./build.sh          # Flick.app 생성 (ad-hoc 서명 포함)
open Flick.app
```

`./build.sh dmg` 는 앱과 Applications 바로가기를 담은 `Flick.dmg` 를 함께 만듭니다. 열어서 앱을 Applications 로 끌어다 놓으면 설치됩니다.

macOS 14+ / Xcode 커맨드라인 도구(`swiftc`)만 있으면 됩니다. 빌드 결과는 macOS 14 이상용 유니버설 바이너리(arm64 + x86_64)입니다. (Apple Silicon 권장)

첫 빌드 때 `build.sh` 가 DynamicLakeKit(바이너리 xcframework)을 `Vendor/` 로 한 번 받습니다.

바탕화면 위젯은 팀 ID 가 있는 인증서(Xcode 에 Apple ID 를 넣으면 생기는 "Apple Development" 등)로 서명할 때만 들어갑니다. 위젯은 샌드박스라 앱이 App Group(`88DH2SR88S.io.github.haewonkr.flick`) 컨테이너에 써 준 상태 파일을 읽는데, 이 그룹은 같은 팀 ID 로 서명해야 인정되기 때문입니다. 인증서가 없거나(ad-hoc, `FLICK_SIGN_ID=-`) 팀이 다르면 경고만 내고 위젯 없이 만들며, 앱은 그대로 동작합니다. 다른 팀으로 빌드하려면 `Widget/*.entitlements` 와 `Widget/WidgetShared.swift` 의 그룹 앞부분을 그 팀 ID 로 바꾸세요.

점검:

```bash
./build.sh test
```

### 위젯 수동 확인

자동 점검이 못 보는 부분입니다. 앱은 Finder 나 별도 터미널에서 띄웁니다(Claude Code 셸에서 띄우면 메뉴바 항목이 "claude" 에 묶입니다).

1. `./build.sh` 에 위젯 경고가 없고 `Flick.app/Contents/PlugIns/FlickWidget.appex` 가 있는지 봅니다.
2. 켜져 있는 이전 Flick(예: `~/Applications/Flick.app`)을 종료하고 새 `Flick.app` 을 엽니다(Applications 로 옮겨 열어도 됩니다). 번들 ID 가 같아 둘이 함께 돌면 팝업이 두 번 뜨고, 위젯 클릭이 위젯을 모르는 이전 버전으로 갈 수 있습니다.
3. 바탕화면 우클릭 › 위젯 편집… 에서 Flick 의 `Flick Inbox` 와 `Flick History` 를 중간 · 큰 크기로 추가합니다. 갤러리 설명이 앱 언어로 나오는지 봅니다(제목은 영문 고정).
4. 파일을 하나 받아 esc(그대로 두기) → `Flick Inbox` 맨 위에 생기고 개수가 늘어나는지.
5. `Flick Inbox` 의 그 줄을 클릭 → 그 파일로 팝업이 다시 뜨는지. 다시 esc → 위젯에 돌아오는지. 이번엔 프리셋으로 옮기기 → `Flick Inbox` 에서 빠지고 `Flick History` 맨 위에 생기는지.
6. `Flick History` 의 줄을 클릭 → Finder 에서 그 파일이 선택되는지. 메뉴바에서 되돌린 뒤 같은 줄을 클릭 → 옮겼던 폴더가 열리는지.
7. 4개 이상 남겨 두면 중간 크기에, 9개 이상이면 큰 크기에도 `+N개 더` 가 뜨는지. 설정 › 일반 › 언어를 바꾸면 위젯 문구도 바뀌는지.
8. 몇 분 뒤 `Flick History` 의 `N분 전` 이 따라 바뀌는지.

## 동작 규칙

- 목적지에 같은 이름이 있으면 `name (2).ext` 로 비켜갑니다.
- `.crdownload`, `.part`, `.tmp` 등 받는 중인 파일과 숨김 파일은 무시합니다.
- 파일 크기가 0.5초 동안 변하지 않아야 완료로 봅니다.(최대 30분 대기).
- 팝업은 한 번에 하나, 여러 개 받으면 팝업 아래에 대기열이 보이고 차례로 뜹니다.
- 대기열이 있을 때 `일괄 옮기기`(⌘A)를 켜고 폴더를 고르면 대기 중인 파일도 같은 폴더로 함께 옮깁니다. 바꾼 이름은 지금 파일에만 적용되고, 메뉴바의 되돌리기는 함께 옮긴 파일을 한 번에 되돌립니다.
- 프리셋 키(또는 클릭)는 그 폴더로 옮기고, `⇧`+키(또는 ⇧클릭)는 그 폴더의 하위 폴더로 들어갑니다(하위 폴더가 없으면 그냥 옮김). 하위 폴더에도 1–9, 0, a–z 가 이름순으로 붙고, 같은 방식으로 더 들어가거나 옮길 수 있습니다. `⌫`·`esc` 로 한 단계 위로 갑니다. 하위 폴더가 있는 타일엔 `›` 가 붙습니다.
- 팝업의 `옮긴 후 열기`(=)를 켜고 옮기면 옮긴 파일을 기본 앱으로 엽니다(일괄로 함께 옮긴 파일은 열지 않음). 처음에 켜 둘지는 설정 > 일반 > 팝업에서 고릅니다.
- 타이핑 중(마지막 키 입력 1.5초 이내)에 팝업이 뜨면 키보드를 가져가지 않습니다. 팝업을 클릭하면 키로 고를 수 있습니다. 팝업이 키보드를 받은 뒤 0.4초 동안 누른 키와 길게 눌러 반복되는 키는 무시합니다. 둘 다 설정 > 일반 > 팝업에서 끌 수 있습니다.
- 프리셋 탭의 `⋯` 메뉴로 프리셋을 JSON 파일로 내보내고 가져옵니다(`presets.json` 과 같은 형식). 가져올 때 추가를 고르면 이미 있는 폴더는 건너뛰고, 지금 쓰는 키와 겹치는 키는 비워 기존 단축키가 바뀌지 않게 합니다. 바꾸기를 고르면 파일 내용으로 통째로 바뀝니다.
- 이동에 실패하면 알림을 띄우고 파일은 원래 폴더에 그대로 남습니다.
- 설정 > 일반 > 감시 폴더에서 Downloads를 끄고 켤 수 있고, 폴더를 5개까지 더 추가해 각각 켜고 끌 수 있습니다. 바로 아래 파일만 보고 하위 폴더는 보지 않습니다.
- 되돌리기는 파일을 처음 들어온 감시 폴더로 돌려놓습니다.
- 팝업에서 `그대로 두기`(esc)한 파일 개수가 메뉴바 아이콘의 화살표 자리에 뜹니다. 그 파일을 옮기거나 지우면 줄어듭니다.
- 바탕화면 위젯은 두 가지이고 중간(두 칸) · 큰(네 칸) 크기가 있습니다. 바탕화면 우클릭 › 위젯 편집… 에서 추가합니다.
  - `Flick Inbox`(남은 파일): 그대로 두기한 파일을 최근 것부터 보여 줍니다(중간 3줄, 큰 8줄, 넘치면 `+N개 더`). 누르면 그 파일로 팝업이 다시 뜨고, 다른 팝업이 떠 있으면 바로 다음 차례가 됩니다.
  - `Flick History`(옮긴 기록): 옮긴 파일을 최신순으로 옮긴 폴더 · 상대 시각과 함께 보여 줍니다. 누르면 Finder 에서 그 파일을 고르고, 나중에 지웠거나 옮겼으면 옮겼던 폴더를 엽니다.
  - Flick 이 그대로 두기 · 옮기기 · 기록 삭제 · 언어 변경 때마다 위젯을 새로 그립니다. 위젯이 여는 `flick://` 주소로는 그대로 두기 목록에 있는 파일만 팝업에 다시 올릴 수 있습니다.

## 구조

| 파일 | 역할 |
|---|---|
| `Sources/Core.swift` | 프리셋, 단축키 배정, 이동, 기록 — UI 없는 순수 로직 |
| `Sources/main.swift` | FSEvents 감시, 팝업, 메뉴바(최근 기록·되돌리기·일시정지·자동 실행), 위젯 상태 갱신 · `flick://` 주소 처리 |
| `Sources/Editor.swift` | 설정 창 (일반 · 프리셋 탭) |
| `Sources/Strings.swift` | 언어 선택과 영어 · 독일어 번역표 |
| `Sources/Welcome.swift` | 첫 실행 안내 창 |
| `Sources/Lake.swift` | DynamicLake 노치 — 상태 게시와 버튼 입력 수신 |
| `Lake/` | DynamicLake 확장(.appex) — 노치에 그리는 SwiftUI 뷰 |
| `Widget/` | 바탕화면 위젯 확장(.appex) — Flick Inbox(남은 파일) · Flick History(옮긴 기록) SwiftUI 뷰. `WidgetShared.swift` 는 앱과 같이 컴파일하는 상태 파일 형식과 `flick://` 주소 |
| `Tests/checks.swift` | `Core.swift` · `Widget/WidgetShared.swift` 에 대한 assert 점검 |

## 라이선스 · License

[MIT](LICENSE)
