import Foundation
import Observation

enum SheetDetent {
    case minimized
    case collapsed
    case expanded
}

/// Sheet geometry is shared by drag snapping and viewport expansion.
enum HomeSheetLayout {
    static let minimizedHeight = 28.0
    static func height(_ detent: SheetDetent, availableHeight: Double) -> Double {
        switch detent {
        case .minimized: minimizedHeight
        case .collapsed: max(minimizedHeight, availableHeight * 0.36)
        case .expanded: max(minimizedHeight, availableHeight * 2 / 3)
        }
    }
    static func nearest(projectedHeight: Double, availableHeight: Double) -> SheetDetent {
        [SheetDetent.minimized, .collapsed, .expanded].min {
            abs(height($0, availableHeight: availableHeight) - projectedHeight) < abs(height($1, availableHeight: availableHeight) - projectedHeight)
        } ?? .collapsed
    }
}

/// Stable suggested names derive from saved room numbers, without creating an empty record.
enum RoomNameSequence {
    static func nextName(in names: [String]) -> String {
        let numbers = Set(names.compactMap { name -> Int? in
            let words = name.lowercased().split(whereSeparator: { $0.isWhitespace })
            let suffix: Substring?
            if words.count == 2, words[0] == "room" { suffix = words[1] }
            else if words.count == 3, words[0] == "new", words[1] == "room" { suffix = words[2] }
            else { suffix = nil }
            guard let suffix, let value = Int(suffix), value > 0 else { return nil }
            return value
        })
        let (candidate, overflow) = max(0, numbers.max() ?? 0).addingReportingOverflow(1)
        var next = overflow ? 1 : candidate
        while numbers.contains(next) { next += 1 }
        return "New Room \(next)"
    }
}

/// Home chat and local scanned-room editor state.
@Observable
final class HomeViewModel {
    /// 로그인이 없는 서비스라 사용자 정보는 고정값이다.
    let userName = "Harper"
    let userInitial = "H"

    var hasScannedSpace = false
    var isPresentingScan = false
    var isProfilePresented = false
    var sceneID = UUID()
    var activeLayout: RoomLayoutSnapshot?
    var activeRoomName: String?
    var activeRoomID: String?
    private(set) var newRoomName = "New Room 1"
    var savedScan: SavedScan?
    var scanLoadError: String?
    var isSimulating = false
    var messages: [ChatMessage] = []
    var draft = ""
    var selectedProductID: Product.ID?
    var sheetDetent: SheetDetent = .collapsed
    private(set) var isResponding = false

    var chatStorageError: String?
    private let historyStore: RoomChatStore
    private var lastCheckpoint = Date.distantPast
    private var streamingReplyID: UUID?

    init(historyDirectory: URL? = nil) {
        historyStore = RoomChatStore(directory: historyDirectory)
        do { messages = try historyStore.load("no-room"); rebuildCards() }
        catch { chatStorageError = error.localizedDescription }
    }

    /// Also called when the app becomes inactive; termination callbacks are not required.
    func persistChat() {
        do {
            try historyStore.save(messages, key: conversationKey, streamingID: streamingReplyID)
            lastCheckpoint = Date()
        } catch { chatStorageError = error.localizedDescription }
    }

    private func rebuildCards() {
        for index in messages.indices where messages[index].role == .assistant {
            messages[index].blocks = blocks(from: messages[index].rawText)
        }
    }

    /// Saving a scan/layout under a new room ID carries its conversation along.
    /// Existing destination history is retained, with UUIDs preventing duplicates.
    func persistChat(forSavedRoomID id: String) {
        responseTask?.cancel()
        interruptReply()
        responseID = UUID()
        isResponding = false
        persistChat()
        streamingReplyID = nil
        let key = "saved:" + id
        do {
            var combined = try historyStore.load(key)
            var ids = Set(combined.map(\.id))
            combined += messages.filter { !$0.rawText.isEmpty && ids.insert($0.id).inserted }
            try historyStore.save(combined, key: key)
            conversations[key] = combined
        } catch { chatStorageError = "Room saved, but its chat couldn't be saved: " + error.localizedDescription }
    }

    private let client = ClaudeClient()
    private let catalog = try? ProductCatalog()
    private var roomGeneration = 0
    private var responseTask: Task<Void, Never>?
    private var responseID = UUID()
    private var conversationKey = "no-room"
    private var conversations: [String: [ChatMessage]] = [:]

