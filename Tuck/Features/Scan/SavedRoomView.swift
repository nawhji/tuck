import SceneKit
import SwiftUI

/// USDZ produced locally by RoomPlan. This does not add furniture placement.
struct SavedRoomPreview: View {
    let url: URL
    @State private var scene: SCNScene?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let scene {
                SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                    .accessibilityLabel("Scanned room. Drag to rotate and pinch to zoom.")
            } else if let errorMessage {
                ContentUnavailableView("3D를 열지 못했어요", systemImage: "cube", description: Text(errorMessage))
            } else {
                ProgressView("3D 불러오는 중…")
            }
        }
        .task(id: url) {
            scene = nil
            errorMessage = nil
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { [url] in
                    let loaded = try SCNScene(url: url)
                    loaded.background.contents = UIColor.secondarySystemBackground
                    let (minimum, maximum) = loaded.rootNode.boundingBox
                    let center = SCNVector3(
                        (minimum.x + maximum.x) / 2,
                        (minimum.y + maximum.y) / 2,
                        (minimum.z + maximum.z) / 2
                    )
                    let span = max(max(maximum.x - minimum.x, maximum.y - minimum.y), max(maximum.z - minimum.z, 1))
                    let camera = SCNNode()
                    camera.camera = SCNCamera()
                    camera.camera?.zNear = 0.01
                    camera.camera?.zFar = Double(span * 20)
                    camera.position = SCNVector3(center.x + span, center.y + span, center.z + span)
                    camera.look(at: center)
                    loaded.rootNode.addChildNode(camera)
                    return loaded
                }.value
                guard !Task.isCancelled else { return }
                scene = loaded
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "치수 목록은 계속 확인할 수 있어요. \(error.localizedDescription)"
            }
        }
    }
}

struct SavedRoomView: View {
    let scan: SavedScan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let model = scan.files.model {
                    SavedRoomPreview(url: model)
                        .frame(height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                if let warning = scan.files.modelWarning {
                    Text(warning).font(.footnote).foregroundStyle(.secondary)
                }
                Text(scan.document.capturedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                Text("가로 × 높이 × 깊이 · 요소의 로컬 축 기준 추정치")
                    .font(.caption).foregroundStyle(.secondary)
                List {
                    Section("가구") {
                        if scan.document.objects.isEmpty { Text("인식된 가구가 없어요.") }
                        ForEach(scan.document.objects) { item in measurement(item) }
                    }
                    Section("벽·문·창문·바닥") {
                        ForEach(scan.document.structures) { item in measurement(item) }
                    }
                }
                .listStyle(.plain)
                HStack {
                    ShareLink("치수 JSON 공유", item: scan.files.json)
                    if let model = scan.files.model { ShareLink("3D 공유", item: model) }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("저장된 방")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }

    private func measurement(_ item: RoomElement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label ?? item.category).font(.subheadline.weight(.medium))
            Text(item.sizeDescription).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
