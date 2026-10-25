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
                ContentUnavailableView("Could not open the 3D model", systemImage: "cube", description: Text(errorMessage))
            } else {
                ProgressView("Loading 3D model…")
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
                errorMessage = "You can still view the measurements. \(error.localizedDescription)"
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
                Text("Width × height × depth · estimated in local axes")
                    .font(.caption).foregroundStyle(.secondary)
                List {
                    Section("Furniture") {
                        if scan.document.objects.isEmpty { Text("No furniture detected.") }
                        ForEach(scan.document.objects) { item in measurement(item) }
                    }
                    Section("Walls, doors, windows and floors") {
                        ForEach(scan.document.structures) { item in measurement(item) }
                    }
                }
                .listStyle(.plain)
                HStack {
                    ShareLink("Share measurements", item: scan.files.json)
                    if let model = scan.files.model { ShareLink("Share 3D model", item: model) }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Saved room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func measurement(_ item: RoomElement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label ?? item.category).font(.subheadline.weight(.medium))
            Text(item.sizeDescription).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
