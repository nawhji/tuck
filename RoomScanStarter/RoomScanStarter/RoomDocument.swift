import Foundation
import RoomPlan
import simd

/// Web / backend contract. All distances are meters in this scan's world space.
struct RoomDocument: Codable, Sendable {
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

struct RoomElement: Codable, Identifiable, Sendable {
    let id: String
    let kind: String
    let category: String
    var label: String?
    let confidence: String
    let dimensions: Dimensions
    let position: Vector3
    /// Local-to-world matrix: [column0, column1, column2, column3], 16 floats.
    let transform: [Float]

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

struct Dimensions: Codable, Sendable {
    let width: Float
    let height: Float
    let depth: Float
}

struct Vector3: Codable, Sendable {
    let x: Float
    let y: Float
    let z: Float
}
