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
            XCTAssertEqual(try ScanStore.all(in: root).map(\.id), ["newer", "older"])
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
            XCTAssertEqual(try ScanStore.all(in: root).map(\.id), ["good"])
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


final class FavoritesStoreTests: XCTestCase {
    private func withFile(_ run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory.appendingPathComponent("favorites.json"))
    }

    func testFavoriteRestoresFullProductAfterRelaunch() throws {
        try withFile { url in
            let store = FavoritesStore(fileURL: url)
            let product = Product.samples[0]
            XCTAssertTrue(store.toggle(product))
            let restored = FavoritesStore(fileURL: url)
            XCTAssertEqual(restored.products, [product])
            XCTAssertTrue(restored.contains(product.id))
        }
    }

    func testUnsaveUsesIDAndPersistsAcrossRelaunch() throws {
        try withFile { url in
            let store = FavoritesStore(fileURL: url)
            var updated = Product.samples[0]
            XCTAssertTrue(store.toggle(updated))
            updated.name = "Changed recommendation text"
            XCTAssertTrue(store.toggle(updated))
            XCTAssertTrue(FavoritesStore(fileURL: url).products.isEmpty)
        }
    }

    func testCorruptFileIsPreservedWhenSavingIsAttempted() throws {
        try withFile { url in
            let original = Data("invalid saved data".utf8)
            try original.write(to: url)
            let store = FavoritesStore(fileURL: url)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertFalse(store.toggle(Product.samples[0]))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testFailedDiskWriteDoesNotShowUnsavedHeartAsSaved() throws {
        try withFile { url in
            let store = FavoritesStore(fileURL: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            XCTAssertFalse(store.toggle(Product.samples[0]))
            XCTAssertTrue(store.products.isEmpty)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testDuplicateStoredIDsAreCollapsed() throws {
        try withFile { url in
            let product = Product.samples[0]
            try JSONEncoder().encode([product, product]).write(to: url)
            XCTAssertEqual(FavoritesStore(fileURL: url).products.count, 1)
        }
    }
}

@MainActor
final class IntegratedHomeFlowTests: XCTestCase {
    func testFailedScanDoesNotPretendToHaveARoom() {
        let model = HomeViewModel()
        model.startScan()
        XCTAssertTrue(model.isPresentingScan)
        model.finishScan(nil)
        XCTAssertFalse(model.isPresentingScan)
        XCTAssertFalse(model.hasScannedSpace)
        XCTAssertEqual(model.sheetDetent, .collapsed)
        XCTAssertNil(model.savedScan)
        XCTAssertNotNil(model.scanLoadError)
    }

    func testScanAndProfileCannotPresentAtTheSameTime() {
        let model = HomeViewModel()
        model.openProfile()
        XCTAssertTrue(model.isProfilePresented)
        model.startScan()
        XCTAssertFalse(model.isPresentingScan)
        model.isProfilePresented = false
        model.startScan()
        model.openProfile()
        XCTAssertTrue(model.isPresentingScan)
        XCTAssertFalse(model.isProfilePresented)
    }

    func testFinishingScanOpensActualMeasurements() {
        let model = HomeViewModel()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = ScanFiles(directory: directory,
                              json: directory.appendingPathComponent("room.json"),
                              nativeJSON: directory.appendingPathComponent("captured-room.json"),
                              model: nil, modelWarning: nil)
        model.startScan()
        model.finishScan(SavedScan(document: .sample, files: files))
        XCTAssertEqual(model.savedScan?.id, RoomDocument.sample.id)
        XCTAssertEqual(model.savedScan?.files.json, files.json)
        XCTAssertTrue(model.hasScannedSpace)
        XCTAssertFalse(model.isPresentingScan)
    }

    func testBackgroundCancellationRejectsPreviousProcessingCallbacks() {
        let scanner = RoomScanner.preview(phase: .processing)
        let token = scanner.scanID
        scanner.cancel()
        scanner.fail("Late processing error", token: token)
        scanner.updateCounts(walls: 10, objects: 10, token: token)
        XCTAssertEqual(scanner.phase, .idle)
        XCTAssertNil(scanner.errorMessage)
        XCTAssertEqual(scanner.wallCount, 0)
    }
}

final class ScannedRoomLibraryTests: XCTestCase {
    private func withRoots(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("scans"), root.appendingPathComponent("layouts"))
    }
    private func snapshot() -> RoomLayoutSnapshot {
        let doc = RoomDocument.sample
        return RoomLayoutSnapshot(version: 1, units: "meters", upAxis: "Y", items: doc.objects.map {
            .init(instanceId: $0.id, assetId: "scan-" + $0.id,
                  position: [Double($0.position.x) + 0.25, Double($0.position.y), Double($0.position.z)], yawRadians: 0.4)
        }, scannedRoom: doc)
    }
    func testRoom1IsRegisteredOnceAndIsNotOverwrittenAfterEditing() throws {
        try withRoots { scans, layouts in
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let entries = try RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts)
            XCTAssertEqual(entries.count, 1)
            let room = try XCTUnwrap(entries.first)
            XCTAssertEqual(room.name, "Sample Room")
            XCTAssertEqual(room.layout?.items.count, 7)
            XCTAssertNil(room.layout?.scannedRoom)
            let edited = RoomLayoutSnapshot(version: 1, units: "meters", upAxis: "Y", items: [])
            try RoomLibraryStore.saveExisting(id: room.id, layout: edited, scansRoot: scans, layoutsRoot: layouts)
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            XCTAssertEqual(try RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts).first?.layout, edited)
        }
    }
    func testScannedGeometryAndEditedTransformsSurviveSaveAndReload() throws {
        try withRoots { scans, layouts in
            let original = snapshot()
            let id = try RoomLibraryStore.saveNew(name: "My scanned room", layout: original, layoutsRoot: layouts)
            let entry = try XCTUnwrap(RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts).first)
            XCTAssertEqual(entry.id, id)
            XCTAssertEqual(entry.layout?.items, original.items)
            XCTAssertEqual(entry.layout?.scannedRoom?.walls, original.scannedRoom?.walls)
            XCTAssertEqual(entry.layout?.scannedRoom?.objects, original.scannedRoom?.objects)
            XCTAssertEqual(entry.layout?.scannedRoom?.id, original.scannedRoom?.id)
        }
    }
    func testNamedScanDoesNotAppearTwiceAndRetainsRawMeasurements() throws {
        try withRoots { scans, layouts in
            let doc = RoomDocument.sample
            let dir = scans.appendingPathComponent(doc.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let raw = try encoder.encode(doc)
            let file = dir.appendingPathComponent("room.json")
            try raw.write(to: file)
            let id = try RoomLibraryStore.saveNew(name: "Named scan", layout: snapshot(), layoutsRoot: layouts)
            let entries = try RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts)
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first?.id, id)
            XCTAssertEqual(entries.first?.scan?.id, doc.id)
            XCTAssertEqual(try Data(contentsOf: file), raw)
        }
    }
    func testInvalidGeometryCannotReplaceSavedRoom() throws {
        try withRoots { scans, layouts in
            let id = try RoomLibraryStore.saveNew(name: "Good room", layout: snapshot(), layoutsRoot: layouts)
            let file = layouts.appendingPathComponent(id + ".json"), before = try Data(contentsOf: file)
            let encoded = try JSONEncoder().encode(snapshot())
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var doc = try XCTUnwrap(json["scannedRoom"] as? [String: Any])
            doc["units"] = "feet"; json["scannedRoom"] = doc
            let bad = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try RoomLibraryStore.saveExisting(id: id, layout: bad, scansRoot: scans, layoutsRoot: layouts))
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }
    @MainActor
    func testHomeStartsEmptyAndOpensSavedScanForEditing() {
        let model = HomeViewModel(), layout = snapshot()
        XCTAssertFalse(model.hasScannedSpace)
        let sceneID = model.sceneID
        model.isProfilePresented = true
        model.openSavedRoom(.init(id: "saved", name: "My room", updatedAt: Date(), layout: layout, scan: nil))
        XCTAssertTrue(model.hasScannedSpace)
        XCTAssertFalse(model.isProfilePresented)
        XCTAssertNotEqual(model.sceneID, sceneID)
        XCTAssertEqual(model.activeLayout, layout)
        XCTAssertEqual(model.roomDisplayName, "My room")
        model.removeCurrentRoom()
        XCTAssertNil(model.activeLayout)
        XCTAssertFalse(model.hasScannedSpace)
    }
    func testLegacyMockLayoutStillDecodesWithoutScanGeometry() throws {
        let json = #"{"version":1,"units":"meters","upAxis":"Y","items":[]}"#
        let layout = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: Data(json.utf8))
        try layout.validate()
        XCTAssertNil(layout.scannedRoom)
    }
    func testRoom1CanBeExplicitlyReplacedWithAnActualScan() throws {
        try withRoots { scans, layouts in
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let original = try XCTUnwrap(RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts).first)
            try RoomLibraryStore.saveExisting(id: original.id, layout: snapshot(), scansRoot: scans, layoutsRoot: layouts)
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let updated = try XCTUnwrap(RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts).first)
            XCTAssertEqual(updated.name, "Sample Room")
            XCTAssertEqual(updated.layout?.scannedRoom?.id, RoomDocument.sample.id)
        }
    }
}

