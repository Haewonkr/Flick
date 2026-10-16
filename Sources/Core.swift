import Foundation

// MARK: - Presets

struct Preset: Codable, Identifiable, Equatable {
    var name: String
    var path: String
    var key: String? = nil      // 비우면 남은 번호가 자동 배정된다
    let id = UUID()             // 편집 UI 전용, 파일에는 저장하지 않는다
    private enum CodingKeys: String, CodingKey { case name, path, key }

    var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
}

let supportDir: URL = {
    let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    let dir = base.appendingPathComponent("Flick")
    // 예전 이름(InboxSelector) 시절 프리셋·기록을 한 번 옮겨 온다.
    try? FileManager.default.moveItem(at: base.appendingPathComponent("InboxSelector"), to: dir)
    return dir
}()
let presetsFile = supportDir.appendingPathComponent("presets.json")
let historyFile = supportDir.appendingPathComponent("history.jsonl")

let defaultPresets = [
    Preset(name: L("문서"), path: "~/Documents"),
    Preset(name: L("이미지"), path: "~/Pictures"),
    Preset(name: L("바탕화면"), path: "~/Desktop"),
]

/// 매 팝업마다 호출된다 — 파일을 고치면 다음 팝업에 바로 반영된다.
func loadPresets() -> [Preset] {
    if let data = try? Data(contentsOf: presetsFile), let p = try? decodePresets(data) {
        return p
    }
    savePresets(defaultPresets)
    return defaultPresets
}

// ponytail: 편집 중 키 입력마다 저장한다. 파일이 수백 바이트라 디바운스 안 붙임.
func savePresets(_ presets: [Preset]) {
    try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    try? encodePresets(presets).write(to: presetsFile)
}

/// presets.json 과 내보내기 파일이 같은 형식이다 — presets.json 을 그대로 가져올 수도 있다.
func encodePresets(_ presets: [Preset]) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    return try enc.encode(presets)
}

/// 비어 있으면 잘못된 파일로 본다 — 빈 목록으로 바꾸거나 합칠 일은 없다.
func decodePresets(_ data: Data) throws -> [Preset] {
    let presets = try JSONDecoder().decode([Preset].self, from: data)
    guard !presets.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    return presets
}

/// 가져온 프리셋을 뒤에 붙인다. 이미 있는 폴더는 건너뛰고(기존 이름·키 유지),
/// 기존 프리셋에 지금 배정된 키와 겹치는 키는 비워 자동 배정에 맡긴다.
/// 자동 배정은 풀 앞쪽부터 채우므로, 겹치지 않는 키는 기존 자동 키보다 뒤에 있다 — 기존 단축키는 하나도 안 바뀐다.
func mergePresets(_ existing: [Preset], _ imported: [Preset]) -> [Preset] {
    let used = Set(assignShortcuts(existing).compactMap { $0 })
    var paths = Set(existing.map(\.url.path))
    var merged = existing
    for var preset in imported where paths.insert(preset.url.path).inserted {
        if let key = normalizedKey(preset.key), used.contains(key) { preset.key = nil }
        merged.append(preset)
    }
    return merged
}

/// 팝업에서 ⇧+키로 들어갈 하위 폴더. 숨김·패키지(.app 등)는 빼고 Finder 와 같은 이름순(2주차 < 10주차).
func subfolders(of dir: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
    let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                               options: .skipsHiddenFiles)) ?? []
    return items.filter {
        let v = try? $0.resourceValues(forKeys: Set(keys))
        return v?.isDirectory == true && v?.isPackage != true
    }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

// MARK: - 감시 폴더

let downloadsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

struct WatchFolder: Codable, Equatable, Identifiable {
    var path: String            // ~ 로 줄여 저장한다
    var enabled = true
    var id: String { path }     // 추가할 때 중복을 막으므로 경로가 곧 식별자
}

/// Downloads 말고 더 지켜볼 수 있는 폴더 수.
let maxWatchFolders = 5
let watchDownloadsKey = "watchDownloads"
let watchFoldersKey = "watchFolders"

var watchDownloads: Bool { UserDefaults.standard.object(forKey: watchDownloadsKey) as? Bool ?? true }

var watchFolders: [WatchFolder] {
    get {
        UserDefaults.standard.data(forKey: watchFoldersKey)
            .flatMap { try? JSONDecoder().decode([WatchFolder].self, from: $0) } ?? []
    }
    set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: watchFoldersKey) }
}

/// 지금 켜져 있는 감시 폴더의 절대 경로. 같은 폴더가 겹치면 한 번만.
func activeWatchDirectories(downloads: Bool = watchDownloads, folders: [WatchFolder] = watchFolders) -> [String] {
    let paths = (downloads ? [downloadsDir.path] : [])
        + folders.filter(\.enabled).map { URL(fileURLWithPath: ($0.path as NSString).expandingTildeInPath).path }
    var seen = Set<String>()
    return paths.filter { seen.insert($0).inserted }
}

