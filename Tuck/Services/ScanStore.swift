import Foundation

struct SavedScan: Identifiable, Sendable {
    var id: String { document.id }
    let document: RoomDocument
    let files: ScanFiles
}

/// Reads only this app's Documents directory. No upload, account, or API key.
enum ScanStore {
    static func latest(in root: URL? = nil) throws -> SavedScan? {
        let rootURL: URL
        if let root {
            rootURL = root
        } else {
            rootURL = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("RoomScans", isDirectory: true)
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return nil }
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
                modelWarning: model == nil ? "치수는 저장되어 있지만 3D 파일이 없어요. 다시 스캔해주세요." : nil
            )
            scans.append(SavedScan(document: document, files: files))
        }
        if let latest = scans.max(by: { $0.document.capturedAt < $1.document.capturedAt }) {
            return latest
        }
        if !directories.isEmpty { throw StoreError.unreadable }
        return nil
    }

    private enum StoreError: LocalizedError {
        case unreadable
        var errorDescription: String? { "저장된 방을 읽지 못했어요. 새 스캔을 시작할 수 있어요." }
    }
}
