import AppKit
import ServiceManagement
import SwiftUI

func showAlert(_ title: String, _ text: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

var launchAtLogin: Bool {
    get { SMAppService.mainApp.status == .enabled }
    set {
        guard newValue != launchAtLogin else { return }
        do {
            if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            showAlert(L("로그인 시 자동 실행을 바꾸지 못했습니다"), error.localizedDescription)
        }
    }
}

// MARK: - 폴더 감시

final class Watcher {
    private var stream: FSEventStreamRef?
    fileprivate let onPath: (String, _ removed: Bool) -> Void

    init(directories: [String], onPath: @escaping (String, _ removed: Bool) -> Void) {
        self.onPath = onPath
        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, pathsPtr, flagsPtr, _ in
            guard let info,
                  let paths = unsafeBitCast(pathsPtr, to: NSArray.self) as? [String] else { return }
            let me = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
            for i in 0..<min(count, paths.count) {
                let flags = flagsPtr[i]
                guard flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 else { continue }
                me.onPath(paths[i], flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0)
            }
        }
        stream = FSEventStreamCreate(nil, callback, &ctx,
                                     directories as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     0.3,
                                     UInt32(kFSEventStreamCreateFlagFileEvents
                                            | kFSEventStreamCreateFlagNoDefer
                                            | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    /// 콜백이 self 를 unretained 로 쥐고 있어, 사라지기 전에 스트림을 반드시 멈춘다.
    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

// MARK: - 팝업 UI

/// 팝업·프리셋 창의 폴더 아이콘 색. 앱 아이콘의 하늘색 그라데이션과 맞췄다.
let iceBlue = Color(red: 0.58, green: 0.81, blue: 0.93)

/// 단축키를 키보드 자판처럼 보여주는 작은 배지.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))
            .fixedSize()
    }
}

struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Tile(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct Tile<Label: View>: View {
        let label: Label
        let pressed: Bool
        @State private var hovering = false

        var body: some View {
            label
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(pressed ? 0.16 : hovering ? 0.10 : 0.05)))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
        }
    }
}

/// 네 모서리를 같은 반경으로. 안쪽 타일(8) + 여백(16)에 맞춘 동심원 반경.
let popupShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

/// glass 팝업 둘레의 투명 여백. 화면 가장자리까지 거리는 그만큼 줄여 위치를 맞춘다.
let glassMargin: CGFloat = 12

/// 설정 > 일반의 "Liquid Glass". 저장된 설정값 그대로.
var popupLiquidGlass: Bool {
    get { UserDefaults.standard.bool(forKey: "popupLiquidGlass") }
    set { UserDefaults.standard.set(newValue, forKey: "popupLiquidGlass") }
}

/// 설정 > 일반의 "옮긴 후 열기" 기본값. 팝업마다 이 값으로 시작하고, = 로 그 파일만 바꾼다.
let openAfterMoveKey = "openAfterMove"
var openAfterMoveDefault: Bool { UserDefaults.standard.bool(forKey: openAfterMoveKey) }

/// 설정이 켜져 있고 시스템이 지원할 때만 참. 그리기·그림자·위치가 모두 이 값 하나를 본다.
var glassActive: Bool {
    if #available(macOS 26, *) { return popupLiquidGlass }
    return false
}

extension View {
    @ViewBuilder
    func popupBackground(glass: Bool) -> some View {
        if #available(macOS 26, *), glass {
            // .regular 는 뿌옇게 막혀 유리 느낌이 약하다. 투명한 .clear 를 쓰고,
            // 뒤 배경에 글자가 묻히지 않게 창 배경색을 옅게 한 겹 깐다(0.2 는 묻히고 0.45 가 읽힌다).
            // glass 는 자기 그림자를 창 밖까지 그린다. 창 경계에 잘리면 사각형 자국이 남아 여백을 둔다.
            background(Color(nsColor: .windowBackgroundColor).opacity(0.45), in: popupShape)
                .glassEffect(.clear, in: popupShape).padding(glassMargin)
        } else {
            // 반투명 머티리얼은 macOS 26 에서 glass 와 거의 구분이 안 돼, 끈 상태는 뒤가 비치지 않게 칠한다.
            background(Color(nsColor: .windowBackgroundColor), in: popupShape)
                .overlay(popupShape.strokeBorder(Color.primary.opacity(0.1)))
                .clipShape(popupShape)
        }
    }
}

