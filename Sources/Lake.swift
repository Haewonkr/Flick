import AppKit
import DynamicLakeKit
import Foundation

/// 노치 표시와 입력. 팝업과 같은 파일을 같은 순간에 보여 주고,
/// 노치에서 고르면 팝업에서 고른 것과 같은 경로로 처리한다.
///
/// Flick 은 전부 메인 스레드에서 돈다(FSEvents 도 main 큐). 여기도 같은 전제라 격리를 따로 두지 않는다.
final class Lake {
    static let shared = Lake()

    /// 지금 노치가 보여 주는 프리셋. 확장은 인덱스만 돌려보낸다.
    private var presets: [Preset] = []
    private var active = false
    /// 결과를 보여 준 뒤 스스로 닫는 타이머. 다음 파일이 오면 취소한다.
    private var closeTimer: Timer?
    /// Coordinator 가 채운다. nil 프리셋은 그대로 두기.
    var onPick: ((Preset?) -> Void)?
    var onUndo: (() -> Void)?

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: FlickLake.actionNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.handle(note.object as? String)
        }
    }

    private func handle(_ action: String?) {
        guard let action else { return }
        switch action {
        case FlickLake.keepAction:
            onPick?(nil)
        case FlickLake.undoAction:
            onUndo?()
        default:
            guard let raw = action.split(separator: ":").last, let index = Int(raw),
                  presets.indices.contains(index) else { return }
            onPick?(presets[index])
        }
    }

    /// 팝업이 뜨는 파일을 노치에도 올린다.
    func show(file: URL, subtitle: String, presets: [Preset], queued: Int) {
        closeTimer?.invalidate()
        closeTimer = nil
        self.presets = presets
        let keys = assignShortcuts(presets)
        let state = FlickLakeState(
            filename: file.lastPathComponent,
            subtitle: subtitle,
            queued: queued,
            tiles: zip(presets, keys).map { .init(key: $0.1 ?? "", name: $0.0.name) })
        post(state, title: file.lastPathComponent)
    }

    /// 옮기거나 실패한 결과를 잠깐 보여 준다.
    func finish(_ status: String, success: Bool) {
        guard active else { return }
        post(FlickLakeState(status: status, success: success), title: status)
        DynamicLakeActivityCenter.showSneakPeek(
            extensionBundleIdentifier: FlickLake.extensionBundleIdentifier)
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        guard active else { return }
        active = false
        presets = []
        closeTimer?.invalidate()
        closeTimer = nil
        DynamicLakeActivityCenter.closeActivity(
            extensionBundleIdentifier: FlickLake.extensionBundleIdentifier)
    }

    private func post(_ state: FlickLakeState, title: String) {
        do {
            if active {
                try DynamicLakeActivityCenter.updateActivityState(
                    extensionBundleIdentifier: FlickLake.extensionBundleIdentifier, state: state)
            } else {
                try DynamicLakeActivityCenter.setActivityActive(
                    true,
                    extensionBundleIdentifier: FlickLake.extensionBundleIdentifier,
                    title: title,
                    priority: .high,        // 받은 파일은 사용자가 바로 처리해야 한다
                    supportsSneakPeek: true,
                    size: .normal,
                    state: state)
                active = true
            }
        } catch {
            // 노치가 안 떠도 팝업은 그대로 동작한다 — 조용히 넘기지 말고 남겨만 둔다.
            NSLog("Flick: 노치 상태 전송 실패 — %@", error.localizedDescription)
        }
    }
}
