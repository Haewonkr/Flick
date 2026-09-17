import Foundation

// MARK: - 언어

enum AppLanguage: String, CaseIterable, Identifiable {
    case ko, en, de
    var id: String { rawValue }

    /// 언어 이름은 그 언어로 적는다 — 못 읽는 언어로 바꿔 버려도 되돌아올 수 있게.
    var displayName: String {
        switch self {
        case .ko: "한국어"
        case .en: "English"
        case .de: "Deutsch"
        }
    }

    static let defaultsKey = "language"

    /// 고른 적이 없으면 시스템 선호 언어 중 지원하는 첫 번째, 없으면 영어.
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        for code in Locale.preferredLanguages {
            if let lang = AppLanguage(rawValue: String(code.prefix(2))) { return lang }
        }
        return .en
    }
}

/// 한국어 원문을 키로 쓴다. 표에 없으면 원문 그대로 — 빠진 번역이 한국어로 보여 눈에 띈다.
/// ponytail: 코드 안 사전. 번역가에게 넘길 일이 생기면 Localizable.strings 로 옮긴다.
func L(_ ko: String) -> String {
    let lang = AppLanguage.current
    guard lang != .ko, let t = translations[ko] else { return ko }
    return lang == .en ? t.en : t.de
}

/// %ld 자리표시자가 든 문구.
func L(_ ko: String, _ args: CVarArg...) -> String {
    String(format: L(ko), arguments: args)
}