/// 팝업 뒤에서 기다리는 파일들. 팝업이 떠 있는 동안 새로 들어와도 목록이 바로 갱신된다.
final class FileQueue: ObservableObject {
    @Published var files: [URL] = []
}

/// 설정 > 일반 > 팝업의 두 가지 타이핑 보호. 둘 다 기본으로 켜져 있다.
let typingGuardKey = "popupTypingGuard"
let keyGraceKey = "popupKeyGrace"
var typingGuard: Bool { UserDefaults.standard.object(forKey: typingGuardKey) as? Bool ?? true }
var keyGrace: Bool { UserDefaults.standard.object(forKey: keyGraceKey) as? Bool ?? true }

/// 마지막 키 입력 후 이만큼 안 지났으면 타이핑 중으로 본다. 권한 없이 시스템 전체 입력 시각을 읽는다.
var isTyping: Bool {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1.5
}

/// 테두리 없는 패널은 기본으로 키 창이 못 된다 — 그러면 단축키가 안 먹는다.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    private var keySince = Date.distantPast
    override func becomeKey() {
        super.becomeKey()
        keySince = Date()
    }

    /// 키보드를 받은 직후 0.4초와 길게 눌러 반복되는 키는 버린다 — 치던 손이 그대로 들어와 파일을 옮기지 않게.
    /// 이름 입력칸에서는 반복(지우기 연타 등)을 살린다.
    private func swallow(_ event: NSEvent) -> Bool {
        guard keyGrace, event.type == .keyDown, !(firstResponder is NSText) else { return false }
        return event.isARepeat || Date().timeIntervalSince(keySince) < 0.4
    }

    /// ⇧+키·⌫ 처럼 SwiftUI 단축키로는 믿고 못 받는 키. 처리했으면 true.
    /// (⇧1 은 "!" 로 와서 "1" 단축키와 안 맞고, 같은 글자 단축키가 둘이면 엉뚱한 쪽이 눌린다.)
    var onNavigate: ((NSEvent) -> Bool)?
    private weak var navigated: NSEvent?   // 두 경로로 같은 이벤트가 와도 한 번만

    private func navigate(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !(firstResponder is NSText) else { return false }
        if event === navigated { return true }
        guard onNavigate?(event) == true else { return false }
        navigated = event
        return true
    }

    // 수식키 없는 SwiftUI 단축키는 performKeyEquivalent 로, 나머지는 sendEvent 로 온다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        swallow(event) || navigate(event) || super.performKeyEquivalent(with: event)
    }
    override func sendEvent(_ event: NSEvent) {
        if !swallow(event) && !navigate(event) { super.sendEvent(event) }
    }
}

/// 팝업이 지금 보여주는 폴더 단계. 맨 위는 프리셋이고, ⇧+키로 하위 폴더에 들어가 ⌫·esc 로 나온다.
/// 어느 단계든 그냥 키·클릭은 그 폴더로 옮기고, 하위 폴더가 없는 곳은 ⇧+키도 옮긴다.
final class FolderLevel: ObservableObject {
    struct Item { let name: String; let url: URL }

    private let top: [Item]
    private let topKeys: [String?]
    @Published private(set) var trail: [Item] = []
    @Published private(set) var items: [Item] = []
    @Published private(set) var keys: [String?] = []
    /// 하위 폴더가 있는 항목. 타일에 › 를 붙인다.
    @Published private(set) var nested = Set<URL>()
    /// 하위 폴더가 없는 곳에 ⇧+키를 누르면 부른다. 옮기려면 팝업의 이름·일괄·열기 상태가 필요해 PickerView 가 채운다.
    /// PickerView 를 붙잡으므로 팝업을 닫을 때 비운다.
    var onLeaf: ((URL) -> Void)?
    // ponytail: 접힌 동안 11번째부터의 단축키는 안 먹는다. 스페이스로 펼치면 살아난다.
    @Published var expanded = false

    init(presets: [Preset]) {
        top = presets.map { Item(name: $0.name, url: $0.url) }
        topKeys = assignShortcuts(presets)
        load()
    }

    var shownCount: Int { expanded ? items.count : min(items.count, collapsedCount) }

    /// 보이는 항목 중 그 키가 붙은 폴더로 들어간다. 그런 키가 없으면 false.
    func enter(key: String) -> Bool {
        guard let i = keys.prefix(shownCount).firstIndex(of: key) else { return false }
        enter(items[i])
        return true
    }

    func enter(_ item: Item) {
        guard nested.contains(item.url) else { onLeaf?(item.url); return }
        trail.append(item)
        load()
    }