// MARK: - 단축키 배정

/// 사람이 입력한 문자열에서 쓸 수 있는 키 한 글자만 남긴다. 대문자는 소문자로.
/// 마지막 글자를 택한다 — 편집기에서 "3" 위에 a 를 치면 "3a" 가 넘어오는데,
/// 이때 나중에 친 a 가 이기는 쪽이 덮어쓰기처럼 동작한다.
func normalizedKey(_ raw: String?) -> String? {
    guard let c = raw?.lowercased().last(where: { !$0.isWhitespace }),
          (c.isASCII && c.isNumber) || (c.isASCII && c.isLetter) else { return nil }
    return String(c)
}

/// 자판 윗줄 순서대로 1~9, 0 을 먼저 쓰고 모자라면 a~z. 36개까지 단축키가 붙는다.
let shortcutPool = (1...9).map(String.init) + ["0"] + "abcdefghijklmnopqrstuvwxyz".map(String.init)

/// 팝업이 접힌 상태에서 보여주는 개수(2열 × 5줄). 나머지는 스페이스로 펼쳐야 보인다.
let collapsedCount = 10

/// 명시된 키가 우선. 비어 있는 프리셋은 남은 키를 위에서부터 채운다.
func assignShortcuts(_ presets: [Preset]) -> [String?] {
    let taken = Set(presets.compactMap { normalizedKey($0.key) })
    var pool = shortcutPool.filter { !taken.contains($0) }
    return presets.map { p in
        if let k = normalizedKey(p.key) { return k }
        return pool.isEmpty ? nil : pool.removeFirst()
    }
}

/// 순서를 바꾸기 직전에 부른다. 자동 배정된 알파벳을 명시 키로 굳혀서
/// 행을 끌어도 알파벳이 옆 행으로 밀리지 않게 한다.
/// 숫자 1~9, 0 은 위에서부터 다시 매겨지는 편이 자연스러워 그대로 둔다.
func pinLetterShortcuts(_ presets: inout [Preset]) {
    for (i, key) in zip(presets.indices, assignShortcuts(presets)) {
        guard let key, key.first?.isLetter == true else { continue }
        presets[i].key = key
    }
}

// MARK: - 완료 판정

let partialExtensions: Set<String> = ["crdownload", "download", "opdownload", "part", "partial", "tmp"]

/// 아직 받는 중이거나 애초에 관심 없는 파일.
func shouldIgnore(_ filename: String) -> Bool {
    if filename.hasPrefix(".") { return true }
    return partialExtensions.contains((filename as NSString).pathExtension.lowercased())
}

// MARK: - 이동

/// 목적지에 같은 이름이 있으면 `name (2).ext` … 로 비켜간다. 절대 덮어쓰지 않는다.
func uniqueDestination(directory: URL, filename: String, exists: (URL) -> Bool) -> URL {
    let base = (filename as NSString).deletingPathExtension
    let ext = (filename as NSString).pathExtension
    var candidate = directory.appendingPathComponent(filename)
    var n = 2
    while exists(candidate) {
        let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
        candidate = directory.appendingPathComponent(name)
        n += 1
    }
    return candidate
}

/// 팝업에서 고친 이름(확장자 제외)에 원래 확장자를 붙인다. 경로를 벗어나지 못하게 / 는 - 로 바꾸고,
/// 비었거나 . / .. 뿐이면 원래 이름을 쓴다.
func renamedFilename(_ original: String, stem: String) -> String {
    let s = stem.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty, s != ".", s != ".." else { return original }
    let ext = (original as NSString).pathExtension
    return ext.isEmpty ? s : "\(s).\(ext)"
}

@discardableResult
func move(_ file: URL, into directory: URL, as name: String? = nil) throws -> URL {
    let fm = FileManager.default
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let dest = uniqueDestination(directory: directory, filename: name ?? file.lastPathComponent) {
        fm.fileExists(atPath: $0.path)
    }
    try fm.moveItem(at: file, to: dest)
    return dest
}

// MARK: - 출처 URL (v2 학습용)

/// macOS가 다운로드 파일에 붙여주는 xattr에서 원본 URL을 읽는다.
func sourceURL(of file: URL) -> String? {
    let key = "com.apple.metadata:kMDItemWhereFroms"
    let size = getxattr(file.path, key, nil, 0, 0, 0)
    guard size > 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    guard getxattr(file.path, key, &buf, size, 0, 0) == size else { return nil }
    let list = try? PropertyListSerialization.propertyList(from: Data(buf), format: nil) as? [String]
    return (list ?? nil)?.first(where: { !$0.isEmpty })
}

// MARK: - 기록

