import Foundation
import RoomPlan
import simd

/// Web / backend contract. All distances are meters in this scan's world space.
struct RoomDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let capturedAt: Date
    let units: String
    let coordinateSystem: String
    let transformLayout: String
    let walls: [RoomElement]
    let doors: [RoomElement]
    let windows: [RoomElement]
    let openings: [RoomElement]
    let floors: [RoomElement]
    var objects: [RoomElement]

    var structures: [RoomElement] {
        [walls, doors, windows, openings, floors].flatMap { $0 }
    }

    init(room: CapturedRoom) {
        schemaVersion = 1
        id = UUID().uuidString
        capturedAt = Date()
        units = "meters"
        coordinateSystem = "right-handed-y-up"
        transformLayout = "column-major"
        walls = room.walls.map { RoomElement(surface: $0, kind: "wall") }
        doors = room.doors.map { RoomElement(surface: $0, kind: "door") }
        windows = room.windows.map { RoomElement(surface: $0, kind: "window") }
        openings = room.openings.map { RoomElement(surface: $0, kind: "opening") }
        floors = room.floors.map { RoomElement(surface: $0, kind: "floor") }
        objects = room.objects.map { RoomElement(object: $0) }
    }
}

struct RoomElement: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let category: String
    var label: String?
    let confidence: String
    let dimensions: Dimensions
    let position: Vector3
    /// Local-to-world matrix: [column0, column1, column2, column3], 16 floats.
    let transform: [Float]
    var polygonCorners: [Vector3]? = nil

    init(object: CapturedRoom.Object) {
        self.init(
            id: object.identifier.uuidString,
            kind: "object",
            category: String(describing: object.category),
            confidence: String(describing: object.confidence),
            dimensions: object.dimensions,
            transform: object.transform
        )
    }

    init(surface: CapturedRoom.Surface, kind: String) {
        self.init(
            id: surface.identifier.uuidString,
            kind: kind,
            category: kind,
            confidence: String(describing: surface.confidence),
            dimensions: surface.dimensions,
            transform: surface.transform
        )
        if !surface.polygonCorners.isEmpty {
            polygonCorners = surface.polygonCorners.map { Vector3(x: $0.x, y: $0.y, z: $0.z) }
        }
    }

    private init(
        id: String, kind: String, category: String, confidence: String,
        dimensions: SIMD3<Float>, transform: simd_float4x4
    ) {
        self.id = id
        self.kind = kind
        self.category = category
        self.confidence = confidence
        label = nil
        self.dimensions = Dimensions(
            width: abs(dimensions.x),
            height: abs(dimensions.y),
            depth: abs(dimensions.z)
        )
        let translation = transform.columns.3
        position = Vector3(x: translation.x, y: translation.y, z: translation.z)
        self.transform = (0..<4).flatMap { column in
            let values = transform[column]
            return [values.x, values.y, values.z, values.w]
        }
    }

    var sizeDescription: String {
        String(format: "%.0f × %.0f × %.0f cm", dimensions.width * 100,
               dimensions.height * 100, dimensions.depth * 100)
    }
}

struct Dimensions: Codable, Equatable, Sendable {
    let width: Float
    let height: Float
    let depth: Float
}

struct Vector3: Codable, Equatable, Sendable {
    let x: Float
    let y: Float
    let z: Float
}

#if DEBUG
extension RoomDocument {
    /// Sample room for SwiftUI previews. Not real scan data.
    static let sample = RoomDocument(
        id: "preview-room", walls: 4, objects: [
            ("table", SIMD3(1.0, 0.75, 0.4), SIMD3(1.2, 0.4, -0.9), "화장대"),
            ("bed", SIMD3(1.6, 0.5, 2.0), SIMD3(-0.8, 0.25, 0.6), nil),
            ("storage", SIMD3(0.9, 1.8, 0.4), SIMD3(2.0, 0.9, 0.5), nil)
        ]
    )

    private init(id: String, walls wallCount: Int, objects: [(String, SIMD3<Float>, SIMD3<Float>, String?)]) {
        let element = RoomElement.sample
        schemaVersion = 1
        self.id = id
        capturedAt = Date()
        units = "meters"
        coordinateSystem = "right-handed-y-up"
        transformLayout = "column-major"
        walls = (0..<wallCount).map { index in
            element("wall", "wall", SIMD3(4, 2.4, 0), SIMD3(Float(index) - 1.5, 1.2, -2))
        }
        doors = [element("door", "door", SIMD3(0.9, 2.0, 0), SIMD3(-2, 1, 0))]
        windows = [element("window", "window", SIMD3(1.2, 1.1, 0), SIMD3(0, 1.4, -2))]
        openings = []
        floors = [element("floor", "floor", SIMD3(4, 5, 0), SIMD3(0, 0, 0))]
        self.objects = objects.map { category, size, at, label in
            var item = element("object", category, size, at)
            item.label = label
            return item
        }
    }
}

extension RoomElement {
    static func sample(_ kind: String, _ category: String, _ size: SIMD3<Float>, _ at: SIMD3<Float>) -> RoomElement {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(at.x, at.y, at.z, 1)
        return RoomElement(id: UUID().uuidString, kind: kind, category: category,
                           confidence: "high", dimensions: size, transform: matrix)
    }
}
#endif


/// A fresh, read-only snapshot of the displayed scene, not a claim of fit.
struct RoomChatContext: Codable, Sendable {
    struct Bounds: Codable, Sendable {
        let min: [Double]
        let max: [Double]
    }
    struct Element: Codable, Sendable {
        let id: String
        let category: String
        let label: String?
        let confidence: String?
        let dimensionsMeters: [Double]
        let centerMeters: [Double]
        let yawRadians: Double?
        let worldCornersMeters: [[Double]]
        let boundsMeters: Bounds
    }
    var roomID: String
    var roomName: String
    var revision: String
    let source: String
    let units: String
    let coordinateSystem: String
    let selectedObjectID: String?
    let objects: [Element]
    let structures: [Element]

    func validate() throws {
        guard units == "meters", coordinateSystem == "right-handed-y-up",
              ["scan_editor", "sample_editor"].contains(source),
              objects.count <= 100, structures.count <= 500 else { throw RoomLibraryError.invalidLayout }
        var ids = Set<String>()
        for item in objects + structures {
            let triples = [item.dimensionsMeters, item.centerMeters, item.boundsMeters.min, item.boundsMeters.max] + item.worldCornersMeters
            guard !item.id.isEmpty, item.id.count <= 160, ids.insert(item.id).inserted,
                  item.worldCornersMeters.count == 8,
                  triples.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && abs($0) < 10_000 } }),
                  item.dimensionsMeters.allSatisfy({ $0 >= 0 }),
                  zip(item.boundsMeters.min, item.boundsMeters.max).allSatisfy({ $0 <= $1 }),
                  item.yawRadians?.isFinite != false else { throw RoomLibraryError.invalidLayout }
        }
        if let selectedObjectID, !objects.contains(where: { $0.id == selectedObjectID }) {
            throw RoomLibraryError.invalidLayout
        }
    }

    var promptText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard (try? validate()) != nil, let data = try? encoder.encode(self) else { return "Room geometry unavailable." }
        return String(decoding: data, as: UTF8.self)
    }
}
