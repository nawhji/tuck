import Foundation
import RoomPlan

struct ScanFiles: Sendable {
    let directory: URL
    let json: URL
    let nativeJSON: URL
    let model: URL?
    let modelWarning: String?
}

enum RoomExporter {
    /// Call off the main thread: USDZ export can take several seconds.
    static func save(room: CapturedRoom, document: RoomDocument) throws -> ScanFiles {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = documents.appendingPathComponent("RoomScans", isDirectory: true)
            .appendingPathComponent(document.id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let json = directory.appendingPathComponent("room.json")
        let nativeJSON = directory.appendingPathComponent("captured-room.json")
        let modelURL = directory.appendingPathComponent("room.usdz")

        // Save measurements first, so a failed USDZ export cannot lose them.
        try write(document, to: json)
        try encoder().encode(room).write(to: nativeJSON, options: .atomic)

        var model: URL?
        var warning: String?
        do {
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
            try room.export(to: modelURL, exportOptions: .parametric)
            model = modelURL
        } catch {
            warning = "치수 JSON은 저장했지만 3D 파일 내보내기에 실패했어요: \(error.localizedDescription)"
        }
        return ScanFiles(directory: directory, json: json, nativeJSON: nativeJSON,
                         model: model, modelWarning: warning)
    }

    static func write(_ document: RoomDocument, to url: URL) throws {
        try encoder().encode(document).write(to: url, options: .atomic)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
