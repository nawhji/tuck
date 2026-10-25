import Foundation

struct RoomLayoutSnapshot: Codable, Sendable, Equatable {
    struct Item: Codable, Sendable, Equatable {
        let instanceId: String
        let assetId: String
        let position: [Double]
        let yawRadians: Double
        var label: String? = nil
        var productID: String? = nil
    }
    let version: Int
    let units: String
    let upAxis: String
    let items: [Item]
    var scannedRoom: RoomDocument? = nil

    func validate() throws {
        guard version == 1, units == "meters", upAxis == "Y", items.count <= 100 else {
            throw RoomLibraryError.invalidLayout
        }
        try scannedRoom?.validateForPreview()
        var ids = Set<String>()
        var products = Set<String>()
        for item in items {
            guard !item.instanceId.isEmpty, item.instanceId.count <= 120,
                  ids.insert(item.instanceId).inserted,
                  !item.assetId.isEmpty, item.assetId.count <= 120,
                  item.position.count == 3, item.position.allSatisfy({ $0.isFinite && abs($0) < 100 }),
                  item.yawRadians.isFinite else { throw RoomLibraryError.invalidLayout }
            if let label = item.label {
                guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.count <= 80 else {
                    throw RoomLibraryError.invalidLayout
                }
            }
            if let productID = item.productID {
                guard FurnitureCatalog.supports(productID), item.assetId == productID,
                      products.insert(productID).inserted else { throw RoomLibraryError.invalidLayout }
            }
        }
    }
}

struct RoomLibraryEntry: Identifiable, Sendable {
    let id: String
    let name: String
    let updatedAt: Date
    let layout: RoomLayoutSnapshot?
    let scan: SavedScan?
}

enum RoomLibraryError: LocalizedError {
    case invalidLayout, invalidName, roomNotFound, unreadable, previewNotReady
    var errorDescription: String? {
        switch self {
        case .invalidLayout: "The room layout couldn't be read. Your room has not been removed."
        case .invalidName: "Enter a room name with 1–60 characters."
        case .roomNotFound: "That saved room is no longer available."
        case .unreadable: "Your saved rooms couldn't be loaded. The original files have been kept."
        case .previewNotReady: "The 3D room is still loading. Try saving again in a moment."
        }
    }
}

/// Named layout snapshots extend the existing scan library without deleting scan measurements.
enum RoomLibraryStore {
    private struct Record: Codable {
        let id: String
        let name: String
        let createdAt: Date
        let updatedAt: Date
        let layout: RoomLayoutSnapshot
    }

