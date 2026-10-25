import SwiftUI
import WebKit

@MainActor
final class RoomPreviewController: ObservableObject {
    private weak var webView: WKWebView?
    private var isReady = false
    private var moveEnabled = false
    private var initialLayout: RoomLayoutSnapshot?
    private var scannedRoom: RoomDocument?
    private var initialSnapshot: RoomLayoutSnapshot?

    func attach(_ view: WKWebView, layout: RoomLayoutSnapshot?, moveEnabled: Bool, scannedRoom: RoomDocument? = nil) {
        webView = view
        isReady = false
        initialSnapshot = nil
        initialLayout = layout
        self.scannedRoom = scannedRoom
        self.moveEnabled = moveEnabled
    }

    func detach(_ view: WKWebView) {
        guard webView === view else { return }
        webView = nil
        isReady = false
        initialSnapshot = nil
    }

    func didLoad(_ view: WKWebView) async throws {
        guard webView === view else { return }
        if let initialLayout {
            try initialLayout.validate()
            let data = try JSONEncoder().encode(initialLayout)
            let json = String(decoding: data, as: UTF8.self)
            _ = try await view.evaluateJavaScript("window.tuckEditor.loadLayout(\(json))")
        } else if let scannedRoom {
            try scannedRoom.validateForPreview()
            let json = String(decoding: try JSONEncoder().encode(scannedRoom), as: UTF8.self)
            _ = try await view.evaluateJavaScript("window.tuckEditor.loadScannedRoom(\(json))")
        }
        guard webView === view else { return }
        isReady = true
        try await applyMoveMode()
        initialSnapshot = try await snapshot()
    }

    func setMoveEnabled(_ enabled: Bool) {
        guard moveEnabled != enabled else { return }
        moveEnabled = enabled
        guard isReady else { return }
        Task { try? await applyMoveMode() }
    }

    private func applyMoveMode() async throws {
        guard let webView else { return }
        _ = try await webView.evaluateJavaScript("window.tuckEditor.setFurnitureMoveEnabled(\(moveEnabled ? "true" : "false"))")
    }

    func hasUnsavedChanges() async throws -> Bool {
        guard let initialSnapshot else { throw RoomLibraryError.previewNotReady }
        return try await snapshot().hasPlacementChanges(comparedTo: initialSnapshot)
    }

    func acceptSavedSnapshot(_ snapshot: RoomLayoutSnapshot) {
        initialSnapshot = snapshot
    }

    func discardChanges() async throws {
        guard isReady, let webView, let initialSnapshot else { throw RoomLibraryError.previewNotReady }
        let json = String(decoding: try JSONEncoder().encode(initialSnapshot), as: UTF8.self)
        _ = try await webView.evaluateJavaScript("window.tuckEditor.loadLayout(\(json))")
        moveEnabled = false
        try await applyMoveMode()
    }

    func snapshot() async throws -> RoomLayoutSnapshot {
        guard isReady, let webView else { throw RoomLibraryError.previewNotReady }
        let value = try await webView.evaluateJavaScript("JSON.stringify(window.tuckEditor.layout())")
        guard let json = value as? String, let data = json.data(using: .utf8) else {
            throw RoomLibraryError.invalidLayout
        }
        let snapshot = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
    }
}
