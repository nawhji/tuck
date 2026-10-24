import SwiftUI

/// 시트 위 영역. 스캔 전에는 점선 원, 스캔 후에는 저장된 USDZ와 치수 열기 버튼을 보여준다.
struct RoomStageView: View {
    let hasScannedSpace: Bool
    let onScanTap: () -> Void
    var modelURL: URL? = nil
    var onViewScan: (() -> Void)? = nil

    var body: some View {
        if hasScannedSpace {
            VStack(spacing: 8) {
                if let modelURL {
                    SavedRoomPreview(url: modelURL)
                        .frame(width: 296, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                } else {
                    miniaturePlaceholder
                }
                if let onViewScan {
                    Button("View measurements", action: onViewScan)
                        .font(.caption.weight(.medium))
                        .buttonStyle(.bordered)
                }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        Button(action: onScanTap) {
            VStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 46, weight: .ultraLight))
                    .foregroundStyle(Color("GrayScale300"))
                Text("Scan your space to start")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color("GrayScale300"))
            }
            .frame(width: 250, height: 250)
            .overlay {
                Circle()
                    .stroke(Color("GrayScale300"), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 4]))
            }
        }
        .buttonStyle(.plain)
    }

    /// 스캔 결과(room.usdz)를 렌더링할 영역. 3D 미니어처가 연결되기 전까지는 빈 자리 표시.
    private var miniaturePlaceholder: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(.secondarySystemBackground))
            .frame(width: 296, height: 310)
            .overlay {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Scanned space")
    }
}

#Preview("Empty") {
    RoomStageView(hasScannedSpace: false) {}
}

#Preview("Scanned") {
    RoomStageView(hasScannedSpace: true) {}
}