let translations: [String: (en: String, de: String)] = [
    // 첫 실행 안내
    "Flick에 오신 것을 환영합니다": ("Welcome to Flick", "Willkommen bei Flick"),
    "받은 파일을 키 한 번으로 제자리에 보내세요.": ("Send every download where it belongs with a single key.",
                                     "Schicke Downloads mit einem Tastendruck an ihren Platz."),
    "Downloads를 지켜봅니다": ("Watches your Downloads", "Überwacht deine Downloads"),
    "파일을 다 받으면 화면 오른쪽 위에 팝업이 뜹니다.": ("When a download finishes, a popup appears in the top-right corner.",
                                         "Ist ein Download fertig, erscheint oben rechts ein Pop-up."),
    "키 한 번으로 옮기기": ("Move with one key", "Mit einer Taste verschieben"),
    "1–9, 0, a–z 키로 프리셋 폴더에 옮기고, esc로 그대로 둡니다.": ("Press 1–9, 0 or a–z to move it to a preset folder, or esc to leave it.",
                                                   "Mit 1–9, 0 oder a–z in einen Preset-Ordner verschieben, mit esc liegen lassen."),
    "메뉴바에서 관리": ("Manage from the menu bar", "Über die Menüleiste verwalten"),
    "메뉴바 아이콘에서 설정, 프리셋 편집, 되돌리기, 일시정지를 할 수 있습니다.": ("Use the menu bar icon for settings, presets, undo and pausing.",
                                                        "Über das Menüleistensymbol erreichst du Einstellungen, Presets, Widerrufen und Pause."),
    "시작하기": ("Get Started", "Los geht’s"),

    // 기본 프리셋
    "문서": ("Documents", "Dokumente"),
    "이미지": ("Pictures", "Bilder"),
    "바탕화면": ("Desktop", "Schreibtisch"),

    // 설정 창
    "Flick 설정": ("Flick Settings", "Flick-Einstellungen"),
    "일반": ("General", "Allgemein"),
    "프리셋": ("Presets", "Presets"),
    "언어": ("Language", "Sprache"),
    "시작": ("Startup", "Start"),
    "로그인 시 자동 실행": ("Launch at login", "Beim Anmelden starten"),
    "Mac에 로그인하면 Flick이 메뉴바에서 바로 Downloads를 지켜봅니다.": ("Flick starts watching Downloads from the menu bar as soon as you log in.",
                                                    "Flick überwacht Downloads direkt nach dem Anmelden über die Menüleiste."),
    "감시 폴더": ("Watched Folders", "Überwachte Ordner"),
    "Downloads 외에 %ld개까지 추가할 수 있습니다. 하위 폴더는 지켜보지 않습니다.": (
        "Add up to %ld folders besides Downloads. Subfolders aren’t watched.",
        "Neben Downloads bis zu %ld Ordner hinzufügen. Unterordner werden nicht überwacht."),
    "폴더 추가…": ("Add Folder…", "Ordner hinzufügen…"),
    "팝업": ("Popup", "Pop-up"),
    "타이핑 중엔 키보드 가져오지 않기": ("Don’t Take Keyboard While Typing", "Beim Tippen Tastatur nicht übernehmen"),
    "키를 누르던 중에 팝업이 뜨면 입력은 그대로 두고, 팝업을 클릭해야 키로 고를 수 있습니다.": (
        "If you’re typing when the popup appears, your typing continues. Click the popup to use its keys.",
        "Tippst du gerade, wenn das Pop-up erscheint, geht die Eingabe weiter. Klicke das Pop-up an, um seine Tasten zu nutzen."),
    "뜬 직후 누른 키 무시": ("Ignore Keys Right After Popup Appears", "Tasten direkt nach dem Erscheinen ignorieren"),
    "팝업이 키보드를 받은 뒤 0.4초 동안 누른 키와 길게 눌러 반복되는 키로는 옮기지 않습니다.": (
        "Keys pressed within 0.4 seconds of the popup taking the keyboard, and held-down repeats, won’t move files.",
        "Tasten in den ersten 0,4 Sekunden und gehaltene Wiederholungen verschieben keine Dateien."),
    "옮긴 후 파일 열기": ("Open File After Moving", "Datei nach dem Verschieben öffnen"),
    "팝업의 옮긴 후 열기(=)를 켠 상태로 시작합니다.": ("The popup starts with Open After Move (=) turned on.",
                                          "Das Pop-up startet mit aktiviertem „Danach öffnen“ (=)."),
    "팝업 뒤 배경이 유리처럼 비칩니다. 다음 팝업부터 적용됩니다.": ("The background shows through the popup like glass. Applies from the next popup.",
                                              "Der Hintergrund scheint wie durch Glas. Gilt ab dem nächsten Pop-up."),
    "설정 창": ("Settings Window", "Einstellungsfenster"),
    "설정 창 뒤 배경이 유리처럼 비칩니다.": ("The background shows through the settings window like glass.",
                               "Der Hintergrund scheint wie durch Glas durch das Einstellungsfenster."),
    "macOS 26 이상에서 사용 가능": ("Requires macOS 26 or later", "Erfordert macOS 26 oder neuer"),
    "기록": ("History", "Verlauf"),
    "기록 보관 기간": ("Keep History For", "Verlauf aufbewahren"),
    "1주": ("1 Week", "1 Woche"),
    "2주": ("2 Weeks", "2 Wochen"),
    "한 달": ("1 Month", "1 Monat"),
    "영구": ("Forever", "Unbegrenzt"),
    "기간이 지난 기록은 자동으로 지워집니다.": ("Older entries are deleted automatically.", "Ältere Einträge werden automatisch gelöscht."),
    "옮긴 기록이 없습니다": ("No Moves Yet", "Noch nichts verschoben"),
    "팝업에서 파일을 옮기면 여기에 남습니다.": ("Files you move from the popup show up here.",
                                   "Dateien, die du über das Pop-up verschiebst, erscheinen hier."),
    "Finder에서 보기": ("Show in Finder", "Im Finder zeigen"),
    "선택한 %ld개 삭제": ("Delete %ld Selected", "%ld ausgewählte löschen"),
    "전체 삭제": ("Delete All", "Alle löschen"),
    "⌘ 또는 ⇧ 클릭으로 여러 개를 고르고 delete 키로 지웁니다.": ("⌘- or ⇧-click to select several, then press delete.",
                                                "Mit ⌘- oder ⇧-Klick mehrere auswählen, dann Löschtaste drücken."),
    "기록을 모두 지울까요?": ("Delete all history?", "Gesamten Verlauf löschen?"),
    "옮긴 파일은 그대로 남습니다.": ("Moved files stay where they are.", "Verschobene Dateien bleiben, wo sie sind."),
    "나중에 지워졌거나 다른 곳으로 옮겨진 파일입니다": ("This file was deleted or moved afterwards", "Diese Datei wurde danach gelöscht oder verschoben"),
    "정보": ("About", "Info"),
    "버전": ("Version", "Version"),
    "개발자": ("Developer", "Entwickler"),

    // 프리셋 편집
    "Downloads 팝업에서 키 한 번으로 보낼 폴더입니다. 위에서부터 %ld개가 바로 보입니다.": (
        "Folders you can send downloads to with one key. The first %ld are shown right away.",
        "Ordner, in die du Downloads mit einer Taste schickst. Die ersten %ld sind sofort sichtbar."),
    "프리셋이 없습니다": ("No Presets", "Keine Presets"),
    "추가 버튼으로 자주 쓰는 폴더를 등록하세요.": ("Use Add to register folders you use often.",
                                   "Füge mit „Hinzufügen“ häufig genutzte Ordner hinzu."),
    "새 폴더": ("New Folder", "Neuer Ordner"),
    "추가": ("Add", "Hinzufügen"),
    "가져오기…": ("Import…", "Importieren…"),
    "내보내기…": ("Export…", "Exportieren…"),
    "가져오기 · 내보내기": ("Import · Export", "Importieren · Exportieren"),
    "내보내지 못했습니다": ("Couldn’t Export Presets", "Presets konnten nicht exportiert werden"),
    "프리셋 파일을 읽지 못했습니다": ("Couldn’t Read Preset File", "Preset-Datei konnte nicht gelesen werden"),
    "프리셋 %ld개를 가져올까요?": ("Import %ld Presets?", "%ld Presets importieren?"),
    "추가하면 이미 있는 폴더는 건너뛰고, 지금 쓰는 키와 겹치는 키는 비워 자동 배정합니다. 바꾸면 지금 프리셋이 모두 지워집니다.": (
        "Add skips folders you already have and clears keys already in use so they’re assigned automatically. Replace deletes all current presets.",
        "Hinzufügen überspringt vorhandene Ordner und leert bereits belegte Tasten zur automatischen Vergabe. Ersetzen löscht alle aktuellen Presets."),
    "바꾸기": ("Replace", "Ersetzen"),
    "취소": ("Cancel", "Abbrechen"),
    "순서 변경": ("Reorder", "Neu anordnen"),
    "행을 끌어 순서를 바꿉니다. 이름과 키를 고치려면 순서 변경을 끄세요.": ("Drag rows to reorder. Turn off Reorder to edit names and keys.",
                                                  "Zeilen zum Anordnen ziehen. Zum Bearbeiten „Neu anordnen“ ausschalten."),
    "키를 비우면 1–9, 0, a–z 순으로 자동 배정됩니다.": ("Empty keys are assigned automatically: 1–9, 0, then a–z.",
                                        "Leere Tasten werden automatisch vergeben: 1–9, 0, dann a–z."),
    "펼쳐야 보이는 항목": ("Shown when expanded", "Nur ausgeklappt sichtbar"),
    "팝업에서 스페이스를 눌러 펼치면 보입니다": ("Press space in the popup to show these", "Im Pop-up mit der Leertaste einblenden"),
    "아직 없는 폴더입니다. 처음 옮길 때 만들어집니다.": ("This folder doesn’t exist yet. It will be created on the first move.",
                                        "Dieser Ordner existiert noch nicht. Er wird beim ersten Verschieben erstellt."),
    "이름": ("Name", "Name"),
    "키가 겹칩니다": ("This key is already used", "Diese Taste ist schon vergeben"),
    "숫자 0~9 또는 알파벳 한 글자. 비우면 흐린 글자의 키가 자동 배정됩니다": ("A digit 0–9 or a letter. Leave empty to use the dimmed key.",
                                                     "Eine Ziffer 0–9 oder ein Buchstabe. Leer lassen für die grau angezeigte Taste."),
    "폴더 바꾸기": ("Change Folder", "Ordner ändern"),
    "삭제": ("Delete", "Löschen"),

    // 팝업
    "다른 위치…": ("Other Location…", "Anderer Ort…"),
    "그대로 두기": ("Leave It", "Liegen lassen"),
    "접기": ("Collapse", "Einklappen"),
    "%ld개 더 보기": ("%ld More", "%ld weitere"),
    "여기로 옮기기": ("Move Here", "Hierher verschieben"),
    "이름 바꾸기": ("Rename", "Umbenennen"),
    "대기 중 %ld개": ("%ld Waiting", "%ld wartend"),
    "일괄 옮기기": ("Move All", "Alle verschieben"),
    "위로": ("Back", "Zurück"),
    "⇧를 누른 채 고르면 하위 폴더로 들어갑니다": ("Hold ⇧ while choosing to open its subfolders", "Mit ⇧ auswählen, um Unterordner zu öffnen"),
    "클릭하면 키로 고를 수 있습니다": ("Click to choose with keys", "Klicken, um per Taste zu wählen"),
    "옮긴 후 열기": ("Open After Move", "Danach öffnen"),
    "옮긴 뒤 이 파일을 기본 앱으로 엽니다.": ("Opens this file in its default app after moving.",
                                 "Öffnet diese Datei nach dem Verschieben mit der Standard-App."),
    "외 %ld개": ("and %ld more", "und %ld weitere"),
    "폴더를 고르면 대기 중인 파일도 같은 곳으로 옮깁니다. 바꾼 이름은 이 파일에만 적용됩니다.": (
        "Waiting files go to the same folder. A new name applies to this file only.",
        "Wartende Dateien landen im selben Ordner. Ein neuer Name gilt nur für diese Datei."),

    // 알림
    "로그인 시 자동 실행을 바꾸지 못했습니다": ("Couldn’t change Launch at Login", "„Beim Anmelden starten“ konnte nicht geändert werden"),
    "옮기지 못했습니다": ("Couldn’t Move File", "Datei konnte nicht verschoben werden"),
    "파일은 원래 폴더에 그대로 있습니다.": ("The file is still in its original folder.", "Die Datei liegt weiterhin im ursprünglichen Ordner."),
    "이름을 바꾸지 못했습니다": ("Couldn’t Rename File", "Datei konnte nicht umbenannt werden"),
    "되돌리지 못했습니다": ("Couldn’t Undo", "Widerrufen fehlgeschlagen"),

    // 메뉴바
    "최근 옮긴 파일": ("Recently Moved", "Zuletzt verschoben"),
    "마지막 이동 되돌리기": ("Undo Last Move", "Letztes Verschieben widerrufen"),
    "마지막 이동 %ld개 되돌리기": ("Undo Last Move (%ld Files)", "Letztes Verschieben widerrufen (%ld Dateien)"),
    "감시 일시정지": ("Pause Watching", "Überwachung pausieren"),
    "설정…": ("Settings…", "Einstellungen…"),
    "프리셋 편집…": ("Edit Presets…", "Presets bearbeiten…"),
    "Downloads 열기": ("Open Downloads", "Downloads öffnen"),
    "Flick 정보": ("About Flick", "Über Flick"),
    "Flick 종료": ("Quit Flick", "Flick beenden"),
    "Flick %@ 업데이트 다운로드…": ("Download Flick %@ Update…", "Flick-%@-Update laden…"),

    // 업데이트
    "Flick %@ 업데이트가 있습니다": ("Flick %@ Is Available", "Flick %@ ist verfügbar"),
    "다운로드": ("Download", "Laden"),
    "나중에": ("Later", "Später"),
]
