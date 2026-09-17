import AppKit
import SwiftUI

// MARK: - 첫 실행 안내

struct WelcomeView: View {
    let onEditPresets: () -> Void
    let onStart: () -> Void
    @State private var autoLaunch = launchAtLogin

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
            VStack(spacing: 6) {
                Text(L("Flick에 오신 것을 환영합니다")).font(.title2.bold())
                Text(L("받은 파일을 키 한 번으로 제자리에 보내세요.")).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("arrow.down.doc", L("Downloads를 지켜봅니다"),
                        L("파일을 다 받으면 화면 오른쪽 위에 팝업이 뜹니다."))
                feature("keyboard", L("키 한 번으로 옮기기"),
                        L("1–9, 0, a–z 키로 프리셋 폴더에 옮기고, esc로 그대로 둡니다."))
                feature("tray.and.arrow.down", L("메뉴바에서 관리"),
                        L("메뉴바 아이콘에서 설정, 프리셋 편집, 되돌리기, 일시정지를 할 수 있습니다."))
            }
            Toggle(L("로그인 시 자동 실행"), isOn: Binding(get: { autoLaunch }, set: {
                launchAtLogin = $0
                autoLaunch = launchAtLogin   // 실패하면 스위치가 되돌아간다
            }))
            HStack {
                Button(L("프리셋 편집…"), action: onEditPresets)
                Spacer()
                Button(L("시작하기"), action: onStart).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 24)
        .frame(width: 440)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2).foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

final class WelcomeWindow {
    static let shared = WelcomeWindow()
    private var window: NSWindow?

    /// 닫기 버튼으로 넘겨도 다시 조르지 않는다 — 띄운 순간 본 것으로 친다.
    func showIfFirstLaunch() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let view = WelcomeView(
            onEditPresets: { SettingsWindow.shared.show(.presets) },
            onStart: { [weak self] in
                // 안내를 읽은 직후에 Downloads 접근 권한 요청이 뜨게 한 번 들여다본다.
                _ = try? FileManager.default.contentsOfDirectory(atPath: downloadsDir.path)
                self?.window?.close()
            })
        let hosting = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.isMovableByWindowBackground = true
        w.contentView = hosting
        w.setContentSize(hosting.fittingSize)
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