    /// 맨 위라서 올라갈 곳이 없으면 false.
    func up() -> Bool {
        guard !trail.isEmpty else { return false }
        trail.removeLast()
        load()
        return true
    }

    private func load() {
        if let dir = trail.last?.url {
            items = subfolders(of: dir).map { Item(name: $0.lastPathComponent, url: $0) }
            keys = assignShortcuts(items.map { Preset(name: $0.name, path: $0.url.path) })
        } else {
            items = top
            keys = topKeys
        }
        // ponytail: 단계마다 타일 수만큼 폴더를 읽는다. 클라우드 폴더에서 멈칫하면 백그라운드로 옮길 것.
        nested = Set(items.map(\.url).filter { !subfolders(of: $0).isEmpty })
        expanded = false
    }
}

struct PickerView: View {
    let file: URL
    let subtitle: String
    @ObservedObject var level: FolderLevel
    @ObservedObject var queue: FileQueue
    // 셋 다 옮기거나 남길 때 쓸 파일 이름을 받는다. 옮기는 둘은 대기열도 함께 옮길지, 옮긴 뒤 열지도 받는다.
    let onMove: (URL, String, Bool, Bool) -> Void
    let onOther: (String, Bool, Bool) -> Void
    let onKeep: (String) -> Void

    /// 확정한 새 이름(확장자 제외). 비어 있으면 원래 이름.
    @State private var stem = ""
    /// 이름을 고치는 중일 때만 non-nil. return 으로 stem 에 확정하고 esc 로 버린다.
    /// 그동안엔 글자 단축키가 입력을 가로채지 않게 전부 끈다.
    @State private var draft: String?
    @FocusState private var nameFocused: Bool
    @State private var batch = false
    @State private var openAfter = openAfterMoveDefault
    /// 타이핑 중이라 키보드를 안 가져온 동안엔 부제 대신 클릭하라는 안내를 보인다.
    @Environment(\.controlActiveState) private var activeState

    private var name: String { renamedFilename(file.lastPathComponent, stem: draft ?? stem) }

