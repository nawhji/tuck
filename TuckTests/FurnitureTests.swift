import XCTest
import SceneKit
import UIKit
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

    func testOriginalTintAndSurfaceMapsSurviveExport() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { _ in
            UIColor.brown.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.multiply.contents = UIColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1)
        material.normal.contents = image; material.normal.intensity = 0.65
        material.roughness.contents = image
        let box = SCNBox(width: 0.6, height: 0.8, length: 0.7, chamferRadius: 0)
        box.materials = [material]
        let scene = SCNScene(); scene.rootNode.addChildNode(SCNNode(geometry: box))
        let model = try FurnitureModelLibrary.export(scene: scene, id: "test", label: "Chair", target: [0.6, 0.8, 0.7])
        let part = try XCTUnwrap(model.parts.first)
        for (actual, expected) in zip(part.color, [Float(0.5), 0.7, 0.9]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
        XCTAssertTrue(try XCTUnwrap(part.texture).hasPrefix("data:image/png;base64,"))
        XCTAssertNotNil(part.normalTexture)
        XCTAssertNotNil(part.roughnessTexture)
        XCTAssertEqual(try XCTUnwrap(part.normalStrength), 0.65, accuracy: 0.001)
        XCTAssertEqual(part.roughness, 1)
        let bytes = try XCTUnwrap(Data(base64Encoded: String(try XCTUnwrap(part.texture).split(separator: ",", maxSplits: 1)[1])))
        XCTAssertEqual(UIImage(data: bytes)?.size, CGSize(width: 2, height: 2))
    }

    func testCGColorAndConstantRoughnessSurviveExport() throws {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1).cgColor
        material.roughness.contents = NSNumber(value: 0.3)
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0); box.materials = [material]
        let scene = SCNScene(); scene.rootNode.addChildNode(SCNNode(geometry: box))
        let model = try FurnitureModelLibrary.export(scene: scene, id: "test", label: "Chair", target: [1, 1, 1])
        let part = try XCTUnwrap(model.parts.first)
        for (actual, expected) in zip(part.color, [Float(0.2), 0.4, 0.6]) {
            XCTAssertEqual(actual, expected, accuracy: 0.001)
        }
        XCTAssertEqual(part.roughness, 0.3, accuracy: 0.001)
        XCTAssertNil(part.texture); XCTAssertNil(part.roughnessTexture)
    }

    /// Run this with Product > Test on the Mac before a live demo.
    func testPreparedModelsLoadWithOriginalMaterialChannels() async throws {
        for id in FurnitureCatalog.modelIDs {
            XCTAssertNotNil(Bundle.main.url(forResource: id, withExtension: "usdz"))
            let data = try await FurnitureModelLibrary.shared.payload(for: id)
            let model = try JSONDecoder().decode(FurnitureModelLibrary.ModelPayload.self, from: data)
            XCTAssertEqual(model.id, id)
            XCTAssertEqual(model.appearanceVersion, 1)
            XCTAssertNotNil(Bundle.main.url(forResource: id, withExtension: "tuckmodel", subdirectory: "ChairMaterials"))
            for part in model.parts {
                let vertices = try XCTUnwrap(Data(base64Encoded: part.positions)).count / 12
                XCTAssertGreaterThan(vertices, 100_000, "Original mesh must not be simplified")
                XCTAssertEqual(try XCTUnwrap(Data(base64Encoded: part.tangents ?? "")).count, vertices * 16)
                let indices = try XCTUnwrap(Data(base64Encoded: part.indices ?? ""))
                XCTAssertGreaterThan(indices.count, 0)
                XCTAssertTrue(indices.count.isMultiple(of: 12))
                XCTAssertEqual(part.color, [1, 1, 1])
                for map in [part.texture, part.normalTexture, part.roughnessTexture, part.metallicTexture] {
                    let uri = try XCTUnwrap(map)
                    let bytes = try XCTUnwrap(Data(base64Encoded: String(uri.split(separator: ",", maxSplits: 1)[1])))
                    XCTAssertEqual(UIImage(data: bytes)?.size, CGSize(width: 2048, height: 2048))
                }
            }
            XCTAssertFalse(model.parts.isEmpty)
            XCTAssertGreaterThan(model.bounds[1][1], 0.3)
            XCTAssertLessThan(model.bounds[1][1], 1.5)
            XCTAssertTrue(model.parts.contains { $0.texture != nil }, "Check source textures for \(id)")
        }
    }
}
