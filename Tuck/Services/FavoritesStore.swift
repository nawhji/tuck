import Foundation
import Observation

/// One shared list for chat cards and profile. A write must succeed before UI changes.
@Observable
final class FavoritesStore {
    private(set) var products: [Product] = []
    var errorMessage: String?
    private let fileURL: URL
    private var canWrite = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("saved-furniture.json")
        reload()
    }

    func contains(_ id: String) -> Bool { products.contains { $0.id == id } }

    func reload() {
        do {
            let loaded: [Product]
            if FileManager.default.fileExists(atPath: fileURL.path) {
                loaded = try JSONDecoder().decode([Product].self, from: Data(contentsOf: fileURL))
            } else {
                loaded = []
            }
            var ids = Set<String>()
            products = loaded.filter { ids.insert($0.id).inserted }
            canWrite = true
            errorMessage = nil
        } catch {
            canWrite = false
            errorMessage = "Your saved furniture couldn't be loaded. Your existing file has been kept."
        }
    }

    @discardableResult
    func toggle(_ product: Product) -> Bool {
        guard canWrite else {
            errorMessage = "Your saved furniture couldn't be loaded. Please try reopening the app."
            return false
        }
        var updated = products
        if contains(product.id) { updated.removeAll { $0.id == product.id } }
        else { updated.insert(product, at: 0) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
            products = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Couldn't save that change. Please try again."
            return false
        }
    }
}
