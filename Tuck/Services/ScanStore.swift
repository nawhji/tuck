import Foundation

struct SavedScan: Identifiable, Sendable {
    var id: String { document.id }
    let document: RoomDocument
    let files: ScanFiles
}

/// Reads only this app's Documents directory. No upload, account, or API key.
enum ScanStore {
    static func latest(in root: URL? = nil) throws -> SavedScan? {
        try all(in: root).first
    }

    static func all(in root: URL? = nil) throws -> [SavedScan] {
        let rootURL: URL
        if let root {
            rootURL = root
        } else {
            rootURL = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("RoomScans", isDirectory: true)
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var scans: [SavedScan] = []
        for directory in directories {
            let json = directory.appendingPathComponent("room.json")
            // An interrupted/corrupt scan must not hide an older, usable scan.
            guard let data = try? Data(contentsOf: json),
                  let document = try? decoder.decode(RoomDocument.self, from: data),
                  document.schemaVersion == 1, document.units == "meters" else { continue }
            let modelURL = directory.appendingPathComponent("room.usdz")
            let size = (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let model = size > 0 ? modelURL : nil
            let files = ScanFiles(
                directory: directory, json: json,
                nativeJSON: directory.appendingPathComponent("captured-room.json"),
                model: model,
                modelWarning: model == nil ? "Measurements are saved, but the 3D model is unavailable. Please scan again." : nil
            )
            scans.append(SavedScan(document: document, files: files))
        }
        if scans.isEmpty && !directories.isEmpty { throw StoreError.unreadable }
        return scans.sorted { $0.document.capturedAt > $1.document.capturedAt }
    }

    private enum StoreError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Saved rooms could not be read. You can start a new scan." }
    }
}