final class RoomSwitchingTests: XCTestCase {
    private func layout(x: Double = 0, yaw: Double = 0, asset: String = "chair") -> RoomLayoutSnapshot {
        .init(version: 1, units: "meters", upAxis: "Y", items: [
            .init(instanceId: "chair-1", assetId: asset, position: [x,0,0], yawRadians: yaw)
        ])
    }
    func testSuggestedNameAdvancesBeyondSavedRoomNumbers() {
        XCTAssertEqual(RoomNameSequence.nextName(in: []), "New Room 1")
        XCTAssertEqual(RoomNameSequence.nextName(in: ["Room 1"]), "New Room 2")
        XCTAssertEqual(RoomNameSequence.nextName(in: ["Room 1", "New Room 2", "New Room 8"]), "New Room 9")
        XCTAssertEqual(RoomNameSequence.nextName(in: ["Bedroom", " Room 12 ", "new room 4"]), "New Room 13")
    }
    func testNonNumericAndOverflowNamesCannotCrashNumbering() {
        XCTAssertEqual(RoomNameSequence.nextName(in: ["Room -2", "New Room x", "New Room 99999999999999999999999999"]), "New Room 1")
        XCTAssertEqual(RoomNameSequence.nextName(in: ["Room \(Int.max)", "New Room 2"]), "New Room 1")
    }
    func testCameraAndSelectionDoNotCountAsPlacementChanges() {
        XCTAssertFalse(layout().hasPlacementChanges(comparedTo: layout()))
        XCTAssertFalse(layout(yaw: .pi * 2).hasPlacementChanges(comparedTo: layout()))
        XCTAssertFalse(layout(x: 0.0000001, yaw: 0.0000001).hasPlacementChanges(comparedTo: layout()))
    }
    func testMovementRotationAndReplacementAreDetected() {
        XCTAssertTrue(layout(x: 0.1).hasPlacementChanges(comparedTo: layout()))
        XCTAssertTrue(layout(yaw: .pi / 12).hasPlacementChanges(comparedTo: layout()))
        XCTAssertTrue(layout(asset: "bed").hasPlacementChanges(comparedTo: layout()))
        let empty = RoomLayoutSnapshot(version: 1, units: "meters", upAxis: "Y", items: [])
        XCTAssertTrue(empty.hasPlacementChanges(comparedTo: layout()))
    }
    func testItemOrderingDoesNotCreateFalseUnsavedChanges() {
        let a = RoomLayoutSnapshot.Item(instanceId: "a", assetId: "chair", position: [0,0,0], yawRadians: 0)
        let b = RoomLayoutSnapshot.Item(instanceId: "b", assetId: "bed", position: [1,0,0], yawRadians: 0)
        let one = RoomLayoutSnapshot(version: 1, units: "meters", upAxis: "Y", items: [a,b])
        let two = RoomLayoutSnapshot(version: 1, units: "meters", upAxis: "Y", items: [b,a])
        XCTAssertFalse(one.hasPlacementChanges(comparedTo: two))
    }
    @MainActor
    func testEmptyHomeUsesNumberWithoutCreatingARoom() {
        let model = HomeViewModel()
        XCTAssertEqual(model.roomDisplayName, "New Room 1")
        XCTAssertFalse(model.hasScannedSpace)
        XCTAssertFalse(model.needsSaveBeforeSwitch(layoutChanged: false))
        let entries = [RoomLibraryEntry(id: "saved", name: "New Room 5", updatedAt: Date(), layout: nil, scan: nil)]
        model.updateRoomNames(entries)
        XCTAssertEqual(model.roomDisplayName, "New Room 6")
        XCTAssertFalse(model.hasScannedSpace)
    }
    @MainActor
    func testSavedRoomPromptsOnlyWhenPlacementChanges() {
        let model = HomeViewModel()
        model.openSavedRoom(.init(id: "saved", name: "Room 1", updatedAt: Date(), layout: layout(), scan: nil))
        XCTAssertEqual(model.activeRoomID, "saved")
        XCTAssertEqual(model.roomDisplayName, "Room 1")
        XCTAssertFalse(model.needsSaveBeforeSwitch(layoutChanged: false))
        XCTAssertTrue(model.needsSaveBeforeSwitch(layoutChanged: true))
    }
    @MainActor
    func testFreshScanPromptsOnlyAfterPlacementChanges() {
        let model = HomeViewModel()
        let dir = URL(fileURLWithPath: "/unused")
        let files = ScanFiles(directory: dir, json: dir, nativeJSON: dir, model: nil, modelWarning: nil)
        model.acceptScan(document: .sample, files: files)
        XCTAssertEqual(model.roomDisplayName, "New Room 1")
        XCTAssertNil(model.activeRoomID)
        XCTAssertFalse(model.needsSaveBeforeSwitch(layoutChanged: false))
        XCTAssertTrue(model.needsSaveBeforeSwitch(layoutChanged: true))
        XCTAssertEqual(model.suggestedSaveName, "New Room 1")
    }
    @MainActor
    func testLeavingSavedRoomReturnsToNextDraftName() {
        let model = HomeViewModel()
        let entry = RoomLibraryEntry(id: "saved", name: "New Room 5", updatedAt: Date(), layout: layout(), scan: nil)
        model.updateRoomNames([entry])
        model.openSavedRoom(entry)
        XCTAssertEqual(model.roomDisplayName, "New Room 5")
        XCTAssertEqual(model.suggestedSaveName, "New Room 6")
        model.removeCurrentRoom()
        XCTAssertEqual(model.roomDisplayName, "New Room 6")
        XCTAssertNil(model.activeRoomID)
        XCTAssertFalse(model.hasScannedSpace)
    }
}

