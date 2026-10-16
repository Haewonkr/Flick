import Foundation

@main
struct Checks {
    static func main() throws {
        let dir = URL(fileURLWithPath: "/tmp/flick-checks")
        var existing = Set<String>()
        let ex: (URL) -> Bool = { existing.contains($0.lastPathComponent) }
        func pick(_ name: String) -> String {
            uniqueDestination(directory: dir, filename: name, exists: ex).lastPathComponent
        }

        // 충돌 없음 → 그대로
        assert(pick("a.pdf") == "a.pdf")

        // 한 번 충돌 → (2), 두 번 → (3). 원본은 건드리지 않는다.
        existing.insert("a.pdf")
        assert(pick("a.pdf") == "a (2).pdf")
        existing.insert("a (2).pdf")
        assert(pick("a.pdf") == "a (3).pdf")

        // 확장자 없는 파일
        existing = ["README"]
        assert(pick("README") == "README (2)")

        // 이중 확장자는 마지막 것만 확장자로 본다 (알려진 동작)
        existing = ["archive.tar.gz"]
        assert(pick("archive.tar.gz") == "archive.tar (2).gz")

        // 팝업에서 바꾼 이름: 확장자 유지, / 는 못 쓰고, 비면 원래 이름
        assert(renamedFilename("a.pdf", stem: "보고서") == "보고서.pdf")
        assert(renamedFilename("archive.tar.gz", stem: " new ") == "new.gz")
        assert(renamedFilename("README", stem: "NOTES") == "NOTES")
        assert(renamedFilename("a.pdf", stem: "../x") == "..-x.pdf")
        for bad in ["", "  ", ".", ".."] { assert(renamedFilename("a.pdf", stem: bad) == "a.pdf", bad) }

        // 감시 폴더: Downloads 끄기, 꺼진 폴더 제외, ~ 확장, 겹치면 한 번만
        let home = NSHomeDirectory()
        let wf = [WatchFolder(path: "~/Desktop"), WatchFolder(path: "~/Documents", enabled: false),
                  WatchFolder(path: home + "/Desktop"), WatchFolder(path: "~/Downloads")]
        assert(activeWatchDirectories(downloads: true, folders: wf) == [home + "/Downloads", home + "/Desktop"])
        assert(activeWatchDirectories(downloads: false, folders: wf) == [home + "/Desktop", home + "/Downloads"])
        assert(activeWatchDirectories(downloads: false, folders: []).isEmpty)

        // 받는 중이거나 관심 없는 파일은 무시
        for name in ["x.crdownload", "x.download", "x.part", "x.PARTIAL", "x.tmp", ".DS_Store", ".hidden.pdf"] {
            assert(shouldIgnore(name), "무시했어야 함: \(name)")
        }
        for name in ["x.pdf", "x.zip", "no-extension", "정상 파일.png"] {
            assert(!shouldIgnore(name), "처리했어야 함: \(name)")
        }

        // 프리셋 경로의 ~ 확장
        let p = Preset(name: "t", path: "~/Documents")
        assert(p.url.path == NSHomeDirectory() + "/Documents", p.url.path)
        assert(!p.url.path.contains("~"))

        // 키 정규화: 0~9 또는 a~z 한 글자
        assert(normalizedKey("3") == "3")
        assert(normalizedKey(" 7 ") == "7")
        assert(normalizedKey("12") == "2")          // 나중에 친 글자가 이긴다 (덮어쓰기)
        assert(normalizedKey("3a") == "a")          // 숫자 위에 알파벳을 쳐도 바뀐다
        assert(normalizedKey("a!") == nil)          // 마지막이 못 쓰는 글자면 비운다
        assert(normalizedKey("0") == "0")           // 0도 일반 키 (펼치기는 스페이스)
        assert(normalizedKey("٣") == nil)           // ASCII 가 아닌 숫자는 못 씀
        assert(normalizedKey("a") == "a")
        assert(normalizedKey("K") == "k")           // 대문자는 소문자로
        assert(normalizedKey("문서") == nil)         // 한글은 키로 못 씀
        assert(normalizedKey("") == nil && normalizedKey(nil) == nil)

        // 전부 자동 → 위에서부터 1,2,3
        let auto = [Preset(name: "a", path: "~"), Preset(name: "b", path: "~"), Preset(name: "c", path: "~")]
        assert(assignShortcuts(auto) == ["1", "2", "3"])

        // 명시된 번호가 우선, 나머지는 남은 번호를 채운다
        let mixed = [Preset(name: "a", path: "~"),
                     Preset(name: "b", path: "~", key: "1"),
                     Preset(name: "c", path: "~"),
                     Preset(name: "d", path: "~", key: "9")]
        assert(assignShortcuts(mixed) == ["2", "1", "3", "9"], "\(assignShortcuts(mixed))")

        // 10개째는 0, 11개째부터 알파벳, 37개째부터는 단축키 없음
        let many = (1...38).map { Preset(name: "p\($0)", path: "~") }
        let got = assignShortcuts(many)
        assert(got.prefix(9).elementsEqual((1...9).map(String.init)), "\(got.prefix(9))")
        assert(got[9] == "0", "\(got[9] ?? "-")")
        assert(got[10] == "a" && got[35] == "z", "\(got[10] ?? "-") \(got[35] ?? "-")")
        assert(got[36] == nil && got[37] == nil)

        // 명시된 알파벳 키는 자동 배정 풀에서 빠진다
        let letters = [Preset(name: "a", path: "~", key: "b"), Preset(name: "b", path: "~")]
        assert(assignShortcuts(letters) == ["b", "1"], "\(assignShortcuts(letters))")

        // 순서를 바꿔도 알파벳은 행을 따라가고, 숫자는 위치대로 다시 매겨진다
        var thirteen = (1...13).map { Preset(name: "p\($0)", path: "~") }
        pinLetterShortcuts(&thirteen)
        assert(thirteen.prefix(10).allSatisfy { $0.key == nil }, "숫자(0 포함)는 고정하지 않는다")
        assert(thirteen[10...].map(\.key) == ["a", "b", "c"], "\(thirteen[10...].map(\.key))")
        thirteen.insert(thirteen.remove(at: 12), at: 10)   // c 를 a 앞으로 (SwiftUI onMove 와 같은 결과)
        assert(assignShortcuts(thirteen).suffix(3) == ["c", "a", "b"], "\(assignShortcuts(thirteen).suffix(3))")
        assert(assignShortcuts(thirteen).prefix(10).elementsEqual((1...9).map(String.init) + ["0"]))

        // 가져오기·내보내기: 같은 형식으로 오가고, 비었거나 깨진 파일은 거절
        let roundTrip = try decodePresets(encodePresets(mixed))
        assert(roundTrip.map(\.name) == mixed.map(\.name) && roundTrip.map(\.key) == mixed.map(\.key))
        for bad in ["[]", "not json", #"{"name":"a"}"#] {
            assert((try? decodePresets(Data(bad.utf8))) == nil, bad)
        }

        // 합치기: 같은 폴더는 건너뛰고, 기존에 배정된 키와 겹치는 키는 비운다
        let existingSet = [Preset(name: "a", path: "~/A"), Preset(name: "b", path: "~/B", key: "3"), Preset(name: "c", path: "~/C")]
        assert(assignShortcuts(existingSet) == ["1", "3", "2"])
        let incoming = [Preset(name: "d", path: "~/D", key: "2"),                 // c 의 자동 키와 겹침 → 비움
                        Preset(name: "e", path: "~/E", key: "3"),                 // b 의 키와 겹침 → 비움
                        Preset(name: "f", path: "~/F", key: "4"),                 // 안 겹침 → 유지
                        Preset(name: "a2", path: NSHomeDirectory() + "/A", key: "9"), // ~ 를 풀면 a 와 같은 폴더 → 건너뜀
                        Preset(name: "h", path: "~/H", key: "K")]
        let merged = mergePresets(existingSet, incoming)
        assert(merged.map(\.name) == ["a", "b", "c", "d", "e", "f", "h"], "\(merged.map(\.name))")
        assert(assignShortcuts(merged) == ["1", "3", "2", "5", "6", "4", "k"], "\(assignShortcuts(merged))")

        // 어떤 조합이든 합친 뒤 기존 프리셋의 단축키는 그대로다
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) % n }
        let keyChoices: [String?] = [nil, nil, nil] + ["1", "2", "3", "5", "0", "a", "b"]
        func randomPresets(_ prefix: String) -> [Preset] {
            (0..<rnd(14)).map { Preset(name: "\(prefix)\($0)", path: "~/\(prefix)\(rnd(20))", key: keyChoices[rnd(keyChoices.count)]) }
        }
        for _ in 0..<500 {
            let old = randomPresets("x"), new = randomPresets(rnd(2) == 0 ? "x" : "y")
            let before = assignShortcuts(old)
            let after = assignShortcuts(mergePresets(old, new))
            assert(Array(after.prefix(old.count)) == before, "\(old) + \(new)")
        }

        // 하위 폴더: 폴더만, 숨김·패키지 빼고, Finder 이름순
        let tree = URL(fileURLWithPath: "/tmp/flick-checks-tree")
        try? FileManager.default.removeItem(at: tree)
        for d in ["10주차", "2주차", "1주차", ".숨김", "Tool.app", "2주차/과제"] {
            try FileManager.default.createDirectory(at: tree.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try Data().write(to: tree.appendingPathComponent("파일.txt"))
        assert(subfolders(of: tree).map(\.lastPathComponent) == ["1주차", "2주차", "10주차"], "\(subfolders(of: tree))")
        assert(subfolders(of: tree.appendingPathComponent("1주차")).isEmpty)
        assert(subfolders(of: tree.appendingPathComponent("없는 폴더")).isEmpty)

        // 파일에 id 는 저장되지 않는다
        let json = String(data: try JSONEncoder().encode(auto), encoding: .utf8)!
        assert(!json.contains("id"), json)

        // key 없는 옛 파일도 그대로 읽힌다
        let old = #"[{"name":"문서","path":"~/Documents"}]"#
        let decoded = try JSONDecoder().decode([Preset].self, from: Data(old.utf8))
        assert(decoded.count == 1 && decoded[0].key == nil)

        // 기록: 예전 줄(path 없음)도 읽히고, 다시 써도 같은 줄이 나온다
        let oldLine = #"{"dest":"/d","ext":"pdf","from":"","name":"a.pdf","ts":"2026-09-17T05:06:41Z"}"#
        let entries = decodeHistory(oldLine + "\n깨진 줄\n")
        assert(entries.count == 1 && entries[0].path == nil)
        assert(String(data: encodeHistory(entries), encoding: .utf8) == oldLine + "\n")

        // 보관 기간(0 = 영구)과 골라 지우기. 결과는 최신순.
        let hfile = URL(fileURLWithPath: "/tmp/flick-checks-history.jsonl")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ daysAgo: Double, _ name: String) -> HistoryEntry {
            HistoryEntry(ts: Date(timeIntervalSince1970: now.timeIntervalSince1970 - daysAgo * 86400),
                         name: name, ext: "", from: "", dest: "/d", path: "/d/" + name)
        }
        try encodeHistory([at(40, "old"), at(10, "mid"), at(1, "new")]).write(to: hfile)
        assert(pruneHistory(days: 0, now: now, file: hfile).map(\.name) == ["new", "mid", "old"])
        assert(pruneHistory(days: 30, now: now, file: hfile).map(\.name) == ["new", "mid"])
        deleteHistory([at(10, "mid")], file: hfile)
        assert(pruneHistory(days: 0, now: now, file: hfile).map(\.name) == ["new"])

        // 위젯 상태: 그대로 둔 파일은 최근 것이 앞, 기록은 최신순 그대로 limit 개, 예전 기록은 폴더 + 이름으로 짐작
        let old1 = HistoryEntry(ts: now, name: "옛.pdf", ext: "pdf", from: "", dest: "/d", path: nil)
        assert(old1.movedPath == "/d/옛.pdf")
        let snap = widgetSnapshot(kept: ["/k/first", "/k/second"], history: [at(1, "new"), old1, at(10, "mid")], limit: 2)
        assert(snap.kept == ["/k/second", "/k/first"], "\(snap.kept)")
        assert(snap.moved.map(\.path) == ["/d/new", "/d/옛.pdf"], "\(snap.moved)")
        assert(snap.locale == AppLanguage.current.rawValue && !snap.strings.keptTitle.isEmpty)
        assert(String(format: snap.strings.more, 3).contains("3"))

        // 같은 내용으로 다시 돌아오고, 깨진 파일은 nil
        assert(WidgetSnapshot(data: snap.encoded()) == snap)
        assert(WidgetSnapshot(data: Data("깨진 파일".utf8)) == nil)

        // 내용이 같으면 다시 쓰지 않는다 — 위젯을 괜히 다시 그리지 않게
        let wfile = URL(fileURLWithPath: "/tmp/flick-checks-widget/widget.json")
        try? FileManager.default.removeItem(at: wfile.deletingLastPathComponent())
        assert(writeWidgetSnapshot(snap, to: wfile))          // 폴더가 없어도 만들어 쓴다
        assert(!writeWidgetSnapshot(snap, to: wfile))
        var changed = snap
        changed.kept.removeFirst()
        assert(writeWidgetSnapshot(changed, to: wfile))
        let written = try Data(contentsOf: wfile)
        assert(WidgetSnapshot(data: written) == changed)

        // 위젯 주소: 이상한 글자가 든 경로도 그대로 돌아오고, 엉뚱한 주소는 거른다
        for path in ["/Users/a/Downloads/a&b=c+d #1 ?% 파일 (2).pdf", "/x/y.zip"] {
            assert(WidgetLink(url: WidgetLink.kept(path).url) == .kept(path), path)
            assert(WidgetLink(url: WidgetLink.reveal(path).url) == .reveal(path), path)
        }
        for bad in ["flick://kept?path=relative/x.pdf", "flick://open?path=/x", "flick://kept",
                    "https://kept?path=/x", "flick://reveal?file=/x"] {
            assert(WidgetLink(url: URL(string: bad)!) == nil, bad)
        }

        // 번역: 코드의 L("…") 이 모두 표에 있고, 빈 번역이 없고, %ld 개수가 원문과 같다
        let sources = try FileManager.default.contentsOfDirectory(atPath: "Sources")
            .filter { $0.hasSuffix(".swift") && $0 != "Strings.swift" }
            .map { try String(contentsOfFile: "Sources/" + $0, encoding: .utf8) }
            .joined()
        let used = try NSRegularExpression(pattern: #"L\("([^"]+)""#)
            .matches(in: sources, range: NSRange(sources.startIndex..., in: sources))
            .map { String(sources[Range($0.range(at: 1), in: sources)!]) }
        assert(!used.isEmpty)
        for key in used { assert(translations[key] != nil, "번역 없음: \(key)") }
        for (ko, t) in translations {
            for s in [t.en, t.de] {
                assert(!s.isEmpty, ko)
                assert(s.components(separatedBy: "%ld").count == ko.components(separatedBy: "%ld").count, "\(ko) → \(s)")
            }
        }

        print("모든 점검 통과")
    }
}