    private var hiddenCount: Int { max(0, level.items.count - collapsedCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    if let draft {
                        HStack(spacing: 0) {
                            TextField("", text: Binding(get: { draft }, set: { self.draft = $0 }))
                                .textFieldStyle(.plain)
                                .focused($nameFocused)
                                .onAppear { nameFocused = true }
                                .onSubmit { stem = self.draft ?? stem; self.draft = nil }
                            let ext = file.pathExtension
                            if !ext.isEmpty { Text("." + ext).foregroundStyle(.secondary).fixedSize() }
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button {
                            draft = (name as NSString).deletingPathExtension
                        } label: {
                            HStack(spacing: 4) {
                                Text(name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                                Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(KeyboardShortcut(.return, modifiers: []))
                        .help(L("이름 바꾸기"))
                    }
                    Text(activeState == .inactive ? L("클릭하면 키로 고를 수 있습니다") : subtitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { openAfter.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: openAfter ? "checkmark.square.fill" : "square")
                            .foregroundStyle(openAfter ? Color.accentColor : .secondary)
                        Text(L("옮긴 후 열기"))
                        KeyCap("=")
                    }
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .fixedSize()
                // ponytail: = 가 shift 조합인 자판(독일어 등)에선 안 먹을 수 있다. 그러면 키를 설정으로 뺄 것.
                .keyboardShortcut(draft == nil ? KeyboardShortcut("=", modifiers: []) : nil)
                .help(L("옮긴 뒤 이 파일을 기본 앱으로 엽니다."))
            }
            if !level.trail.isEmpty {
                HStack(spacing: 6) {
                    Button { _ = level.up() } label: {
                        HStack(spacing: 4) { Image(systemName: "chevron.left"); KeyCap("⌫") }
                    }
                    .buttonStyle(.borderless)
                    .help(L("위로"))
                    Text(level.trail.map(\.name).joined(separator: " › "))
                        .lineLimit(1).truncationMode(.head)
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(Array(level.items.prefix(level.shownCount).enumerated()), id: \.offset) { i, item in
                    let key = i < level.keys.count ? level.keys[i] : nil
                    let nested = level.nested.contains(item.url)
                    // 그냥 누르면 이 폴더로 옮기고, ⇧ 를 누른 채 클릭하면 하위 폴더로 들어간다(⇧+키는 KeyPanel 이 받는다).
                    Button {
                        if NSEvent.modifierFlags.contains(.shift) { level.enter(item) } else { onMove(item.url, name, batch, openAfter) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundStyle(iceBlue)
                            Text(item.name).lineLimit(1)
                            Spacer(minLength: 4)
                            if nested { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary) }
                            if let key { KeyCap(key) }
                        }
                    }
                    .buttonStyle(TileButtonStyle())
                    .keyboardShortcut(draft == nil ? key.map { KeyboardShortcut(KeyEquivalent(Character($0)), modifiers: []) } : nil)
                    .help((item.url.path as NSString).abbreviatingWithTildeInPath
                          + (nested ? "\n" + L("⇧를 누른 채 고르면 하위 폴더로 들어갑니다") : ""))
                }
            }
            if !queue.files.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("대기 중 %ld개", queue.files.count)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { batch.toggle() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: batch ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(batch ? Color.accentColor : .secondary)
                                Text(L("일괄 옮기기"))
                                KeyCap("⌘A")
                            }
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(draft == nil ? KeyboardShortcut("a", modifiers: .command) : nil)
                        .help(L("폴더를 고르면 대기 중인 파일도 같은 곳으로 옮깁니다. 바꾼 이름은 이 파일에만 적용됩니다."))
                    }
                    ForEach(queue.files.prefix(3), id: \.self) { url in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        }
                        .foregroundStyle(batch ? HierarchicalShapeStyle.primary : .secondary)
                    }
                    if queue.files.count > 3 {
                        Text(L("외 %ld개", queue.files.count - 3)).foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
            }
            HStack {
                Button(L("다른 위치…")) { onOther(name, batch, openAfter) }
                Spacer()
                // 이름을 고치는 중엔 esc 가 편집만 취소하고, 하위 폴더에 들어가 있으면 한 단계 위로 간다.
                Button { if draft != nil { draft = nil } else if !level.up() { onKeep(name) } } label: {
                    HStack(spacing: 5) { Text(level.trail.isEmpty ? L("그대로 두기") : L("위로")); KeyCap("esc") }
                }
                .keyboardShortcut(.cancelAction)
            }
            // 양옆 버튼 폭이 달라도 진짜 가운데에 오도록 Spacer 대신 overlay
            .overlay {
                if hiddenCount > 0 {
                    Button { level.expanded.toggle() } label: {
                        HStack(spacing: 5) { Text(level.expanded ? L("접기") : L("%ld개 더 보기", hiddenCount)); KeyCap("space") }
                    }
                    .keyboardShortcut(draft == nil ? KeyboardShortcut(.space, modifiers: []) : nil)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 360)
        .popupBackground(glass: glassActive)
        // 클로저가 State 저장소를 읽으므로 누른 순간의 이름·일괄·열기 상태로 옮긴다.
        .onAppear { level.onLeaf = { onMove($0, name, batch, openAfter) } }
    }
}

// MARK: - 조정자

final class Coordinator: NSObject, NSWindowDelegate {
    private var seen = Set<String>()
    private let queue = FileQueue()
    private var panel: NSPanel?
    /// 지금 팝업이 다루는 파일. 닫히는 애니메이션 동안 눌린 키가 같은 파일을 또 옮기지 않게 먼저 비운다.
    private var current: URL?
    private var level: FolderLevel?
    var paused = false
    /// 켜진 감시 폴더. FSEvents 는 하위 폴더까지 알려주므로 바로 아래 파일만 거른다.
    var watchedDirs = Set<String>()
    // ponytail: 메모리에만 둔다, 재실행하면 비워짐. 필요해지면 history.jsonl 에 전체 경로 저장.
    /// 한 번에 옮긴 파일들의 (새 경로, 원래 폴더) 묶음, 최신이 앞. 일괄 옮기기는 한 묶음이라 한 번에 되돌린다.
    private(set) var recent: [[(dest: URL, origin: URL)]] = []
    /// esc 로 그대로 둔 파일 경로. 메뉴바 아이콘에 개수가 뜨고, 옮기거나 지우면 빠진다.
    var kept = UserDefaults.standard.stringArray(forKey: "keptFiles") ?? [] {
        didSet { UserDefaults.standard.set(kept, forKey: "keptFiles"); onKeptChange?() }
    }
    var onKeptChange: (() -> Void)?

    func pruneKept() {
        let alive = kept.filter { FileManager.default.fileExists(atPath: $0) }
        if alive != kept { kept = alive }
    }

    func handle(path: String, removed: Bool) {
        if kept.contains(path) { pruneKept() }   // Finder 에서 옮기거나 지우면 이 경로로 이벤트가 온다
        guard !paused, !removed else { return }
        guard watchedDirs.contains((path as NSString).deletingLastPathComponent) else { return }
        let name = (path as NSString).lastPathComponent
        guard !shouldIgnore(name), !seen.contains(path) else { return }
        seen.insert(path)
        waitUntilStable(URL(fileURLWithPath: path))
    }

    // ponytail: 크기 안정화 0.5s×2 휴리스틱. 대용량 스트리밍 저장에서 오탐 나면
    // kMDItemDownloadedDate 또는 파일 잠금(flock) 확인으로 승급.
    private func waitUntilStable(_ url: URL, attempts: Int = 0) {
        // Safari 는 리네임으로 파일을 넣고, 그 경로에 오는 자격 있는 이벤트는 딱 하나다.
        // 그 한 번의 stat 이 빗나가면 재시도할 이벤트가 없으므로 여기서 한 번 더 본다.
        guard let a = fileSize(url) else {
            guard attempts == 0 else { seen.remove(url.path); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                waitUntilStable(url, attempts: 1)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard let b = fileSize(url) else { seen.remove(url.path); return }
            if a == b {
                queue.files.append(url)
                showNext()
            } else if attempts < 3600 {   // 30분 넘게 커지면 포기
                waitUntilStable(url, attempts: attempts + 1)
            } else {
                seen.remove(url.path)
            }
        }
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    // ponytail: 파일당 팝업 1개, 큐 직렬 처리. 나머지는 팝업의 대기열에 보이고 일괄 옮기기로 한꺼번에 보낸다.
    // 대기열에서 몇 개만 골라 보내는 UI 는 없다 — 필요해지면 행마다 체크박스.
    private func showNext() {
        guard panel == nil, !queue.files.isEmpty else { return }
        let file = queue.files.removeFirst()
        guard let size = fileSize(file) else { seen.remove(file.path); showNext(); return }
        let level = FolderLevel(presets: loadPresets())
        self.level = level
        let host = sourceURL(of: file).flatMap { URL(string: $0)?.host }

        let view = PickerView(
            file: file,
            subtitle: [ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file), host]
                .compactMap { $0 }.joined(separator: " · "),
            level: level,
            queue: queue,
            onMove: { [weak self] in self?.finish(file, into: $0, as: $1, withQueue: $2, open: $3) },
            onOther: { [weak self] name, withQueue, open in
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.canCreateDirectories = true
                openPanel.prompt = L("여기로 옮기기")
                openPanel.directoryURL = level.trail.last?.url ?? file.deletingLastPathComponent()
                NSApp.activate(ignoringOtherApps: true)   // 뒤에 뜨면 워처가 통째로 멈춘 것처럼 보인다
                if openPanel.runModal() == .OK, let dir = openPanel.url {
                    self?.finish(file, into: dir, as: name, withQueue: withQueue, open: open)
                }
            },
            onKeep: { [weak self] in self?.keep(file, as: $0) }
        )

        // 제목 표시줄 있는 창은 위 모서리만 시스템이 깎는다. 테두리 없이 만들고 모양은 뷰가 그린다.
        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear   // 뷰의 둥근 머티리얼 밖은 투명하게
        p.hasShadow = !glassActive   // glass 는 제 그림자를 직접 그린다
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        p.isReleasedWhenClosed = false
        p.onNavigate = { [level] event in
            let mods = event.modifierFlags.intersection([.shift, .control, .option, .command])
            // 물리 키 그대로의 글자로 본다 — ⇧1 이 "!" 가 아니라 "1" 로 읽힌다.
            if mods == .shift, let key = event.characters(byApplyingModifiers: [])?.lowercased() {
                return level.enter(key: key)
            }
            if mods.isEmpty, event.keyCode == 51 { return level.up() }   // ⌫
            return false
        }
        let hosting = NSHostingController(rootView: view)
        p.contentViewController = hosting   // 펼치면 창도 같이 커진다
        panel = p          // windowDidResize 보다 반드시 먼저
        current = file
        // 크기를 지금 확정해야 최종 위치를 알고 거기로 밀어 넣을 수 있다.
        p.setContentSize(hosting.view.fittingSize)
        pinToTopRight(p)
        p.displayIfNeeded()
        p.invalidateShadow()   // 그림자를 둥근 모양 기준으로 다시 계산
        slideIn(p)
    }

    /// 오른쪽에서 살짝 밀려 들어오며 나타난다. 위치만 바뀌므로 windowDidResize 의 재배치와 부딪히지 않는다.
    private func slideIn(_ window: NSWindow) {
        let final = window.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion { window.setFrameOrigin(NSPoint(x: final.minX + 48, y: final.minY)) }
        window.alphaValue = 0
        // 타이핑 중이면 보이기만 하고 키보드는 치던 앱에 남긴다. 팝업을 클릭하면 그때 키보드를 받는다.
        if typingGuard && isTyping { window.orderFrontRegardless() } else { window.makeKeyAndOrderFront(nil) }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.15 : 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)   // 빠르게 들어와 부드럽게 멈춤
            window.animator().setFrame(final, display: true)
            window.animator().alphaValue = 1
        }, completionHandler: {
            window.invalidateShadow()   // Liquid Glass 는 늦게 그려져 첫 그림자가 사각형으로 잡힌다
        })
    }

    /// 들어온 쪽(오른쪽)으로 빠지며 사라진다.
    private func slideOut(_ window: NSWindow, completion: @escaping () -> Void) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var frame = window.frame
        if !reduceMotion { frame.origin.x += 48 }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.12 : 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    /// 우상단 고정. 펼치기로 높이가 변해도 위쪽 모서리가 제자리에 있게 매번 다시 잡는다.
    private func pinToTopRight(_ window: NSWindow) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let margin = 16 - (glassActive ? glassMargin : 0)
        window.setFrameOrigin(NSPoint(x: screen.maxX - window.frame.width - margin,
                                      y: screen.maxY - window.frame.height - margin))
    }

