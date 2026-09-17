import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 설정 창 (일반 / 프리셋 / 기록)

enum SettingsTab: String, CaseIterable {
    case general = "일반"
    case presets = "프리셋"
    case history = "기록"
    var title: String { L(rawValue) }
}

final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: PresetStore
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.current.rawValue

    var body: some View {
        VStack(spacing: 0) {
            PillTabs(selection: $model.tab)
                .padding(.top, 12).padding(.bottom, 10)
                .zIndex(1)   // 스크롤 뷰가 위로 번져 탭을 덮지 않게
            switch model.tab {
            case .general: GeneralSettings()
            case .presets: PresetEditor(store: store)
            case .history: HistoryList()
            }
        }
        .id(language)   // L() 은 관찰 대상이 아니라서, 언어가 바뀌면 통째로 다시 만든다
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)   // 탭을 제목 표시줄 줄에 올린다
    }
}

let settingsGlassKey = "settingsLiquidGlass"

/// 상단 가운데 알약 모양 탭. 고른 탭 밑으로 흰 알약이 미끄러져 간다.
struct PillTabs: View {
    @Binding var selection: SettingsTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 18).padding(.vertical, 5)
                        .background {
                            if selection == tab {
                                Capsule().fill(Color.primary.opacity(0.14))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct GeneralSettings: View {
    @State private var autoLaunch = launchAtLogin
    @AppStorage("popupLiquidGlass") private var glass = false   // main.swift 의 popupLiquidGlass 와 같은 키
    @AppStorage(settingsGlassKey) private var settingsGlass = false
    @AppStorage(AppLanguage.defaultsKey) private var language = AppLanguage.current.rawValue
    @AppStorage(historyRetentionKey) private var retention = historyRetentionDays
    @AppStorage(openAfterMoveKey) private var openAfterMove = false
    @AppStorage(typingGuardKey) private var guardTyping = true
    @AppStorage(keyGraceKey) private var grace = true
    @AppStorage(watchDownloadsKey) private var watchDl = true
    @State private var folders = watchFolders

    private var foldersBinding: Binding<[WatchFolder]> {
        Binding(get: { folders }, set: { folders = $0; watchFolders = $0 })
    }

    var body: some View {
        Form {
            Section(L("언어")) {
                Picker(L("언어"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
            }
            Section(L("시작")) {
                Toggle(isOn: Binding(get: { autoLaunch }, set: {
                    launchAtLogin = $0
                    autoLaunch = launchAtLogin   // 실패하면 스위치가 되돌아간다
                })) {
                    Text(L("로그인 시 자동 실행"))
                    Text(L("Mac에 로그인하면 Flick이 메뉴바에서 바로 Downloads를 지켜봅니다."))
                }
            }
            Section(L("감시 폴더")) {
                HStack {
                    Toggle(isOn: $watchDl) { folderLabel((downloadsDir.path as NSString).abbreviatingWithTildeInPath) }
                    Image(systemName: "minus.circle").hidden()   // 아래 행들과 스위치 줄을 맞춘다
                }
                ForEach(foldersBinding) { $folder in
                    HStack {
                        Toggle(isOn: $folder.enabled) { folderLabel(folder.path) }
                        Button { foldersBinding.wrappedValue.removeAll { $0.id == folder.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(L("삭제"))
                    }
                }
                HStack {
                    Text(L("Downloads 외에 %ld개까지 추가할 수 있습니다. 하위 폴더는 지켜보지 않습니다.", maxWatchFolders))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("폴더 추가…"), action: addFolder)
                        .disabled(folders.count >= maxWatchFolders)
                }
            }
            Section(L("팝업")) {
                Toggle(isOn: $openAfterMove) {
                    Text(L("옮긴 후 파일 열기"))
                    Text(L("팝업의 옮긴 후 열기(=)를 켠 상태로 시작합니다."))
                }
                Toggle(isOn: $guardTyping) {
                    Text(L("타이핑 중엔 키보드 가져오지 않기"))
                    Text(L("키를 누르던 중에 팝업이 뜨면 입력은 그대로 두고, 팝업을 클릭해야 키로 고를 수 있습니다."))
                }
                Toggle(isOn: $grace) {
                    Text(L("뜬 직후 누른 키 무시"))
                    Text(L("팝업이 키보드를 받은 뒤 0.4초 동안 누른 키와 길게 눌러 반복되는 키로는 옮기지 않습니다."))
                }
            }
            Section("Liquid Glass") {
                if #available(macOS 26, *) {
                    Toggle(isOn: $glass) {
                        Text(L("팝업"))
                        Text(L("팝업 뒤 배경이 유리처럼 비칩니다. 다음 팝업부터 적용됩니다."))
                    }
                    Toggle(isOn: $settingsGlass) {
                        Text(L("설정 창"))
                        Text(L("설정 창 뒤 배경이 유리처럼 비칩니다."))
                    }
                } else {
                    LabeledContent("Liquid Glass", value: L("macOS 26 이상에서 사용 가능"))
                }
            }
            Section(L("기록")) {
                Picker(selection: $retention) {
                    Text(L("1주")).tag(7)
                    Text(L("2주")).tag(14)
                    Text(L("한 달")).tag(30)
                    Text(L("영구")).tag(0)
                } label: {
                    Text(L("기록 보관 기간"))
                    Text(L("기간이 지난 기록은 자동으로 지워집니다."))
                }
            }
            Section(L("정보")) {
                LabeledContent(L("버전"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                LabeledContent(L("개발자"), value: "Haewonkr")
                LabeledContent("GitHub") {
                    Link("Haewonkr/Flick", destination: URL(string: "https://github.com/Haewonkr/Flick")!)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // 두 탭 배경을 창 배경으로 맞춘다
        .toggleStyle(.switch)
        .onAppear { autoLaunch = launchAtLogin }   // 시스템 설정에서 바꿨을 수도 있다
    }

    private func folderLabel(_ path: String) -> some View {
        Group {
            Text((path as NSString).lastPathComponent)
            Text(path).lineLimit(1).truncationMode(.middle).help(path)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = (url.path as NSString).abbreviatingWithTildeInPath
        // Downloads 나 이미 있는 폴더를 또 고르면 새로 넣지 않고 켜기만 한다.
        if url.path == downloadsDir.path {
            watchDl = true
        } else if let i = folders.firstIndex(where: { $0.path == path }) {
            foldersBinding.wrappedValue[i].enabled = true
        } else if folders.count < maxWatchFolders {
            foldersBinding.wrappedValue.append(WatchFolder(path: path))
        }
    }
}

// MARK: - 기록

struct HistoryList: View {
    @State private var entries: [HistoryEntry] = []
    @State private var selection = Set<HistoryEntry>()
    @State private var anchor: HistoryEntry?   // ⇧ 클릭 범위의 시작점
    @State private var confirmingDeleteAll = false

    /// List 기본 선택은 행 전체를 시스템 파란색으로 칠해서 쓰지 않고, 클릭을 직접 받는다.
    private func click(_ e: HistoryEntry) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.shift), let a = anchor, let i = entries.firstIndex(of: a), let j = entries.firstIndex(of: e) {
            selection = Set(entries[min(i, j)...max(i, j)])
        } else if mods.contains(.command) {
            if selection.remove(e) == nil { selection.insert(e) }
            anchor = e
        } else {
            selection = [e]
            anchor = e
        }
    }

    private func delete(_ doomed: Set<HistoryEntry>) {
        deleteHistory(doomed)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { entries = pruneHistory() }
        selection.subtract(doomed)
    }

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            HStack(spacing: 14) {
                Button { delete(selection) } label: {
                    Label(L("선택한 %ld개 삭제", selection.count), systemImage: "trash")
                }
                .disabled(selection.isEmpty)
                .keyboardShortcut(.delete, modifiers: [])
                Button(L("전체 삭제")) { confirmingDeleteAll = true }
                    .disabled(entries.isEmpty)
                Spacer()
                Text(L("⌘ 또는 ⇧ 클릭으로 여러 개를 고르고 delete 키로 지웁니다."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
        }
        .confirmationDialog(L("기록을 모두 지울까요?"), isPresented: $confirmingDeleteAll) {
            Button(L("전체 삭제"), role: .destructive) { delete(Set(entries)) }
        } message: {
            Text(L("옮긴 파일은 그대로 남습니다."))
        }
        .onAppear { entries = pruneHistory() }   // 탭을 열 때마다 보관 기간을 적용하고 새로 읽는다
    }

    private var list: some View {
        // List(NSTableView)는 행 transition 을 무시해서, 지우는 행이 옆으로 빠지게 하려고 직접 쌓는다.
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(entries, id: \.self) { e in
                    // 예전 기록엔 최종 경로가 없어 폴더 + 원래 이름으로 짐작한다.
                    let url = URL(fileURLWithPath: e.path ?? (e.dest as NSString).appendingPathComponent(e.name))
                    let exists = FileManager.default.fileExists(atPath: url.path)
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            Text((e.dest as NSString).abbreviatingWithTildeInPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 같은 파일을 여러 번 옮기면 분까지 같을 수 있어 초까지 보인다.
                        Text(e.ts.formatted(.dateTime.month().day().hour().minute().second()
                            .locale(Locale(identifier: AppLanguage.current.rawValue))))
                            .font(.caption).foregroundStyle(.secondary).fixedSize()
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .disabled(!exists)
                        .help(exists ? L("Finder에서 보기") : L("나중에 지워졌거나 다른 곳으로 옮겨진 파일입니다"))
                        // 선택된 줄의 휴지통은 선택 전체를 지운다 (Finder 와 같은 동작).
                        Button { delete(selection.contains(e) ? selection : [e]) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help(L("삭제"))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background {
                        let box = RoundedRectangle(cornerRadius: 10)
                        if selection.contains(e) {
                            box.fill(iceBlue.opacity(0.3)).overlay(box.strokeBorder(iceBlue))
                        } else {
                            box.fill(Color.primary.opacity(0.05))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { click(e) }
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.9))))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
        .overlay {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text(L("옮긴 기록이 없습니다")).font(.headline)
                    Text(L("팝업에서 파일을 옮기면 여기에 남습니다.")).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 프리셋 편집기

final class PresetStore: ObservableObject {
    @Published var items: [Preset] = [] { didSet { savePresets(items) } }
    func reload() { items = loadPresets() }
}

struct PresetEditor: View {
    @ObservedObject var store: PresetStore
    /// 켜면 행 어디를 잡아도 끌 수 있고, 끄면 키·이름을 고칠 수 있다. 둘을 섞으면 텍스트 필드가 드래그를 먹는다.
    @State private var reordering = false

    var body: some View {
        let shortcuts = assignShortcuts(store.items)
        let explicit = store.items.compactMap { normalizedKey($0.key) }
        let duplicated = Set(explicit.filter { k in explicit.filter { $0 == k }.count > 1 })

        VStack(spacing: 0) {
            Text(L("Downloads 팝업에서 키 한 번으로 보낼 폴더입니다. 위에서부터 %ld개가 바로 보입니다.", collapsedCount))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.bottom, 10)

            // 두 모드가 같은 List·같은 행을 써야 토글할 때 레이아웃이 흔들리지 않는다.
            // onMove 가 끄는 동안 놓일 자리에 파란 삽입선을 그려주고, nil 이면 끌기가 꺼진다.
            List {
                ForEach(Array($store.items.enumerated()), id: \.element.id) { i, $preset in
                    row($preset, at: i, auto: shortcuts[i], duplicated: duplicated)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 14, bottom: 3, trailing: 14))
                }
                .onMove(perform: reordering ? { from, to in
                    var items = store.items
                    pinLetterShortcuts(&items)
                    items.move(fromOffsets: from, toOffset: to)
                    store.items = items
                } : nil)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if store.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 36)).foregroundStyle(.tertiary)
                        Text(L("프리셋이 없습니다")).font(.headline)
                        Text(L("추가 버튼으로 자주 쓰는 폴더를 등록하세요.")).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            HStack(spacing: 14) {
                Button {
                    store.items.append(Preset(name: L("새 폴더"), path: "~/Documents"))
                } label: {
                    Label(L("추가"), systemImage: "plus")
                }
                .disabled(reordering)
                Toggle(L("순서 변경"), isOn: Binding(get: { reordering }, set: {
                    reordering = $0
                    NSApp.keyWindow?.makeFirstResponder(nil)   // 입력 중이던 칸에 계속 타이핑되지 않게
                }))
                .toggleStyle(.switch).controlSize(.small)
                Menu {
                    Button(L("가져오기…"), action: importPresets)
                    Button(L("내보내기…"), action: exportPresets).disabled(store.items.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(reordering)
                .help(L("가져오기 · 내보내기"))
                Spacer()
                Text(reordering
                     ? L("행을 끌어 순서를 바꿉니다. 이름과 키를 고치려면 순서 변경을 끄세요.")
                     : L("키를 비우면 1–9, 0, a–z 순으로 자동 배정됩니다."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func row(_ preset: Binding<Preset>, at index: Int, auto: String?, duplicated: Set<String>) -> some View {
        let isDup = normalizedKey(preset.wrappedValue.key).map(duplicated.contains) ?? false
        let exists = FileManager.default.fileExists(atPath: preset.wrappedValue.url.path)
        // 경계선을 행 안에 넣어야 List 에서 한 행으로 취급돼 onMove 인덱스가 어긋나지 않는다.
        VStack(alignment: .leading, spacing: 6) {
            if index == collapsedCount {
                HStack(spacing: 8) {
                    Text(L("펼쳐야 보이는 항목")).font(.caption.weight(.medium)).foregroundStyle(.secondary).fixedSize()
                    Rectangle().fill(.quaternary).frame(height: 1)
                }
                .padding(.top, 8).padding(.horizontal, 4)
                .help(L("팝업에서 스페이스를 눌러 펼치면 보입니다"))
            }
            HStack(spacing: 12) {
                // 순서 변경 중엔 폴더 아이콘 자리에 손잡이를 그린다 — 같은 폭이라 행이 안 흔들린다.
                Image(systemName: reordering ? "line.3.horizontal"
                                  : exists ? "folder.fill" : "folder.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(reordering ? Color.secondary : exists ? iceBlue : Color.orange)
                    .frame(width: 26)
                    .help(reordering || exists ? "" : L("아직 없는 폴더입니다. 처음 옮길 때 만들어집니다."))

                // 순서 변경 중엔 입력칸을 Text 로 바꾸지 않고 클릭만 통과시킨다 — 크기가 그대로라 안 흔들린다.
                VStack(alignment: .leading, spacing: 2) {
                    TextField(L("이름"), text: preset.name)
                        .textFieldStyle(.plain).font(.body.weight(.medium))
                        .allowsHitTesting(!reordering)
                    Text(preset.wrappedValue.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                        .help(preset.wrappedValue.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField(auto ?? "–", text: Binding(
                    get: { preset.wrappedValue.key ?? "" },
                    set: { preset.wrappedValue.key = normalizedKey($0) }))
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isDup ? Color.red : Color.secondary.opacity(0.4)))
                    .foregroundStyle(isDup ? Color.red : Color.primary)
                    .help(isDup ? L("키가 겹칩니다") : L("숫자 0~9 또는 알파벳 한 글자. 비우면 흐린 글자의 키가 자동 배정됩니다"))
                    .allowsHitTesting(!reordering)

                Group {
                    Button { chooseFolder(for: preset) } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .help(L("폴더 바꾸기"))

                    Button {
                        let id = preset.wrappedValue.id
                        store.items.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(L("삭제"))
                }
                .buttonStyle(.borderless)
                .font(.body)
                .foregroundStyle(.secondary)
                .disabled(reordering).allowsHitTesting(!reordering)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        .contentShape(Rectangle())
    }

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Flick Presets.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try encodePresets(store.items).write(to: url, options: .atomic)
        } catch {
            showAlert(L("내보내지 못했습니다"), error.localizedDescription)
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imported: [Preset]
        do {
            imported = try decodePresets(Data(contentsOf: url))
        } catch {
            showAlert(L("프리셋 파일을 읽지 못했습니다"), "\(url.lastPathComponent)\n\(error.localizedDescription)")
            return
        }
        let alert = NSAlert()
        alert.messageText = L("프리셋 %ld개를 가져올까요?", imported.count)
        alert.informativeText = L("추가하면 이미 있는 폴더는 건너뛰고, 지금 쓰는 키와 겹치는 키는 비워 자동 배정합니다. 바꾸면 지금 프리셋이 모두 지워집니다.")
        alert.addButton(withTitle: L("추가"))
        alert.addButton(withTitle: L("바꾸기")).hasDestructiveAction = true
        alert.addButton(withTitle: L("취소"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: store.items = mergePresets(store.items, imported)
        case .alertSecondButtonReturn: store.items = imported
        default: break
        }
    }

    private func chooseFolder(for preset: Binding<Preset>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = preset.wrappedValue.url
        if panel.runModal() == .OK, let url = panel.url {
            preset.wrappedValue.path = (url.path as NSString).abbreviatingWithTildeInPath
            if preset.wrappedValue.name == L("새 폴더") {
                preset.wrappedValue.name = url.lastPathComponent
            }
        }
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private let store = PresetStore()
    private let model = SettingsModel()
    private var window: NSWindow?
    private var hosting: NSView?

    func show(_ tab: SettingsTab) {
        store.reload()   // 파일을 밖에서 고쳤을 수도 있다
        model.tab = tab
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsView(model: model, store: store))
            self.hosting = hosting
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            // 빈 툴바로 제목 표시줄을 높여 신호등 버튼이 탭과 같은 줄 가운데에 오게 한다.
            w.toolbar = NSToolbar()
            w.toolbarStyle = .unified
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.contentView = hosting
            // 뷰가 제목 표시줄까지 덮으므로 fittingSize 대신 창 크기를 직접 준다.
            // 높이는 접힌 팝업에 보이는 10개가 프리셋 탭에서 스크롤 없이 보이는 값.
            w.setContentSize(NSSize(width: 600, height: 668))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            applyGlass()
            // 일반 탭의 스위치를 바꾸면 열린 창에 바로 반영한다.
            NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                   queue: .main) { [weak self] _ in self?.applyGlass() }
        }
        window?.title = L("Flick 설정")   // 창 목록·미션 컨트롤용. 화면에는 탭이 대신 보인다
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// SwiftUI .glassEffect 를 창 배경에 깔면 탭을 바꿀 때 이전 내용이 유리에 잔상으로 남는다.
    /// AppKit 유리 뷰로 내용 전체를 감싸면 내용은 유리 위에 그려져 섞이지 않는다.
    private func applyGlass() {
        guard let w = window, let hosting else { return }
        if #available(macOS 26, *), UserDefaults.standard.bool(forKey: settingsGlassKey) {
            guard !(w.contentView is NSGlassEffectView) else { return }
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.45)   // 팝업과 같은 배합: 글자가 묻히지 않게
            glass.contentView = hosting
            w.isOpaque = false
            w.backgroundColor = .clear
            w.contentView = glass
        } else if w.contentView !== hosting {
            w.contentView = hosting
            w.isOpaque = true
            w.backgroundColor = .windowBackgroundColor
        }
    }
}
