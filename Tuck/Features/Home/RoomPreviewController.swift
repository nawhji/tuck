import SwiftUI
import WebKit

/// One bridge for the visible room, product cards, movement, and saved rooms.
@MainActor
final class RoomPreviewController: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isRestoring = false
    @Published private(set) var moveEnabled = false
    @Published private(set) var placedProductIDs: Set<String> = []
    @Published private(set) var loadingProductIDs: Set<String> = []
    @Published var errorMessage: String?
    private weak var webView: WKWebView?
    private var generation = UUID()
    private var initialLayout: RoomLayoutSnapshot?
    private var scannedRoom: RoomDocument?
    private var initialSnapshot: RoomLayoutSnapshot?

    func attach(_ view: WKWebView, layout: RoomLayoutSnapshot?, moveEnabled: Bool, scannedRoom: RoomDocument? = nil) {
        webView = view
        generation = UUID()
        initialSnapshot = nil
        initialLayout = layout
        self.scannedRoom = scannedRoom
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.isReady = false; self.isRestoring = false
            self.moveEnabled = moveEnabled
            self.loadingProductIDs.removeAll(); self.placedProductIDs.removeAll()
        }
    }
    func detach(_ view: WKWebView) {
        guard webView === view else { return }
        webView = nil; generation = UUID()
        initialSnapshot = nil
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.isReady = false; self.isRestoring = false; self.loadingProductIDs.removeAll()
        }
    }
    private func check(_ view: WKWebView, _ token: UUID) throws {
        try Task.checkCancellation()
        guard webView === view, generation == token else { throw CancellationError() }
    }
    func didLoad(_ view: WKWebView) async throws {
        guard webView === view else { throw CancellationError() }
        let token = generation
        isRestoring = true
        defer { if generation == token { isRestoring = false; loadingProductIDs.removeAll() } }
        do {
            if let initialLayout {
                try initialLayout.validate()
                let products = Set(initialLayout.items.compactMap {
                    $0.productID ?? (FurnitureCatalog.supports($0.assetId) ? $0.assetId : nil)
                })
                for id in products.sorted() {
                    loadingProductIDs.insert(id)
                    try await register(id, in: view, token: token)
                }
                try check(view, token)
                let json = String(decoding: try JSONEncoder().encode(initialLayout), as: UTF8.self)
                _ = try await view.callAsyncJavaScript("window.tuckEditor.loadLayout(JSON.parse(json)); return true;",
                    arguments: ["json": json], in: nil, contentWorld: .page)
            } else if let scannedRoom {
                try scannedRoom.validateForPreview()
                let json = String(decoding: try JSONEncoder().encode(scannedRoom), as: UTF8.self)
                _ = try await view.callAsyncJavaScript("window.tuckEditor.loadScannedRoom(JSON.parse(json)); return true;",
                    arguments: ["json": json], in: nil, contentWorld: .page)
            }
            try check(view, token)
            try await applyMoveMode(in: view, token: token)
            let current = try await readSnapshot(in: view)
            try check(view, token)
            accept(current)
            initialSnapshot = current
            isReady = true
        } catch is CancellationError { throw CancellationError() }
        catch {
            if generation == token { errorMessage = "Couldn't open this room: \(error.localizedDescription)" }
            throw error
        }
    }
    func setMoveEnabled(_ enabled: Bool) {
        guard moveEnabled != enabled else { return }
        moveEnabled = enabled
        guard isReady, let view = webView else { return }
        let token = generation
        Task {
            do { try await applyMoveMode(in: view, token: token) }
            catch is CancellationError {}
            catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }
    private func applyMoveMode(in view: WKWebView, token: UUID) async throws {
        try check(view, token)
        _ = try await view.callAsyncJavaScript("window.tuckEditor.setFurnitureMoveEnabled(enabled); return true;",
            arguments: ["enabled": moveEnabled], in: nil, contentWorld: .page)
        try check(view, token)
    }
    /// nil means the same product is loading; true means it was newly added.
    @discardableResult
    func toggleProduct(_ product: Product) async throws -> Bool? {
        guard FurnitureCatalog.supports(product.id) else { throw FurnitureError.missingModel(product.id) }
        guard isReady, let view = webView else { throw RoomLibraryError.previewNotReady }
        guard !loadingProductIDs.contains(product.id) else { return nil }
        let token = generation, removing = placedProductIDs.contains(product.id)
        loadingProductIDs.insert(product.id)
        defer { if generation == token { loadingProductIDs.remove(product.id) } }
        if !removing { try await register(product.id, in: view, token: token) }
        try check(view, token)
        let value = try await command(removing ? "removeProduct" : "tryProduct", payload: product.id, in: view)
        try check(view, token)
        let layout = try decode(value)
        guard layout.items.contains(where: { $0.productID == product.id }) != removing else {
            throw FurnitureError.rendererUnavailable
        }
        accept(layout)
        if !removing { moveEnabled = true }
        return !removing
    }
    private func register(_ id: String, in view: WKWebView, token: UUID) async throws {
        let data = try await FurnitureModelLibrary.shared.payload(for: id)
        try check(view, token)
        let json = String(decoding: data, as: UTF8.self)
        _ = try await view.callAsyncJavaScript("return await window.tuckFurniture.register(JSON.parse(json));",
            arguments: ["json": json], in: nil, contentWorld: .page)
        try check(view, token)
    }
    private func command(_ name: String, payload: Any, in view: WKWebView) async throws -> Any {
        try await view.callAsyncJavaScript("return await window.tuckFurniture[command](payload);",
            arguments: ["command": name, "payload": payload], in: nil, contentWorld: .page) ?? NSNull()
    }
    func receive(_ body: Any, from view: WKWebView) {
        guard webView === view, isReady, let event = body as? [String: Any] else { return }
        if event["type"] as? String == "layout", let object = event["layout"] {
            do {
                accept(try decode(object))
                if let enabled = event["furnitureMoveEnabled"] as? Bool { moveEnabled = enabled }
            } catch { errorMessage = error.localizedDescription }
        } else if event["type"] as? String == "error" {
            errorMessage = event["message"] as? String ?? "The room could not display that furniture."
        }
    }
    func resetRoom() {
        guard isReady, loadingProductIDs.isEmpty, let view = webView else { return }
        let token = generation
        Task {
            do {
                let result = try await command("reset", payload: NSNull(), in: view)
                try check(view, token)
                accept(try decode(result))
            } catch is CancellationError {}
            catch { if generation == token { errorMessage = error.localizedDescription } }
        }
    }
    private func decode(_ value: Any) throws -> RoomLayoutSnapshot {
        let layout = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
        try layout.validate()
        return layout
    }
    private func accept(_ layout: RoomLayoutSnapshot) {
        placedProductIDs = Set(layout.items.compactMap { $0.productID })
    }
    private func readSnapshot(in view: WKWebView) async throws -> RoomLayoutSnapshot {
        let value = try await view.evaluateJavaScript("JSON.stringify(window.tuckEditor.layout())")
        guard let json = value as? String, let data = json.data(using: .utf8) else { throw RoomLibraryError.invalidLayout }
        let layout = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: data)
        try layout.validate()
        return layout
    }
    func hasUnsavedChanges() async throws -> Bool {
        guard let initialSnapshot else { throw RoomLibraryError.previewNotReady }
        return try await snapshot().hasPlacementChanges(comparedTo: initialSnapshot)
    }

    func acceptSavedSnapshot(_ snapshot: RoomLayoutSnapshot) { initialSnapshot = snapshot }

    func discardChanges() async throws {
        guard isReady, loadingProductIDs.isEmpty, let view = webView, let initialSnapshot else {
            throw RoomLibraryError.previewNotReady
        }
        let token = generation
        let json = String(decoding: try JSONEncoder().encode(initialSnapshot), as: UTF8.self)
        let result = try await view.callAsyncJavaScript("return window.tuckFurniture.restore(JSON.parse(json));",
            arguments: ["json": json], in: nil, contentWorld: .page)
        try check(view, token)
        accept(try decode(result ?? NSNull()))
        moveEnabled = false
        try await applyMoveMode(in: view, token: token)
    }

    func chatContext(roomID: String, roomName: String) async throws -> RoomChatContext {
        guard isReady, loadingProductIDs.isEmpty, let view = webView else { throw RoomLibraryError.previewNotReady }
        let token = generation
        let value = try await view.evaluateJavaScript("JSON.stringify(window.tuckEditor.chatContext())")
        try check(view, token)
        guard let json = value as? String else { throw RoomLibraryError.previewNotReady }
        var context = try JSONDecoder().decode(RoomChatContext.self, from: Data(json.utf8))
        context.roomID = roomID; context.roomName = roomName; context.revision = UUID().uuidString
        try context.validate()
        return context
    }

    func snapshot() async throws -> RoomLayoutSnapshot {
        guard isReady, loadingProductIDs.isEmpty, let view = webView else { throw RoomLibraryError.previewNotReady }
        let token = generation, result = try await readSnapshot(in: view)
        try check(view, token)
        accept(result)
        return result
    }
}