final class SampleRoomMigrationTests: XCTestCase {
    private func withRoots(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("scans"), root.appendingPathComponent("layouts"))
    }
    func testFreshInstallStartsAtOneWithSampleExcludedFromNumbering() throws {
        try withRoots { scans, layouts in
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let entries = try RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts)
            XCTAssertEqual(entries.map(\.name), ["Sample Room"])
            XCTAssertEqual(RoomNameSequence.nextName(in: entries.map(\.name)), "New Room 1")
            XCTAssertEqual(RoomNameSequence.nextName(in: ["Sample Room", "New Room 1"]), "New Room 2")
        }
    }
    func testLegacySampleRenameKeepsIDTimestampsAndEditedFurniture() throws {
        try withRoots { scans, layouts in
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let file = layouts.appendingPathComponent("tuck-demo-room-1.json")
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            json["name"] = "Room 1"
            var layout = try XCTUnwrap(json["layout"] as? [String: Any])
            var items = try XCTUnwrap(layout["items"] as? [[String: Any]])
            items[0]["position"] = [1.25, 2.0, 3.5]
            items[0]["yawRadians"] = 0.7
            layout["items"] = items; json["layout"] = layout
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let before = try XCTUnwrap(RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts).first)
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let entries = try RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts)
            let after = try XCTUnwrap(entries.first)
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(after.id, before.id)
            XCTAssertEqual(after.name, "Sample Room")
            XCTAssertEqual(after.updatedAt, before.updatedAt)
            XCTAssertEqual(after.layout, before.layout)
            let migrated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            XCTAssertEqual(migrated["createdAt"] as? String, json["createdAt"] as? String)
        }
    }
    func testUserRenamedSampleAndOtherRoom1AreKept() throws {
        try withRoots { scans, layouts in
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let file = layouts.appendingPathComponent("tuck-demo-room-1.json")
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            json["name"] = "My custom sample"
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let layout = try XCTUnwrap(RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts).first?.layout)
            let otherID = try RoomLibraryStore.saveNew(name: "Room 1", layout: layout, layoutsRoot: layouts)
            try RoomLibraryStore.ensureDemoRoom(layoutsRoot: layouts)
            let entries = try RoomLibraryStore.all(scansRoot: scans, layoutsRoot: layouts)
            XCTAssertEqual(entries.first(where: { $0.id == "tuck-demo-room-1" })?.name, "My custom sample")
            XCTAssertEqual(entries.first(where: { $0.id == otherID })?.name, "Room 1")
        }
    }
}