    /// panel 을 보지 않고 알림이 준 창을 쓴다 — panel 이 아직 nil 이면 재배치를 건너뛰어
    /// 창이 0×0 기준 좌표(화면 오른쪽 위 바깥)에 그대로 남는다.
    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        pinToTopRight(w)
        w.invalidateShadow()   // 펼치고 접으면 모양이 바뀐다
    }

    /// withQueue 면 대기 중인 파일도 원래 이름 그대로 같은 폴더로 옮긴다.
    /// open 이면 옮긴 뒤 팝업의 파일만 연다 — 일괄로 함께 옮긴 파일까지 열면 창이 쏟아진다.
    private func finish(_ file: URL, into directory: URL, as name: String, withQueue: Bool, open: Bool) {
        guard file == current else { return }
        var batch = [(file, name)]
        if withQueue {
            batch += queue.files.map { ($0, $0.lastPathComponent) }
            queue.files.removeAll()
        }
        var failures: [String] = []
        var moved: [(dest: URL, origin: URL)] = []
        var toOpen: URL?
        for (file, name) in batch {
            // 기다리는 사이 밖에서 지우거나 옮긴 파일은 조용히 건너뛴다.
            guard FileManager.default.fileExists(atPath: file.path) else { seen.remove(file.path); continue }
            let from = sourceURL(of: file)
            do {
                let dest = try move(file, into: directory, as: name)
                seen.remove(file.path)   // 경로가 비었으니 같은 이름을 또 받으면 새 파일이다
                // 다른 감시 폴더로 옮겼으면 거기서 팝업이 다시 뜨지 않게 (undoLast 와 같은 이유)
                if watchedDirs.contains(directory.path) { seen.insert(dest.path) }
                appendHistory(name: file.lastPathComponent, from: from, dest: dest)
                moved.insert((dest, file.deletingLastPathComponent()), at: 0)
                if open, file == current { toOpen = dest }
            } catch {
                failures.append("\(file.lastPathComponent)\n\(error.localizedDescription)")
            }
        }
        if !moved.isEmpty { recent = Array(([moved] + recent).prefix(5)) }
        if !failures.isEmpty {
            showAlert(L("옮기지 못했습니다"),
                      failures.joined(separator: "\n\n") + "\n\n" + L("파일은 원래 폴더에 그대로 있습니다."))
        }
        close()
        if let toOpen { NSWorkspace.shared.open(toOpen) }
    }

    /// 그대로 두되, 이름을 고쳤으면 그 폴더 안에서 바꾼다.
    private func keep(_ file: URL, as name: String) {
        guard file == current else { return }
        var path = file.path
        if name != file.lastPathComponent {
            do {
                let dest = try move(file, into: file.deletingLastPathComponent(), as: name)
                seen.remove(file.path)
                seen.insert(dest.path)   // 이름만 바뀐 같은 파일로 팝업이 다시 뜨지 않게 (undoLast 와 같은 이유)
                path = dest.path
            } catch {
                showAlert(L("이름을 바꾸지 못했습니다"), "\(file.lastPathComponent)\n\(error.localizedDescription)")
            }
        }
        if !kept.contains(path) { kept.append(path) }
        close()
    }

    /// 밖에서 지우거나 옮긴 파일은 목록에서 뺀다.
    func pruneRecent() {
        recent = recent.map { $0.filter { FileManager.default.fileExists(atPath: $0.dest.path) } }.filter { !$0.isEmpty }
    }

    /// 마지막 묶음을 통째로 원래 폴더로 되돌린다. 실패한 파일만 묶음에 남아 다시 시도할 수 있다.
    func undoLast() {
        pruneRecent()
        guard let group = recent.first else { return }
        var failed: [(dest: URL, origin: URL)] = []
        var messages: [String] = []
        for (dest, origin) in group {
            do {
                let back = try move(dest, into: origin)
                // FSEvents 콜백도 main 큐라 이 삽입이 먼저 끝난다 — 되돌린 파일로 팝업이 다시 뜨지 않는다.
                seen.insert(back.path)
            } catch {
                failed.append((dest, origin))
                messages.append("\(dest.lastPathComponent)\n\(error.localizedDescription)")
            }
        }
        if failed.isEmpty { recent.removeFirst() } else { recent[0] = failed }
        if !messages.isEmpty { showAlert(L("되돌리지 못했습니다"), messages.joined(separator: "\n\n")) }
    }

    private func close() {
        guard let p = panel, current != nil else { return }
        current = nil
        level?.onLeaf = nil
        // 사라지는 동안엔 panel 을 쥐고 있어 다음 팝업이 겹쳐 뜨지 않고 큐에서 기다린다.
        slideOut(p) { [weak self] in
            p.orderOut(nil)   // windowWillClose 를 거치지 않으므로 여기서 직접 정리한다
            self?.panel = nil
            self?.showNext()
        }
    }

    /// 닫기 버튼·⌘W 등 close() 를 안 거치는 경로. 이게 없으면 panel 이 non-nil 로 남아
    /// 이후 팝업이 영영 안 뜬다.
    func windowWillClose(_ notification: Notification) {
        panel = nil
        level?.onLeaf = nil
        DispatchQueue.main.async { [weak self] in self?.showNext() }
    }
}

