import SwiftUI
import WebKit

@MainActor
final class RoomPreviewController: ObservableObject {
    @Published private(set) var placedProductIDs: Set<String> = []
    private var pendingProducts = Set<String>()
    private var generation = UUID()
    private weak var webView: WKWebView?
    private var isReady = false
    private var moveEnabled = false
    private var initialLayout: RoomLayoutSnapshot?
    private var scannedRoom: RoomDocument?
    private var initialSnapshot: RoomLayoutSnapshot?

    func attach(_ view: WKWebView, layout: RoomLayoutSnapshot?, moveEnabled: Bool, scannedRoom: RoomDocument? = nil) {
        generation = UUID()
        webView = view
        isReady = false
        pendingProducts.removeAll()
        initialSnapshot = nil
        initialLayout = layout
        self.scannedRoom = scannedRoom
        self.moveEnabled = moveEnabled
    }

    func detach(_ view: WKWebView) {
        guard webView === view else { return }
        webView = nil
        generation = UUID()
        pendingProducts.removeAll()
        isReady = false
        initialSnapshot = nil
    }

    func didLoad(_ view: WKWebView) async throws {
        guard webView === view else { return }
        let token = generation
        if let initialLayout {
            for id in Set(initialLayout.items.map(\.assetId)).filter(FurnitureModelLibrary.supports).sorted() {
                try await registerProduct(id, in: view, generation: token)
            }
            try check(view, token)
            try initialLayout.validate()
            let data = try JSONEncoder().encode(initialLayout)
            let json = String(decoding: data, as: UTF8.self)
            _ = try await view.evaluateJavaScript("window.tuckEditor.loadLayout(\(json))")
        } else if let scannedRoom {
            try scannedRoom.validateForPreview()
            let json = String(decoding: try JSONEncoder().encode(scannedRoom), as: UTF8.self)
            _ = try await view.evaluateJavaScript("window.tuckEditor.loadScannedRoom(\(json))")
        }
        try check(view, token)
        isReady = true
        try await applyMoveMode()
        initialSnapshot = try await snapshot()
    }

    private func check(_ view: WKWebView, _ token: UUID) throws {
        try Task.checkCancellation()
        guard webView === view, generation == token else { throw CancellationError() }
    }

    private func registerProduct(_ id: String, in view: WKWebView, generation token: UUID) async throws {
        let data = try await FurnitureModelLibrary.shared.payload(for: id)
        try check(view, token)
        _ = try await view.callAsyncJavaScript("return await window.tuckProducts.register(JSON.parse(json));",
            arguments: ["json": String(decoding: data, as: UTF8.self)], in: nil, contentWorld: .page)
        try check(view, token)
    }

    /// Keeps the original Try/Remove card; only connects it to the existing room.
    func toggleProduct(_ id: String) async throws -> Bool? {
        guard isReady, let view = webView else { throw RoomLibraryError.previewNotReady }
        guard !pendingProducts.contains(id) else { return nil }
        guard FurnitureModelLibrary.supports(id) else { throw FurniturePlacementError.missingModel(id) }
        let token = generation
        let adding = !placedProductIDs.contains(id)
        pendingProducts.insert(id)
        defer { if generation == token { pendingProducts.remove(id) } }
        if adding { try await registerProduct(id, in: view, generation: token) }
        try check(view, token)
        let result = try await view.callAsyncJavaScript("return JSON.stringify(adding ? window.tuckProducts.add(id) : window.tuckProducts.remove(id));",
            arguments: ["id": id, "adding": adding], in: nil, contentWorld: .page)
        try check(view, token)
        guard let json = result as? String else { throw RoomLibraryError.invalidLayout }
        let layout = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: Data(json.utf8))
        try layout.validate()
        updateProductIDs(layout)
        return adding
    }

    private func updateProductIDs(_ layout: RoomLayoutSnapshot) {
        placedProductIDs = Set(layout.items.map(\.assetId).filter(FurnitureModelLibrary.supports))
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
        updateProductIDs(initialSnapshot)
        moveEnabled = false
        try await applyMoveMode()
    }

    func chatContext(roomID: String, roomName: String) async throws -> RoomChatContext {
        guard isReady, let view = webView else { throw RoomLibraryError.previewNotReady }
        let value = try await view.evaluateJavaScript("JSON.stringify(window.tuckEditor.chatContext())")
        guard webView === view, isReady, let json = value as? String else { throw RoomLibraryError.previewNotReady }
        var context = try JSONDecoder().decode(RoomChatContext.self, from: Data(json.utf8))
        context.roomID = roomID
        context.roomName = roomName
        context.revision = UUID().uuidString
        try context.validate()
        return context
    }

    func snapshot() async throws -> RoomLayoutSnapshot {
        guard isReady, pendingProducts.isEmpty, let webView else { throw RoomLibraryError.previewNotReady }
        let value = try await webView.evaluateJavaScript("JSON.stringify(window.tuckEditor.layout())")
        guard let json = value as? String, let data = json.data(using: .utf8) else {
            throw RoomLibraryError.invalidLayout
        }
        let snapshot = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: data)
        try snapshot.validate()
        updateProductIDs(snapshot)
        return snapshot
    }
}
