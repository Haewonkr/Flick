import SwiftUI
import WidgetKit

/// 바탕화면 위젯 둘. 그리기만 하고, 누르면 flick:// 주소로 앱에 넘긴다. 로직은 전부 Flick.app 에 있다.
@main
struct FlickWidgets: WidgetBundle {
    var body: some Widget {
        KeptWidget()
        MovedWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// 앱이 그룹 컨테이너에 써 둔 상태. 없거나 깨졌으면 빈 상태(영어 문구)로 그린다.
func loadSnapshot() -> WidgetSnapshot {
    FlickWidget.snapshotFile.flatMap { try? Data(contentsOf: $0) }.flatMap(WidgetSnapshot.init(data:)) ?? WidgetSnapshot()
}

/// 앱이 상태 파일을 고칠 때마다 reloadAllTimelines 로 다시 부르므로 스스로는 새로 고치지 않는다(.never).
struct SnapshotProvider: TimelineProvider {
    /// 미리 그려 둘 시점(지금부터 초). 기록 위젯만 상대 시각이 낡지 않게 여러 장 그린다.
    var offsets: [TimeInterval] = [0]

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: loadSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now, snapshot = loadSnapshot()
        let entries = offsets.map { SnapshotEntry(date: now + $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

/// 줄 수는 위젯 크기로 정한다. macOS 27 바탕화면 실제 크기(chronod 로그: medium 344×164, large 344×344)에
/// 여백 16pt 로 그려 맞춘 값이다 — 제목 + 3줄 + "+N개 더" 가 130pt, 8줄이면 290pt.
/// ponytail: 화면마다 크기가 다르면 넘치거나 남는다. 그런 화면이 나오면 ViewThatFits 로 줄 수를 맞출 것.
struct FamilyRows<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let content: (Int) -> Content

    var body: some View { content(family == .systemLarge ? 8 : 3) }
}

struct KeptWidget: Widget {
    var body: some WidgetConfiguration {
        // 갤러리 이름·설명도 앱이 고른 언어로. 앱을 한 번도 안 켰으면 영어.
        let strings = loadSnapshot().strings
        return StaticConfiguration(kind: FlickWidget.keptKind, provider: SnapshotProvider()) { entry in
            FamilyRows { KeptView(snapshot: entry.snapshot, limit: $0) }
        }
        .configurationDisplayName(strings.keptTitle)
        .description(strings.keptDescription)
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MovedWidget: Widget {
    /// "3분 전" 이 맞게 보이도록 다시 그릴 시점. 오래될수록 성기게 — 오차가 지난 시간에 비례한다.
    /// ponytail: 7일 뒤로는 마지막 장에 멈춘다. 그 사이 하나라도 옮기거나 남기면 앱이 새로 그리게 한다.
    static let offsets: [TimeInterval] = [0, 1, 2, 3, 4, 5, 10, 15, 20, 30, 45].map { $0 * 60 }
        + [1, 2, 3, 4, 6, 9, 12, 18, 24, 36, 48, 72, 96, 120, 144, 168].map { $0 * 3600 }

    var body: some WidgetConfiguration {
        let strings = loadSnapshot().strings
        return StaticConfiguration(kind: FlickWidget.movedKind, provider: SnapshotProvider(offsets: Self.offsets)) { entry in
            FamilyRows { MovedView(snapshot: entry.snapshot, now: entry.date, limit: $0) }
        }
        .configurationDisplayName(strings.movedTitle)
        .description(strings.movedDescription)
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
