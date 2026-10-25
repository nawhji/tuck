import SwiftUI

/// A predictable local search path for the three prepared presentation chairs.
/// AI recommendation cards call the exact same Try/Remove action.
struct FurnitureSearchView: View {
    @ObservedObject var room: RoomPreviewController
    let onTry: (Product) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var catalog: ProductCatalog?
    @State private var loadError: String?
    @State private var confirmsReset = false

    private var products: [Product] {
        catalog.map { FurnitureCatalog.products(matching: query, catalog: $0) } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("Three 3D-ready chairs. Search by name, brand, color, or material.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 24)
                    if !room.isReady {
                        HStack { ProgressView(); Text(room.isRestoring ? "Restoring your furniture…" : "Preparing the 3D room…") }
                            .font(.caption).padding(.horizontal, 24)
                    }
                    if let loadError {
                        Text(loadError).foregroundStyle(.red).padding(.horizontal, 24)
                    } else if products.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    ForEach(products) { product in
                        ProductCardView(product: product, isSelected: room.placedProductIDs.contains(product.id),
                            onToggle: { onTry(product) }, isLoading: room.loadingProductIDs.contains(product.id),
                            canTry: room.isReady)
                    }
                    Text("Drag furniture to move it. Tap a name to select it, rename it, rotate it, or remove it.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
                    Button("Reset current room", role: .destructive) { confirmsReset = true }
                        .disabled(!room.isReady || !room.loadingProductIDs.isEmpty)
                        .font(.caption).padding(.horizontal, 24).padding(.vertical, 12)
                }
                .padding(.vertical, 16)
            }
            .background(Color("TuckCream"))
            .navigationTitle("Find a chair")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Otio, Goda, Peacemaker…")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do { catalog = try ProductCatalog() }
                catch { loadError = "The product catalog could not be opened." }
            }
            .alert("Furniture", isPresented: Binding(get: { room.errorMessage != nil },
                set: { if !$0 { room.errorMessage = nil } })) {
                Button("OK", role: .cancel) { room.errorMessage = nil }
            } message: { Text(room.errorMessage ?? "") }
            .confirmationDialog("Reset furniture in this room?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset room", role: .destructive) { room.resetRoom() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This resets furniture positions, names, and removals, including chairs you tried.") }
        }
    }
}