/// 필드 전체로 같음을 판단한다 — 초 단위 시각 + 경로라 두 줄이 겹칠 일은 사실상 없다.
struct HistoryEntry: Codable, Hashable {
    var ts = Date()
    let name: String      // Downloads 에 들어왔을 때의 이름
    let ext: String
    let from: String      // 출처 URL, 없으면 ""
    let dest: String      // 옮긴 폴더
    var path: String?     // 옮긴 파일의 최종 경로(바꾼 이름·(2) 포함). 예전 기록엔 없다

    /// 예전 기록엔 최종 경로가 없어 폴더 + 원래 이름으로 짐작한다.
    var movedPath: String { path ?? (dest as NSString).appendingPathComponent(name) }
}

/// 설정 일반 탭에서 고르는 보관 기간(일). 0 은 영구, 고른 적 없으면 한 달.
let historyRetentionKey = "historyRetentionDays"
var historyRetentionDays: Int { UserDefaults.standard.object(forKey: historyRetentionKey) as? Int ?? 30 }

private let historyEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return e
}()
private let historyDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

/// 한 줄에 하나씩(JSONL). 못 읽는 줄은 버린다.
func decodeHistory(_ text: String) -> [HistoryEntry] {
    text.split(separator: "\n").compactMap { try? historyDecoder.decode(HistoryEntry.self, from: Data($0.utf8)) }
}

func encodeHistory(_ entries: [HistoryEntry]) -> Data {
    entries.reduce(into: Data()) { out, e in
        guard let line = try? historyEncoder.encode(e) else { return }
        out.append(line)
        out.append(0x0A)
    }
}

/// 보관 기간이 지난 기록을 파일에서 지우고, 남은 기록을 최신순으로 돌려준다.
@discardableResult
func pruneHistory(days: Int = historyRetentionDays, now: Date = Date(), file: URL = historyFile) -> [HistoryEntry] {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    let all = decodeHistory(text)
    let cutoff = now.addingTimeInterval(-Double(days) * 86400)
    let kept = days > 0 ? all.filter { $0.ts >= cutoff } : all
    if kept.count != all.count { try? encodeHistory(kept).write(to: file, options: .atomic) }
    return kept.reversed()
}

/// 파일을 새로 읽어서 지운다 — 설정 창을 연 뒤에 옮긴 기록이 날아가지 않게.
func deleteHistory(_ doomed: Set<HistoryEntry>, file: URL = historyFile) {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
    try? encodeHistory(decodeHistory(text).filter { !doomed.contains($0) }).write(to: file, options: .atomic)
}

func appendHistory(name: String, from: String?, dest: URL) {
    let entry = HistoryEntry(name: name, ext: (name as NSString).pathExtension.lowercased(), from: from ?? "",
                             dest: dest.deletingLastPathComponent().path, path: dest.path)
    let line = encodeHistory([entry])
    if let fh = try? FileHandle(forWritingTo: historyFile) {
        defer { try? fh.close() }
        _ = try? fh.seekToEnd()
        try? fh.write(contentsOf: line)
    } else {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? line.write(to: historyFile)
    }
}

// MARK: - 바탕화면 위젯

/// 위젯이 읽을 상태. kept 는 그대로 둔 순서(오래된 것이 앞), history 는 pruneHistory 처럼 최신순.
/// 기록은 큰 위젯 한 장(8줄)을 채울 만큼만 넘긴다.
func widgetSnapshot(kept: [String], history: [HistoryEntry], limit: Int = 10) -> WidgetSnapshot {
    WidgetSnapshot(
        kept: kept.reversed(),
        moved: history.prefix(limit).map { .init(path: $0.movedPath, date: $0.ts) },
        locale: AppLanguage.current.rawValue,
        // 위젯 제목은 이름처럼 쓰여 언어와 상관없이 영문 고정이다.
        strings: .init(keptTitle: "Flick Inbox",
                       keptDescription: L("팝업에서 그대로 둔 파일입니다. 누르면 팝업이 다시 떠 옮길 수 있습니다."),
                       keptEmpty: L("남은 파일이 없습니다"),
                       more: L("+%ld개 더"),
                       movedTitle: "Flick History",
                       movedDescription: L("Flick으로 옮긴 파일입니다. 누르면 Finder에서 보여 줍니다."),
                       movedEmpty: L("옮긴 기록이 없습니다")))
}

/// 내용이 바뀌었을 때만 쓴다 — 같은 내용으로 위젯을 다시 그리게 하지 않으려고. 썼으면 true.
func writeWidgetSnapshot(_ snapshot: WidgetSnapshot, to file: URL) -> Bool {
    let data = snapshot.encoded()
    guard (try? Data(contentsOf: file)) != data else { return false }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    return (try? data.write(to: file, options: .atomic)) != nil
}