// MARK: - 앱

/// 그대로 둔 파일이 있으면 화살표를 지우고 그 자리에 개수를 쓴다. 템플릿이라 메뉴바 색을 따른다.
func menuBarIcon(count: Int) -> NSImage? {
    guard let base = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Flick") else { return nil }
    guard count > 0 else { return base }
    let text = (count > 99 ? "99+" : String(count)) as NSString
    let font = NSFont.systemFont(ofSize: text.length == 1 ? 10 : text.length == 2 ? 9 : 7, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let image = NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        let width = text.size(withAttributes: attrs).width
        let baseline: CGFloat = 9   // 상자 안쪽 홈 바로 위
        // 18×17 심볼 기준으로 맞춘 좌표. 위는 숫자 자리, 아래 작은 칸은 홈에 닿는 화살촉.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSRect(x: rect.midX - width / 2 - 1, y: baseline - 0.6, width: width + 2, height: rect.height).fill()
        NSRect(x: rect.midX - 3, y: 6.5, width: 6, height: 3).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        text.draw(at: NSPoint(x: rect.midX - width / 2, y: baseline + font.descender), withAttributes: attrs)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Flick"
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = Coordinator()
    private var watcher: Watcher?
    private var statusItem: NSStatusItem?
    private var watchedDirs: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = loadPresets()   // 없으면 기본 프리셋 파일 생성
        pruneHistory()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        coordinator.onKeptChange = { [weak self] in self?.updateIcon() }
        coordinator.pruneKept()   // 꺼져 있던 동안 치운 파일
        updateIcon()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem?.menu = menu

        updateWatcher()
        // 설정 창에서 감시 폴더를 바꾸면 바로 반영한다. 다른 설정이 바뀔 땐 경로가 같아 그냥 넘어간다.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.updateWatcher() }
        WelcomeWindow.shared.showIfFirstLaunch()

        checkForUpdate()
        Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdate() }
    }

    /// GitHub 최신 릴리즈 태그(v1.2 등)가 지금 버전보다 높으면 메뉴에 띄우고, 버전마다 한 번만 창으로 알린다.
    /// ponytail: 알리기만 하고 설치는 사용자가 dmg 로. 자동 설치가 필요해지면 Sparkle.
    private var update: (version: String, url: URL)?

    private func checkForUpdate() {
        let api = URL(string: "https://api.github.com/repos/Haewonkr/Flick/releases/latest")!
        URLSession.shared.dataTask(with: api) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            guard latest.compare(current, options: .numeric) == .orderedDescending else { return }
            DispatchQueue.main.async { self.announce(latest, page) }
        }.resume()
    }

    private func announce(_ version: String, _ page: URL) {
        update = (version, page)
        let key = "notifiedUpdate"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)
        let alert = NSAlert()
        alert.messageText = L("Flick %@ 업데이트가 있습니다", version)
        alert.addButton(withTitle: L("다운로드"))
        alert.addButton(withTitle: L("나중에"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
    }

    @objc private func openUpdate() {
        if let update { NSWorkspace.shared.open(update.url) }
    }

    private func updateWatcher() {
        let dirs = activeWatchDirectories()
        guard dirs != watchedDirs else { return }
        watchedDirs = dirs
        coordinator.watchedDirs = Set(dirs)
        watcher = nil   // 옛 스트림을 먼저 멈춘다
        guard !dirs.isEmpty else { return }
        watcher = Watcher(directories: dirs) { [coordinator] path, removed in
            coordinator.handle(path: path, removed: removed)
        }
    }

    private func updateIcon() {
        statusItem?.button?.image = menuBarIcon(count: coordinator.kept.count)
    }

    /// 열 때마다 새로 그린다 — 최근 기록·체크 상태가 늘 최신이다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        @discardableResult func add(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            return item
        }

        if let update {
            add(L("Flick %@ 업데이트 다운로드…", update.version), #selector(openUpdate))
            menu.addItem(.separator())
        }
        coordinator.pruneRecent()
        coordinator.pruneKept()   // 감시를 끈 폴더에서 치운 파일은 이벤트가 안 온다
        if !coordinator.recent.isEmpty {
            add(L("최근 옮긴 파일"), nil).isEnabled = false
            for url in coordinator.recent.joined().map(\.dest).prefix(5) {
                let item = add("\(fit(url.lastPathComponent, 220)) → \(fit(url.deletingLastPathComponent().lastPathComponent, 100))",
                               #selector(revealRecent(_:)))
                item.representedObject = url
                item.image = NSWorkspace.shared.icon(forFile: url.path)
                item.image?.size = NSSize(width: 16, height: 16)
                item.indentationLevel = 1
            }
        }
        let lastCount = coordinator.recent.first?.count ?? 0
        add(lastCount > 1 ? L("마지막 이동 %ld개 되돌리기", lastCount) : L("마지막 이동 되돌리기"),
            #selector(undoLast), key: "z").isEnabled = lastCount > 0
        menu.addItem(.separator())
        add(L("감시 일시정지"), #selector(togglePause)).state = coordinator.paused ? .on : .off
        menu.addItem(.separator())
        add(L("설정…"), #selector(openSettings), key: ",")
        add(L("프리셋 편집…"), #selector(editPresets))
        add(L("Downloads 열기"), #selector(openDownloads))
        menu.addItem(.separator())
        add(L("Flick 정보"), #selector(about))
        menu.addItem(withTitle: L("Flick 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// 메뉴 글꼴 기준 폭(pt)을 넘으면 가운데를 … 로 줄인다 — 한글처럼 넓은 글자도 폭이 일정하다.
    private func fit(_ name: String, _ maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        var text = name, keep = name.count
        while (text as NSString).size(withAttributes: attrs).width > maxWidth, keep > 3 {
            keep -= 1   // 앞 2/3, 뒤 1/3 을 남겨 이름 시작과 확장자가 모두 보이게
            text = "\(name.prefix(keep - keep / 3))…\(name.suffix(keep / 3))"
        }
        return text
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func undoLast() { coordinator.undoLast() }

    @objc private func togglePause() {
        coordinator.paused.toggle()
        statusItem?.button?.appearsDisabled = coordinator.paused
    }

    @objc private func openSettings() { SettingsWindow.shared.show(.general) }
    @objc private func editPresets() { SettingsWindow.shared.show(.presets) }
    @objc private func openDownloads() { NSWorkspace.shared.open(downloadsDir) }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