final class SaveBeforeScanTests: XCTestCase {
    private func layout(x: Double) -> RoomLayoutSnapshot {
        .init(version: 1, units: "meters", upAxis: "Y", items: [
            .init(instanceId: "chair", assetId: "chair", position: [x,0,0], yawRadians: 0.4)
        ])
    }
    @MainActor
    func testSaveBeforeScanKeepsSceneAndChatButUpdatesSavedPlacement() {
        let model = HomeViewModel()
        model.messages = [.sampleUser]
        let original = RoomLibraryEntry(id: "sample", name: "Sample Room", updatedAt: Date(), layout: layout(x: 0), scan: nil)
        model.openSavedRoom(original)
        let sceneID = model.sceneID
        let saved = RoomLibraryEntry(id: original.id, name: original.name, updatedAt: Date(), layout: layout(x: 1), scan: nil)
        model.recordSavedRoom(saved)
        XCTAssertEqual(model.sceneID, sceneID)
        XCTAssertEqual(model.activeLayout, saved.layout)
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.activeRoomID, saved.id)
        model.startScan()
        XCTAssertTrue(model.isPresentingScan)
        model.isPresentingScan = false
        XCTAssertEqual(model.activeLayout, saved.layout)
        XCTAssertEqual(model.roomDisplayName, "Sample Room")
    }
    @MainActor
    func testSaveAsNewBeforeScanUsesNextNameForTheCapturedRoom() {
        let model = HomeViewModel()
        let saved = RoomLibraryEntry(id: "new", name: "New Room 1", updatedAt: Date(), layout: layout(x: 1), scan: nil)
        model.updateRoomNames([saved])
        model.recordSavedRoom(saved)
        XCTAssertEqual(model.activeRoomID, "new")
        XCTAssertEqual(model.roomDisplayName, "New Room 1")
        let dir = URL(fileURLWithPath: "/unused")
        let files = ScanFiles(directory: dir, json: dir, nativeJSON: dir, model: nil, modelWarning: nil)
        model.startScan()
        model.finishScan(SavedScan(document: .sample, files: files))
        XCTAssertEqual(model.roomDisplayName, "New Room 2")
        XCTAssertNil(model.activeRoomID)
        XCTAssertFalse(model.isPresentingScan)
    }
    @MainActor
    func testCancellingUnmodifiedScanKeepsPreviousRoom() {
        let model = HomeViewModel()
        let saved = RoomLibraryEntry(id: "sample", name: "Sample Room", updatedAt: Date(), layout: layout(x: 0), scan: nil)
        model.openSavedRoom(saved)
        let sceneID = model.sceneID
        XCTAssertFalse(model.needsSaveBeforeSwitch(layoutChanged: false))
        model.startScan()
        model.isPresentingScan = false
        XCTAssertEqual(model.sceneID, sceneID)
        XCTAssertEqual(model.activeRoomID, "sample")
        XCTAssertEqual(model.activeLayout, saved.layout)
        XCTAssertTrue(model.hasScannedSpace)
    }
}