    private func interruptReply() {
        if let id = streamingReplyID, let index = messages.firstIndex(where: { $0.id == id }),
           !messages[index].rawText.isEmpty {
            messages[index].rawText += "\n\n[This reply was interrupted. Send a follow-up to continue.]"
            messages[index].blocks = blocks(from: messages[index].rawText)
        }
        streamingReplyID = nil
    }

    private func activateConversation(_ key: String) {
        responseTask?.cancel()
        interruptReply()
        responseID = UUID()
        isResponding = false
        if let last = messages.last, last.role == .assistant, last.rawText.isEmpty { messages.removeLast() }
        persistChat()
        streamingReplyID = nil
        conversations[conversationKey] = messages
        conversationKey = key
        if let cached = conversations[key] { messages = cached }
        else {
            do { messages = try historyStore.load(key) }
            catch { messages = []; chatStorageError = error.localizedDescription }
        }
        rebuildCards()
        selectedProductID = nil
        draft = ""
    }

    var roomDisplayName: String { activeRoomName ?? newRoomName }
    var suggestedSaveName: String { activeRoomID == nil ? roomDisplayName : newRoomName }

    func updateRoomNames(_ entries: [RoomLibraryEntry]) {
        newRoomName = RoomNameSequence.nextName(in: entries.map(\.name))
    }

    func needsSaveBeforeSwitch(layoutChanged: Bool) -> Bool {
        hasScannedSpace && layoutChanged
    }
    var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding }

    // MARK: - Actions

    func startScan() {
        guard !isProfilePresented else { return }
        isPresentingScan = true
    }

    func finishScan(_ scan: SavedScan?) {
        isPresentingScan = false
        guard let scan else {
            scanLoadError = "No room was captured. Scan again on a LiDAR device, or open Sample Room in My rooms."
            return
        }
        acceptScan(document: scan.document, files: scan.files)
        sheetDetent = .collapsed
    }

    @MainActor
    func prepareLibrary() async {
        do {
            let entries = try await Task.detached(priority: .userInitiated) {
                try RoomLibraryStore.ensureDemoRoom()
                return try RoomLibraryStore.all()
            }.value
            updateRoomNames(entries)
        } catch { scanLoadError = error.localizedDescription }
    }

    func openSavedRoom(_ entry: RoomLibraryEntry) {
        let key = entry.layout == nil ? entry.scan.map { "scan:" + $0.id } ?? "saved:" + entry.id : "saved:" + entry.id
        activateConversation(key)
        roomGeneration += 1
        sceneID = UUID()
        activeLayout = entry.layout
        savedScan = entry.scan
        activeRoomName = entry.name
        activeRoomID = entry.id
        hasScannedSpace = true
        sheetDetent = .collapsed
        isProfilePresented = false
    }
    func acceptScan(document: RoomDocument, files: ScanFiles) {
        activateConversation("scan:" + document.id)
        roomGeneration += 1
        sceneID = UUID()
        activeLayout = nil
        activeRoomName = newRoomName
        activeRoomID = nil
        savedScan = SavedScan(document: document, files: files)
        hasScannedSpace = true
    }

    @MainActor
    func restoreLatestScan() async {
        let generation = roomGeneration
        do {
            let scan = try await Task.detached(priority: .userInitiated) { try ScanStore.latest() }.value
            guard !Task.isCancelled, generation == roomGeneration, savedScan == nil, let scan else { return }
            acceptScan(document: scan.document, files: scan.files)
        } catch { if generation == roomGeneration { scanLoadError = error.localizedDescription } }
    }
    func removeCurrentRoom() {
        activateConversation("no-room")
        roomGeneration += 1
        hasScannedSpace = false
        sceneID = UUID()
        activeLayout = nil
        activeRoomName = nil
        activeRoomID = nil
        savedScan = nil
        selectedProductID = nil
        isSimulating = false
        scanLoadError = nil
        sheetDetent = .collapsed
    }

    func openProfile() {
        guard !isPresentingScan else { return }
        isProfilePresented = true
    }

    func send(contextProvider: (() async throws -> RoomChatContext)? = nil) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        let generation = roomGeneration
        let requestID = UUID()
        responseID = requestID
        let requiresRoom = hasScannedSpace
        draft = ""
        isResponding = true
        responseTask = Task { [client] in
            defer {
                if responseID == requestID {
                    streamingReplyID = nil
                    persistChat()
                    isResponding = false
                }
            }
            var replyID: ChatMessage.ID?
            do {
                // Fail closed when a room is open but its preview cannot provide current geometry.
                // Never silently send the original scan after the user has moved furniture.
                let context: RoomChatContext?
                if requiresRoom {
                    guard let contextProvider else { throw RoomLibraryError.previewNotReady }
                    context = try await contextProvider()
                    try context?.validate()
                } else { context = nil }
                try Task.checkCancellation()
                guard generation == roomGeneration, responseID == requestID else { return }
                messages.append(ChatMessage(role: .user, text: text))
                persistChat()
                let turns = messages.map { ClaudeClient.Turn(role: $0.role == .user ? "user" : "assistant", text: $0.rawText) }
                let reply = ChatMessage(role: .assistant, text: "")
                replyID = reply.id
                streamingReplyID = reply.id
                messages.append(reply)
                lastCheckpoint = .distantPast
                for try await chunk in client.stream(turns, roomContext: context) {
                    try Task.checkCancellation()
                    guard generation == roomGeneration, responseID == requestID else { return }
                    append(chunk, to: reply.id)
                }
            } catch is CancellationError {
            } catch {
                guard generation == roomGeneration, responseID == requestID else { return }
                if let replyID {
                    append(replyIsEmpty(replyID) ? error.localizedDescription : "\n\n⚠️ \(error.localizedDescription)", to: replyID)
                } else {
                    draft = text
                    scanLoadError = "Couldn't read the current room for chat. Wait for the 3D preview and try again."
                }
            }
        }
    }

    /// 원문을 이어 붙이고 본문·카드 덩어리로 다시 나눈다. 카드는 JSON 블록이 닫힌 뒤에 나타난다.
    private func append(_ text: String, to id: ChatMessage.ID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].rawText += text
        messages[index].blocks = blocks(from: messages[index].rawText)
        if Date().timeIntervalSince(lastCheckpoint) >= 0.5 { persistChat() }
    }

    private func blocks(from raw: String) -> [ChatMessage.Block] {
        ReplyParser.parse(raw).compactMap { segment in
            switch segment {
            case .text(let text):
                return .text(text)
            case .products(let picks):
                // 카탈로그에 없는 id는 버린다.
                let products = catalog.map { catalog in picks.compactMap { Product(pick: $0, catalog: catalog) } } ?? []
                return products.isEmpty ? nil : .products(products)
            }
        }
    }

    private func replyIsEmpty(_ id: ChatMessage.ID) -> Bool {
        messages.first(where: { $0.id == id })?.rawText.isEmpty ?? true
    }

    func attachImage() { /* TODO: 이미지 입력 */ }
    /// 카드를 누르면 선택, 선택된 카드를 다시 누르면 해제. (시뮬레이션 연동은 TODO)
    func toggleSelection(of product: Product) {
        selectedProductID = selectedProductID == product.id ? nil : product.id
    }
}

