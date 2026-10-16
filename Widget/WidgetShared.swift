import Foundation

/// 앱이 쓰고 바탕화면 위젯이 읽는 상태. 앱 · 위젯 · 점검이 같이 컴파일한다.
/// 위젯은 샌드박스라 앱의 설정·기록 파일을 못 읽는다. 앱이 App Group 컨테이너에 이 파일 하나를 써 준다.
struct WidgetSnapshot: Codable, Equatable {
    struct Moved: Codable, Equatable {
        var path: String    // 옮긴 파일의 최종 경로. 예전 기록이면 폴더 + 원래 이름으로 짐작한 경로
        var date: Date
    }

    /// 위젯 문구. 앱이 고른 언어로 미리 옮겨 둔다 — 위젯은 앱의 언어 설정을 못 본다.
    /// 기본값은 앱이 한 번도 안 써 줬을 때(설치 직후) 보인다.
    struct Strings: Codable, Equatable {
        var keptTitle = "Flick Inbox"
        var keptDescription = "Files you left from the popup. Click one to bring the popup back and move it."
        var keptEmpty = "Nothing Left Unfiled"
        var more = "+%ld more"
        var movedTitle = "Flick History"
        var movedDescription = "Files moved with Flick. Click one to show it in Finder."
        var movedEmpty = "No Moves Yet"
    }

    var kept: [String] = []     // 그대로 둔 파일 경로, 최근에 둔 것이 앞
    var moved: [Moved] = []     // 최신순
    var locale = "en"           // 상대 시각("3분 전")을 앱과 같은 언어로 쓰려고
    var strings = Strings()
}

extension WidgetSnapshot {
    /// 키 순서를 고정한다 — 앱이 내용이 같으면 안 쓰고 넘어가도록 바이트로 비교한다.
    func encoded() -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)) ?? Data()
    }

    init?(data: Data) {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let s = try? d.decode(Self.self, from: data) else { return nil }
        self = s
    }
}

enum FlickWidget {
    /// 팀 ID 접두어 그룹은 프로비저닝 프로필 없이 쓸 수 있다. 두 .entitlements 파일과 같은 값이어야 한다.
    static let appGroup = "88DH2SR88S.io.github.haewonkr.flick"
    static let keptKind = "FlickKept"
    static let movedKind = "FlickMoved"

    static var snapshotFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget.json")
    }
}

/// 위젯 행을 누르면 여는 주소. 앱이 받아서 처리한다.
enum WidgetLink: Equatable {
    case kept(String)       // 그대로 둔 파일로 팝업을 다시 띄운다
    case reveal(String)     // Finder 에서 보여 준다

    static let scheme = "flick"

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .kept(let path): c.host = "kept"; c.queryItems = [URLQueryItem(name: "path", value: path)]
        case .reveal(let path): c.host = "reveal"; c.queryItems = [URLQueryItem(name: "path", value: path)]
        }
        return c.url!
    }

    /// 절대 경로가 아니면 버린다. & = # 같은 글자는 URLComponents 가 인코딩해 왕복한다.
    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = c.queryItems?.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/") else { return nil }
        switch c.host {
        case "kept": self = .kept(path)
        case "reveal": self = .reveal(path)
        default: return nil
        }
    }
}
