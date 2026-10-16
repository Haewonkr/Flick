import Foundation

/// 앱이 확장에 보내는 상태. 앱 타깃과 확장 타깃이 같이 컴파일한다.
struct FlickLakeState: Codable, Hashable {
    struct Tile: Codable, Hashable {
        var key: String     // 팝업과 같은 단축키. 노치에선 라벨로만 쓴다.
        var name: String
    }

    var filename = ""
    var subtitle = ""       // 크기 · 출처
    var queued = 0          // 뒤에 기다리는 파일 수
    var tiles: [Tile] = []
    var status: String?     // 있으면 결과 화면
    var success = false
}

enum FlickLake {
    static let extensionBundleIdentifier = "io.github.haewonkr.flick.lake"

    /// 확장 -> 앱. DynamicLakeKit 은 앱 -> 확장 한 방향만 준다.
    /// 값은 notification 의 object 로 보낸다 — userInfo 는 배달 보장이 약하다.
    static let actionNotification = Notification.Name("io.github.haewonkr.flick.lakeAction")

    static func pickAction(_ index: Int) -> String { "pick:\(index)" }
    static let keepAction = "keep"
    static let undoAction = "undo"
}
