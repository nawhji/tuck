import Foundation

/// Explicit product-to-file mapping for the three supplied live-demo models.
/// Other products never silently fall back to an unrelated chair or a box.
enum FurnitureCatalog {
    static let modelIDs = ["sofa_007_brown", "sofa_027_brown", "sofa_028_brown"]

    static func supports(_ productID: String) -> Bool { modelIDs.contains(productID) }

    static func products(matching query: String = "", catalog: ProductCatalog) -> [Product] {
        let words = normalize(query).split(separator: " ").map(String.init).filter {
            !["chair", "chairs", "sofa", "sofas", "single", "seat", "seater", "armchair",
              "1", "1인", "1인용", "일인용", "쇼파", "소파", "의자", "1인쇼파", "1인소파"].contains($0)
        }
        return modelIDs.compactMap { id -> Product? in
            guard let row = catalog.row(id: id) else { return nil }
            let text = normalize([id, row["name"], row["brand"], row["color_name"], row["color_family"],
                                  row["description"], row["style_tags"], row["upholstery_material"]]
                .compactMap { $0 }.joined(separator: " "))
            guard words.allSatisfy({ text.contains($0) }) else { return nil }
            return Product(pick: ProductPick(id: id), catalog: catalog)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

struct FurnitureLayout: Codable, Equatable {
    var version = 1
    var units = "meters"
    var upAxis = "Y"
    var items: [Item]

    struct Item: Codable, Equatable {
        let instanceId: String
        let assetId: String
        var label: String
        var position: [Double]
        var yawRadians: Double
        var productID: String?
    }

    static let builtinIDs: Set<String> = ["wall_shelves", "drawers_sink", "bed", "rug", "chair",
                                          "mirror", "window_curtains", "closet_shelf"]

    func validated() throws -> FurnitureLayout {
        guard version == 1, units == "meters", upAxis == "Y", items.count <= 100 else {
            throw FurnitureError.invalidLayout
        }
        var instanceIDs = Set<String>()
        var productIDs = Set<String>()
        for item in items {
            guard !item.instanceId.isEmpty, item.instanceId.count <= 120,
                  instanceIDs.insert(item.instanceId).inserted,
                  !item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.label.count <= 80,
                  item.position.count == 3, item.position.allSatisfy({ $0.isFinite && abs($0) < 100 }),
                  item.yawRadians.isFinite, abs(item.yawRadians) < 10_000 else {
                throw FurnitureError.invalidLayout
            }
            if let productID = item.productID {
                guard FurnitureCatalog.supports(productID), item.assetId == productID,
                      productIDs.insert(productID).inserted else { throw FurnitureError.invalidLayout }
            } else if !Self.builtinIDs.contains(item.assetId) {
                throw FurnitureError.invalidLayout
            }
        }
        return self
    }
}

enum FurnitureError: LocalizedError {
    case invalidLayout, missingModel(String), unsupportedGeometry, emptyModel, rendererUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidLayout: "The saved furniture layout could not be read. Your file has been kept."
        case .missingModel(let id): "The 3D file for \(id) is missing from the app. Check Copy Bundle Resources in Xcode."
        case .unsupportedGeometry: "This 3D model contains unsupported geometry."
        case .emptyModel: "The 3D model did not contain visible furniture."
        case .rendererUnavailable: "The 3D room is still preparing. Please try again in a moment."
        }
    }
}
