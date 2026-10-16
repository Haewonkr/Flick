import DynamicLakeKit
import SwiftUI

/// 확장이 앱에 버튼 입력을 알린다.
private func send(_ action: String) {
    DistributedNotificationCenter.default().postNotificationName(
        FlickLake.actionNotification, object: action, userInfo: nil, deliverImmediately: true)
}

private func stateColor(_ state: FlickLakeState) -> Color {
    state.status == nil ? .white : (state.success ? .green : .red)
}

/// 노치에 항상 보이는 부분. 받은 파일 아이콘과 대기 개수만.
struct LakeCompactView: View {
    @StateObject private var reader = DynamicLakeActivityStateReader<FlickLakeState>(
        initialState: FlickLakeState())

    var body: some View {
        let state = reader.state ?? FlickLakeState()
        GeometryReader { proxy in
            let geometry = LiveActivityGeometry.currentOnActiveScreen(
                size: .normal,
                totalSize: CGSize(width: max(proxy.size.width, 1), height: max(proxy.size.height, 1)))

            LiveActivitySlotLayout(geometry: geometry) {
                Image(systemName: symbol(state))
                    .font(.system(size: geometry.compactSymbolFontSize, weight: .semibold))
                    .foregroundStyle(stateColor(state))
                    .liveActivityLeftSlotSymbol(
                        in: geometry, visualWidth: geometry.compactSymbolVisualWidth)
            } right: {
                LiveActivityCompactTextSlot(
                    text: state.queued > 0 ? "+\(state.queued)" : "",
                    geometry: geometry,
                    fontSize: geometry.compactProminentTextFontSize,
                    weight: .semibold,
                    foregroundStyle: AnyShapeStyle(.white.opacity(0.85)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func symbol(_ state: FlickLakeState) -> String {
        guard state.status != nil else { return "tray.and.arrow.down.fill" }
        return state.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
}

/// 펼친 화면. 팝업의 프리셋 격자를 노치 폭에 맞춰 한 줄로 편다.
struct LakeSneakPeekView: View {
    @StateObject private var reader = DynamicLakeActivityStateReader<FlickLakeState>(
        initialState: FlickLakeState())

    var body: some View {
        let state = reader.state ?? FlickLakeState()
        VStack(alignment: .leading, spacing: 8) {
            header(state)
            if let status = state.status {
                result(status, state)
            } else {
                tiles(state)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ state: FlickLakeState) -> some View {
        HStack(spacing: 6) {
            Text(state.filename.isEmpty ? "Flick" : state.filename)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            if !state.subtitle.isEmpty {
                Text(state.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if state.queued > 0 {
                Text("+\(state.queued)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
    }

    private func result(_ status: String, _ state: FlickLakeState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: state.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(state.success ? .green : .red)
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
            Spacer(minLength: 4)
            if state.success {
                Button { send(FlickLake.undoAction) } label: {
                    Label("되돌리기", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func tiles(_ state: FlickLakeState) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(state.tiles.enumerated()), id: \.offset) { index, tile in
                    Button { send(FlickLake.pickAction(index)) } label: {
                        Tile(key: tile.key, name: tile.name, destructive: false)
                    }
                    .buttonStyle(.plain)
                }
                Button { send(FlickLake.keepAction) } label: {
                    Tile(key: "esc", name: "그대로 두기", destructive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct Tile: View {
        let key: String
        let name: String
        let destructive: Bool

        var body: some View {
            HStack(spacing: 5) {
                Text(key)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(minWidth: 12)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(destructive ? 0.06 : 0.12)))
        }
    }
}
