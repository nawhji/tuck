import SwiftUI

struct ProfileView: View {
    let name: String
    let initial: String
    let favorites: FavoritesStore
    var onOpenRoom: ((RoomLibraryEntry) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Text(initial)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color("TuckBrown"), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(name).font(.title2.weight(.semibold))
                            Text("Make yourself at home.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .listRowBackground(Color.clear)
                Section {
                    NavigationLink {
                        ProfileRoomsView(onOpenRoom: onOpenRoom)
                    } label: {
                        profileRow("My rooms", icon: "cube", subtitle: "Your layouts, scans and measurements")
                    }
                    NavigationLink {
                        SavedFurnitureView(favorites: favorites)
                    } label: {
                        profileRow("Saved furniture", icon: "heart", subtitle: "\(favorites.products.count) saved")
                    }
                    NavigationLink {
                        ContentUnavailableView(
                            "No orders yet", systemImage: "shippingbox",
                            description: Text("Your completed orders will appear here.")
                        )
                        .navigationTitle("Orders")
                    } label: {
                        profileRow("Orders", icon: "shippingbox", subtitle: "Your purchase history")
                    }
                } footer: {
                    Text("Your rooms and saved furniture are stored on this iPhone.")
                        .padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("TuckCream"))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Color("TuckBrown"))
        .alert("Saved furniture", isPresented: Binding(
            get: { favorites.errorMessage != nil },
            set: { if !$0 { favorites.errorMessage = nil } }
        )) { Button("OK", role: .cancel) { favorites.errorMessage = nil } } message: { Text(favorites.errorMessage ?? "") }
    }

    private func profileRow(_ title: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 28).foregroundStyle(Color("TuckBrown"))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ProfileRoomsView: View {
    var onOpenRoom: ((RoomLibraryEntry) -> Void)? = nil
    @State private var rooms: [RoomLibraryEntry] = []
    @State private var selectedRoom: RoomLibraryEntry?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading rooms…")
            } else if let errorMessage {
                ContentUnavailableView("Couldn't load rooms", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else if rooms.isEmpty {
                ContentUnavailableView("No rooms yet", systemImage: "cube",
                                       description: Text("Scan a room using the camera button on Home."))
            } else {
                List(rooms) { room in
                    Button {
                        if let onOpenRoom { onOpenRoom(room) }
                        else { selectedRoom = room }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "cube").font(.title2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(room.name).font(.headline)
                                Text(room.updatedAt, style: .date).font(.caption)
                                if let layout = room.layout {
                                    Text("\(layout.items.count) furniture items").font(.caption).foregroundStyle(.secondary)
                                } else if let scan = room.scan {
                                    Text("\(scan.document.walls.count) walls · \(scan.document.objects.count) items")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("My rooms")
         .sheet(item: $selectedRoom) { room in
            if let layout = room.layout {
                SavedLayoutRoomView(room: room, layout: layout)
            } else if let scan = room.scan {
                SavedRoomView(scan: scan)
            }
        }
        .task {
            do {
                rooms = try await Task.detached(priority: .userInitiated) {
                    try RoomLibraryStore.ensureDemoRoom()
                    return try RoomLibraryStore.all()
                }.value
            } catch { errorMessage = "Your scans couldn't be read. The original files have been kept." }
            isLoading = false
        }
    }
}

private struct SavedLayoutRoomView: View {
    let room: RoomLibraryEntry
    let layout: RoomLayoutSnapshot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                RoomStageView(hasScannedSpace: true, onScanTap: {}, viewportSize: geometry.size,
                              initialLayout: layout)
            }
            .background(.white)
            .navigationTitle(room.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Color("TuckBrown"))
    }
}

private struct SavedFurnitureView: View {
    let favorites: FavoritesStore
    var body: some View {
        Group {
            if favorites.products.isEmpty {
                ContentUnavailableView("No saved furniture yet", systemImage: "heart",
                                       description: Text("Tap the heart on a furniture recommendation to save it here."))
            } else {
                List {
                    ForEach(favorites.products) { product in
                        NavigationLink {
                            SavedFurnitureDetail(product: product, favorites: favorites)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: product.imageURL)
                                    .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(product.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text(product.brand).font(.caption).foregroundStyle(.secondary)
                                    Text(product.price).font(.subheadline)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Unsave", role: .destructive) { favorites.toggle(product) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved furniture")
    }
}

private struct SavedFurnitureDetail: View {
    let product: Product
    let favorites: FavoritesStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RemoteImage(url: product.imageURL).frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                Text(product.brand).font(.subheadline).foregroundStyle(.secondary)
                Text(product.name).font(.title2.weight(.semibold))
                Text(product.price).font(.title3)
                Text(product.keywords.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption).foregroundStyle(.secondary)
                Button { favorites.toggle(product) } label: {
                    Label(favorites.contains(product.id) ? "Saved" : "Save furniture",
                          systemImage: favorites.contains(product.id) ? "heart.fill" : "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                if let url = product.sourceURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    Link(destination: url) {
                        Label("View product", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            .padding(24)
        }
        .navigationTitle("Furniture")
        .navigationBarTitleDisplayMode(.inline)
    }
}
