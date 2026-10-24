import XCTest
@testable import Tuck

final class RoomScanTests: XCTestCase {
    private func withStore(_ run: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try run(root)
    }

    private func writeScan(_ root: URL, id: String, date: String, schema: Int = 1) throws {
        let directory = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(RoomDocument.sample)) as? [String: Any])
        json["id"] = id
        json["capturedAt"] = date
        json["schemaVersion"] = schema
        try JSONSerialization.data(withJSONObject: json).write(to: directory.appendingPathComponent("room.json"))
    }

    func testEmptyStoreHasNoScan() throws {
        try withStore { root in
            XCTAssertNil(try ScanStore.latest(in: root))
            XCTAssertNil(try ScanStore.latest(in: root.appendingPathComponent("missing")))
        }
    }

    func testRestoresNewestScanAndMeasurementsWithoutUSDZ() throws {
        try withStore { root in
            try writeScan(root, id: "older", date: "2026-10-23T12:00:00Z")
            try writeScan(root, id: "newer", date: "2026-10-24T12:00:00Z")
            let scan = try XCTUnwrap(ScanStore.latest(in: root))
            XCTAssertEqual(scan.id, "newer")
            XCTAssertEqual(scan.document.objects.first?.label, "화장대")
            XCTAssertEqual(scan.document.objects.first?.dimensions.width, 1.0)
            XCTAssertEqual(scan.document.objects.first?.transform.count, 16)
            XCTAssertNil(scan.files.model)
            XCTAssertNotNil(scan.files.modelWarning)
        }
    }

    func testCorruptOrUnsupportedScanDoesNotHideOlderScan() throws {
        try withStore { root in
            try writeScan(root, id: "good", date: "2026-10-23T12:00:00Z")
            try writeScan(root, id: "unsupported", date: "2026-10-24T12:00:00Z", schema: 999)
            let corrupt = root.appendingPathComponent("corrupt")
            try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
            try Data("broken".utf8).write(to: corrupt.appendingPathComponent("room.json"))
            XCTAssertEqual(try ScanStore.latest(in: root)?.id, "good")
        }
    }

    func testUnreadableStoreReportsErrorInsteadOfPretendingItIsEmpty() throws {
        try withStore { root in
            try writeScan(root, id: "future", date: "2026-10-24T12:00:00Z", schema: 999)
            XCTAssertThrowsError(try ScanStore.latest(in: root))
        }
    }

    func testEmptyModelIsNotExposedForPreviewOrSharing() throws {
        try withStore { root in
            try writeScan(root, id: "scan", date: "2026-10-24T12:00:00Z")
            try Data().write(to: root.appendingPathComponent("scan/room.usdz"))
            XCTAssertNil(try ScanStore.latest(in: root)?.files.model)
        }
    }

    @MainActor
    func testCancelInvalidatesLateSessionCallbacks() {
        let scanner = RoomScanner.preview(phase: .scanning)
        let token = scanner.scanID
        scanner.cancel()
        scanner.updateCounts(walls: 9, objects: 9, token: token)
        scanner.fail("Late failure", token: token)
        XCTAssertNotEqual(scanner.scanID, token)
        XCTAssertEqual(scanner.phase, .idle)
        XCTAssertEqual(scanner.wallCount, 0)
        XCTAssertNil(scanner.errorMessage)
    }

    @MainActor
    func testRenamingBeforeSaveDoesNotMutateMeasurements() {
        let scanner = RoomScanner.preview(phase: .ready, document: .sample)
        let object = scanner.document!.objects[0]
        XCTAssertFalse(scanner.renameObject(id: object.id, label: "New label"))
        XCTAssertEqual(scanner.document?.objects[0].label, object.label)
        XCTAssertNotNil(scanner.saveMessage)
    }
}
