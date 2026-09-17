# Flick

Downloads(또는 지정한 감시 폴더)에 파일이 들어오면 팝업을 띄워 어디로 옮길지 물어보는 macOS 메뉴바 앱입니다.

*A macOS menu bar app that pops up when a file lands in Downloads (or any watched folder) and moves it to a preset folder with a single key. Korean, English and German(Prototype) UI.*

## 설치 · Install

[Releases](https://github.com/Haewonkr/Flick/releases/latest) 에서 `Flick.dmg` 를 받아 열고 `Flick` 을 Applications 로 끌어다 놓습니다. macOS 13 이상, Apple Silicon · Intel 모두 지원합니다.

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

macOS 13+ / Xcode 커맨드라인 도구(`swiftc`)만 있으면 됩니다. 빌드 결과는 macOS 13 이상용 유니버설 바이너리(arm64 + x86_64)입니다. (Apple Silicon 권장)

점검:

```bash
./build.sh test
```

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

## 구조

| 파일 | 역할 |
|---|---|
| `Sources/Core.swift` | 프리셋, 단축키 배정, 이동, 기록 — UI 없는 순수 로직 |
| `Sources/main.swift` | FSEvents 감시, 팝업, 메뉴바(최근 기록·되돌리기·일시정지·자동 실행) |
| `Sources/Editor.swift` | 설정 창 (일반 · 프리셋 탭) |
| `Sources/Strings.swift` | 언어 선택과 영어 · 독일어 번역표 |
| `Sources/Welcome.swift` | 첫 실행 안내 창 |
| `Tests/checks.swift` | `Core.swift` 에 대한 assert 점검 |

## 라이선스 · License

[MIT](LICENSE)
