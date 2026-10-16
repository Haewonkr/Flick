import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// 팝업 폴더 아이콘과 같은 하늘색(앱의 iceBlue). 위젯은 앱 코드를 같이 컴파일하지 않아 따로 둔다.
private let iceBlue = Color(red: 0.58, green: 0.81, blue: 0.93)

/// 그대로 둔 파일. 누르면 그 파일로 팝업이 다시 뜬다.
struct KeptView: View {
    let snapshot: WidgetSnapshot
    let limit: Int

    var body: some View {
        let kept = snapshot.kept
        WidgetFrame(symbol: "tray.and.arrow.down", title: snapshot.strings.keptTitle, count: kept.count) {
            if kept.isEmpty {
                EmptyNote(text: snapshot.strings.keptEmpty)
            } else {
                ForEach(kept.prefix(limit), id: \.self) { path in
                    Link(destination: WidgetLink.kept(path).url) {
                        FileRow(path: path, detail: folderName(path))
                    }
                }
                if kept.count > limit {
                    Text(String(format: snapshot.strings.more, kept.count - limit))
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, FileRow.textInset)
                }
            }
        }
    }
}

/// 옮긴 기록, 최신순. 누르면 옮긴 파일을 Finder 에서 보여 준다.
struct MovedView: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let limit: Int

    var body: some View {
        WidgetFrame(symbol: "clock.arrow.circlepath", title: snapshot.strings.movedTitle, count: nil) {
            if snapshot.moved.isEmpty {
                EmptyNote(text: snapshot.strings.movedEmpty)
            } else {
                // 되돌렸다 다시 옮기면 같은 경로가 두 번 나올 수 있어 순번으로 구분한다.
                ForEach(Array(snapshot.moved.prefix(limit).enumerated()), id: \.offset) { _, m in
                    Link(destination: WidgetLink.reveal(m.path).url) {
                        FileRow(path: m.path, detail: "→ " + folderName(m.path),
                                trailing: relative(m.date, to: now, locale: snapshot.locale))
                    }
                }
            }
        }
    }
}

/// 제목 줄 + 내용. 남는 아래쪽은 비운다.
struct WidgetFrame<Content: View>: View {
    let symbol: String
    let title: String
    let count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(iceBlue)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 { Text("\(count)").foregroundStyle(.secondary) }
            }
            .font(.headline)
            .padding(.bottom, 1)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
    }
}

struct FileRow: View {
    let path: String
    let detail: String
    var trailing: String? = nil

    static let iconSize: CGFloat = 24
    static let spacing: CGFloat = 8
    /// 아이콘 오른쪽, 파일 이름이 시작하는 곳. "+N개 더" 를 여기에 맞춘다.
    static let textInset = iconSize + spacing

    var body: some View {
        HStack(spacing: Self.spacing) {
            Image(nsImage: fileIcon(path)).resizable().frame(width: Self.iconSize, height: Self.iconSize)
            VStack(alignment: .leading, spacing: 0) {
                Text((path as NSString).lastPathComponent)
                    .font(.callout.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.middle)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary).fixedSize() }
        }
        .contentShape(Rectangle())   // 줄 전체를 눌러도 열리게
    }
}

struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 샌드박스라 파일 자체는 못 읽는다. 확장자로 종류 아이콘을 고른다.
private func fileIcon(_ path: String) -> NSImage {
    NSWorkspace.shared.icon(for: UTType(filenameExtension: (path as NSString).pathExtension) ?? .data)
}

private func folderName(_ path: String) -> String {
    ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
}

/// "3분 전" · "어제". 앱이 고른 언어로.
private func relative(_ date: Date, to now: Date, locale: String) -> String {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: locale)
    f.dateTimeStyle = .named
    f.unitsStyle = .short
    return f.localizedString(for: min(date, now), relativeTo: now)
}