    private static func root(_ override: URL?) throws -> URL {
        if let override { return override }
        return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true)
            .appendingPathComponent("RoomLayouts", isDirectory: true)
    }

    private static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 120 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    static func all(scansRoot: URL? = nil, layoutsRoot: URL? = nil) throws -> [RoomLibraryEntry] {
        var entries: [String: RoomLibraryEntry] = [:]
        var scanError: Error?
        do {
            for scan in try ScanStore.all(in: scansRoot) where safeID(scan.id) {
                let name = "Room · " + scan.document.capturedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                entries[scan.id] = RoomLibraryEntry(id: scan.id, name: name,
                    updatedAt: scan.document.capturedAt, layout: nil, scan: scan)
            }
        } catch { scanError = error }
        let folder = try root(layoutsRoot)
        var unreadableFiles = false
        var sourceScanIDs = Set<String>()
        if FileManager.default.fileExists(atPath: folder.path) {
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                      options: .skipsHiddenFiles)
            where file.pathExtension == "json" {
                do {
                    let record = try decoder().decode(Record.self, from: Data(contentsOf: file))
                    guard safeID(record.id), file.deletingPathExtension().lastPathComponent == record.id,
                          !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          record.name.count <= 60 else { throw RoomLibraryError.unreadable }
                    try record.layout.validate()
                    if let sourceID = record.layout.scannedRoom?.id { sourceScanIDs.insert(sourceID) }
                    let scan = record.layout.scannedRoom.flatMap { entries[$0.id]?.scan } ?? entries[record.id]?.scan
                    entries[record.id] = RoomLibraryEntry(id: record.id, name: record.name,
                        updatedAt: record.updatedAt, layout: record.layout, scan: scan)
                } catch { unreadableFiles = true }
            }
        }
        for id in sourceScanIDs where entries[id]?.layout == nil { entries.removeValue(forKey: id) }
        if entries.isEmpty && (scanError != nil || unreadableFiles) { throw RoomLibraryError.unreadable }
        return entries.values.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
    }

    @discardableResult
    static func saveNew(name: String, layout: RoomLayoutSnapshot, layoutsRoot: URL? = nil) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { throw RoomLibraryError.invalidName }
        try layout.validate()
        let id = UUID().uuidString
        try write(Record(id: id, name: name, createdAt: Date(), updatedAt: Date(), layout: layout), to: root(layoutsRoot))
        return id
    }

    static func saveExisting(id: String, layout: RoomLayoutSnapshot,
                             scansRoot: URL? = nil, layoutsRoot: URL? = nil) throws {
        try layout.validate()
        guard safeID(id), let entry = try all(scansRoot: scansRoot, layoutsRoot: layoutsRoot).first(where: { $0.id == id }) else {
            throw RoomLibraryError.roomNotFound
        }
        let folder = try root(layoutsRoot)
        let previous = try? decoder().decode(Record.self, from: Data(contentsOf: folder.appendingPathComponent(id + ".json")))
        try write(Record(id: id, name: entry.name,
                         createdAt: previous?.createdAt ?? entry.scan?.document.capturedAt ?? entry.updatedAt,
                         updatedAt: Date(), layout: layout), to: folder)
    }

    private static let seedLock = NSLock()

    /// Register once. Keep the sample layout and any user edits when updating its default name.
    static func ensureDemoRoom(layoutsRoot: URL? = nil) throws {
        seedLock.lock()
        defer { seedLock.unlock() }
        let folder = try root(layoutsRoot)
        let id = "tuck-demo-room-1"
        let file = folder.appendingPathComponent(id + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            let record = try decoder().decode(Record.self, from: Data(contentsOf: file))
            // Only migrate the original sample's old default name, never user-renamed rooms.
            if record.id == id && record.name == "Room 1" {
                try write(Record(id: record.id, name: "Sample Room", createdAt: record.createdAt,
                                 updatedAt: record.updatedAt, layout: record.layout), to: folder)
            }
            return
        }
        let json = #"{"version":1,"units":"meters","upAxis":"Y","items":[{"instanceId":"wall_shelves_1","assetId":"wall_shelves","position":[0.43374999999999997,1.0775000000000001,1.6],"yawRadians":0},{"instanceId":"drawers_sink_2","assetId":"drawers_sink","position":[0.42999999999999994,0.0,1.44725],"yawRadians":0},{"instanceId":"bed_3","assetId":"bed","position":[0.8800000000000001,0.0,-0.72],"yawRadians":0},{"instanceId":"rug_4","assetId":"rug","position":[-1.1,0.003000000000000001,0.4],"yawRadians":0},{"instanceId":"chair_5","assetId":"chair","position":[-1.1035,0.019161240682637543,-0.43],"yawRadians":0},{"instanceId":"mirror_6","assetId":"mirror","position":[-0.445,0.0,-1.5409596300854067],"yawRadians":0},{"instanceId":"window_curtains_7","assetId":"window_curtains","position":[1.229553358369463,0.41999999999999993,0.8200000000000001],"yawRadians":0}]}"#
        let layout = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: Data(json.utf8))
        try layout.validate()
        try write(Record(id: id, name: "Sample Room", createdAt: Date(), updatedAt: Date(), layout: layout), to: folder)
    }

    private static func write(_ record: Record, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: folder.appendingPathComponent(record.id + ".json"), options: .atomic)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension RoomDocument {
    /// Validate untrusted persisted/bridge geometry before allocating rendering resources.
    func validateForPreview() throws {
        guard schemaVersion == 1, units == "meters", coordinateSystem == "right-handed-y-up",
              transformLayout == "column-major", structures.count <= 500, objects.count <= 100,
              !walls.isEmpty || !floors.isEmpty || !objects.isEmpty else { throw RoomLibraryError.invalidLayout }
        var ids = Set<String>()
        for item in structures + objects {
            let dims = [item.dimensions.width, item.dimensions.height, item.dimensions.depth]
            guard !item.id.isEmpty, item.id.count <= 120, ids.insert(item.id).inserted,
                  item.transform.count == 16, item.transform.allSatisfy({ $0.isFinite && abs($0) < 10_000 }),
                  abs(item.transform[3]) < 0.01, abs(item.transform[7]) < 0.01,
                  abs(item.transform[11]) < 0.01, abs(item.transform[15] - 1) < 0.01,
                  dims.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 100 }),
                  dims.contains(where: { $0 > 0 }), (item.polygonCorners?.count ?? 0) <= 100 else {
                throw RoomLibraryError.invalidLayout
            }
            for corner in item.polygonCorners ?? [] {
                guard [corner.x, corner.y, corner.z].allSatisfy({ $0.isFinite && abs($0) < 100 }) else {
                    throw RoomLibraryError.invalidLayout
                }
            }
        }
    }
}

extension RoomLayoutSnapshot {
    /// Selection, camera movement and item ordering don't count as layout edits.
    func hasPlacementChanges(comparedTo baseline: RoomLayoutSnapshot) -> Bool {
        guard version == baseline.version, units == baseline.units, upAxis == baseline.upAxis,
              scannedRoom == baseline.scannedRoom, items.count == baseline.items.count else { return true }
        let epsilon = 0.00001
        for item in items {
            guard let old = baseline.items.first(where: { $0.instanceId == item.instanceId }),
                  item.assetId == old.assetId, item.label == old.label, item.productID == old.productID,
                  item.position.count == 3, old.position.count == 3 else { return true }
            if zip(item.position, old.position).contains(where: { abs($0 - $1) > epsilon }) { return true }
            let angle = (item.yawRadians - old.yawRadians).truncatingRemainder(dividingBy: 2 * .pi)
            if min(abs(angle), 2 * .pi - abs(angle)) > epsilon { return true }
        }
        return false
    }
}