#if DEBUG
extension HomeViewModel {
    enum PreviewState {
        case empty, scanned, asking, answer, simulation
    }

    static func preview(_ state: PreviewState) -> HomeViewModel {
        let model = HomeViewModel()
        switch state {
        case .empty:
            model.messages = [.sampleUser]
        case .scanned:
            model.hasScannedSpace = true
            model.messages = [.sampleUser]
        case .asking:
            model.hasScannedSpace = true
            model.sheetDetent = .expanded
            model.draft = "I’d like to get a modern carpet besides my bed."
        case .answer:
            model.hasScannedSpace = true
            model.sheetDetent = .expanded
            model.messages = [.sampleAnswer]
            model.selectedProductID = Product.samples[0].id
        case .simulation:
            model.hasScannedSpace = true
            model.isSimulating = true
        }
        return model
    }
}

extension Product {
    static let samples = [
        Product(id: "chair-1", name: "Really Cool Chair", price: "$ 495.15", brand: "IKEA",
                keywords: ["freeshipping", "modern", "walnut", "velvet"], imageURL: nil, sourceURL: URL(string: "https://www.ikea.com")),
        Product(id: "chair-2", name: "Really Cool Chair", price: "$ 495.15", brand: "IKEA",
                keywords: ["freeshipping", "modern"], imageURL: nil, sourceURL: nil),
    ]
}

extension ChatMessage {
    static let sampleUser = ChatMessage(
        role: .user,
        text: "I want to add a knee-height cabinet next to my vanity. I’d prefer something with a modern, minimalist design."
    )
    static let sampleAnswer = ChatMessage(
        role: .assistant,
        text: "",
        blocks: [
            .text("#### Two options\nFor a modern look, the first one is **compact** and *easy to place* next to a vanity."),
            .products([Product.samples[0]]),
            .text("If you want something with more storage, the second one is a better fit."),
            .products([Product.samples[1]]),
        ]
    )
}
#endif
