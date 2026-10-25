import XCTest
import SceneKit
@testable import Tuck

final class FurnitureTests: XCTestCase {
    func testPreparedChairSearchAndExactProductMapping() throws {
        let catalog = try ProductCatalog()
        XCTAssertEqual(FurnitureCatalog.products(catalog: catalog).map(\.id), FurnitureCatalog.modelIDs)
        XCTAssertEqual(FurnitureCatalog.products(matching: "OTIO chair", catalog: catalog).map(\.id), ["sofa_007_brown"])
        XCTAssertEqual(FurnitureCatalog.products(matching: "goda", catalog: catalog).map(\.id), ["sofa_027_brown"])
        XCTAssertEqual(FurnitureCatalog.products(matching: "Peacemaker", catalog: catalog).map(\.id), ["sofa_028_brown"])
        XCTAssertEqual(FurnitureCatalog.products(matching: "1인 소파", catalog: catalog).count, 3)
        for id in FurnitureCatalog.modelIDs { XCTAssertEqual(catalog.row(id: id)?["model_asset_id"], id) }
    }

    func testLegacyRoomLayoutAndNamedProductRoundTrip() throws {
        let legacy = Data(#"{"version":1,"units":"meters","upAxis":"Y","items":[{"instanceId":"bed_3","assetId":"bed","position":[0,0,0],"yawRadians":0}]}"#.utf8)
        let old = try JSONDecoder().decode(RoomLayoutSnapshot.self, from: legacy)
        XCTAssertNoThrow(try old.validate())
        XCTAssertNil(old.items[0].productID)
        let item = RoomLayoutSnapshot.Item(instanceId: "product:sofa_007_brown", assetId: "sofa_007_brown",
            position: [0.1,0,0.2], yawRadians: 0.6, label: "My reading chair", productID: "sofa_007_brown")
        let snapshot = RoomLayoutSnapshot(version: 1, units: "meters", upAxis: "Y", items: [item])
        XCTAssertNoThrow(try snapshot.validate())
        XCTAssertEqual(try JSONDecoder().decode(RoomLayoutSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let duplicate = RoomLayoutSnapshot.Item(instanceId: "another", assetId: item.assetId,
            position: [1,0,0], yawRadians: 0, productID: item.productID)
        XCTAssertThrowsError(try RoomLayoutSnapshot(version: 1, units: "meters", upAxis: "Y", items: [item,duplicate]).validate())
    }

    func testGeometryHierarchyAndCatalogScale() throws {
        let scene = SCNScene(), parent = SCNNode()
        parent.position = SCNVector3(30,50,-20); parent.scale = SCNVector3(100,100,100)
        parent.addChildNode(SCNNode(geometry: SCNBox(width: 0.6, height: 0.8, length: 0.7, chamferRadius: 0)))
        scene.rootNode.addChildNode(parent)
        let model = try FurnitureModelLibrary.export(scene: scene, id: "test", label: "Chair", target: [0.6,0.8,0.7])
        XCTAssertFalse(model.parts.isEmpty)
        XCTAssertEqual(model.bounds[0][1], 0, accuracy: 0.0001)
        XCTAssertEqual(model.bounds[1][1], 0.8, accuracy: 0.0001)
        let part = try XCTUnwrap(model.parts.first)
        let data = try XCTUnwrap(Data(base64Encoded: part.positions))
        XCTAssertTrue(data.count.isMultiple(of: 36))
        XCTAssertEqual(Data(base64Encoded: part.normals)?.count, data.count)
        XCTAssertEqual(Data(base64Encoded: part.uvs)?.count, data.count / 3 * 2)
    }

    /// Run this with Product > Test on the Mac before a live demo.
    func testOriginalBundledModelsImportWithTextures() async throws {
        for id in FurnitureCatalog.modelIDs {
            XCTAssertNotNil(Bundle.main.url(forResource: id, withExtension: "usdz"))
            let data = try await FurnitureModelLibrary.shared.payload(for: id)
            let model = try JSONDecoder().decode(FurnitureModelLibrary.ModelPayload.self, from: data)
            XCTAssertEqual(model.id, id)
            XCTAssertFalse(model.parts.isEmpty)
            XCTAssertGreaterThan(model.bounds[1][1], 0.3)
            XCTAssertLessThan(model.bounds[1][1], 1.5)
            XCTAssertTrue(model.parts.contains { $0.texture != nil }, "Check source textures for \(id)")
        }
    }
}
