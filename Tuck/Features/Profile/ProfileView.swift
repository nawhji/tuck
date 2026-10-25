import SwiftUI

struct ProfileView: View {
    let name: String
    let initial: String
    let favorites: FavoritesStore
    let orders: OrderHistoryStore
    var onOpenRoom: ((RoomLibraryEntry) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 15) {
                    Text(initial)
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(Color("TuckBrown"), in: Circle())
                    Text(name)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.black)
                }
                .padding(.top, 16).padding(.bottom, 40)

                VStack(spacing: 0) {
                    menuRow("My Space") { ProfileRoomsView(onOpenRoom: onOpenRoom) }
                    menuRow("Saved") { SavedFurnitureView(favorites: favorites) }
                    menuRow("Order History") { OrderHistoryView(store: orders) }
                    menuRow("Payment Method") { PaymentMethodView() }
                    menuRow("Addresses") { AddressesView() }
                }
                .padding(.horizontal, 25)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Saved", isPresented: Binding(
            get: { favorites.errorMessage != nil },
            set: { if !$0 { favorites.errorMessage = nil } }
        )) { Button("OK", role: .cancel) { favorites.errorMessage = nil } } message: { Text(favorites.errorMessage ?? "") }
    }

    private func menuRow<Destination: View>(_ title: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                }
                .padding(.vertical, 18)
                Divider().overlay(Color(white: 0.9))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(rooms) { room in
                            Button {
                                if let onOpenRoom { onOpenRoom(room) }
                                else { selectedRoom = room }
                            } label: { RoomRow(room: room) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 19).padding(.vertical, 12)
                }
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .navigationTitle("My Space")
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
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(favorites.products) { product in
                            ProductCardView(product: product, isSelected: false)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .environment(favorites)
        .navigationTitle("Saved")
    }
}

private struct RoomRow: View {
    let room: RoomLibraryEntry

    private var summary: String {
        if let layout = room.layout { return "\(layout.items.count) furniture items" }
        if let scan = room.scan { return "\(scan.document.walls.count) walls · \(scan.document.objects.count) items" }
        return ""
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(room.name)
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.black).lineLimit(2)
                Text(room.updatedAt, format: .dateTime.year().month(.abbreviated).day())
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color("GrayScale300"))
                Text(summary)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color("TuckBrown"))
            }
            .padding(.leading, 16).padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            RoomStageView(hasScannedSpace: true, onScanTap: {}, viewportSize: CGSize(width: 150, height: 130),
                          initialLayout: room.layout,
                          scannedRoom: room.layout?.scannedRoom ?? room.scan?.document)
                .frame(width: 150, height: 130)
                .allowsHitTesting(false)
        }
        .frame(height: 130)
        .background(.white)
        .clipShape(.rect(cornerRadius: 30))
    }
}

private struct OrderHistoryView: View {
    let store: OrderHistoryStore

    var body: some View {
        Group {
            if store.orders.isEmpty {
                ContentUnavailableView("No orders yet", systemImage: "shippingbox",
                                       description: Text("Your confirmed orders will appear here."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(store.orders) { order in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(order.date, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color("GrayScale300"))
                                HStack(spacing: 14) {
                                    RemoteImage(url: order.imageURL.flatMap(URL.init(string:)))
                                        .frame(width: 84, height: 84)
                                        .clipShape(.rect(cornerRadius: 16))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(order.productName)
                                            .font(.system(size: 16, weight: .medium)).foregroundStyle(.black).lineLimit(2)
                                        Text(order.brand)
                                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color("TuckBrown"))
                                        Text(order.quantity > 1 ? "\(order.total) · Qty \(order.quantity)" : order.total)
                                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.black)
                                    }
                                    Spacer(minLength: 0)
                                }
                                Divider()
                                HStack {
                                    Label("Order confirmed", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color("TuckBrown"))
                                    Spacer()
                                    Text(order.address)
                                        .font(.system(size: 12)).foregroundStyle(Color("GrayScale300")).lineLimit(1)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: .rect(cornerRadius: 24))
                        }
                    }
                    .padding(.horizontal, 19).padding(.vertical, 12)
                }
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .navigationTitle("Order History")
    }
}

private struct PaymentMethodView: View {
    private let card = DemoProfile.card

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "creditcard").font(.system(size: 22, weight: .light))
                        Spacer()
                        Text(card.brand.uppercased())
                            .font(.system(size: 18, weight: .bold)).italic()
                    }
                    Spacer()
                    Text("••••  ••••  ••••  \(card.last4)")
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                    HStack {
                        Text(DemoProfile.current.name.uppercased())
                        Spacer()
                        Text("Test card")
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.2), in: .capsule)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, 14)
                }
                .foregroundStyle(.white)
                .padding(22)
                .frame(height: 190)
                .background(
                    LinearGradient(colors: [Color("TuckBrown"), Color("TuckBrown").opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 24))
                Text("Payments are processed by Stripe in test mode, so nothing is really charged.")
                    .font(.system(size: 12)).foregroundStyle(Color("GrayScale300"))
            }
            .padding(.horizontal, 19).padding(.vertical, 12)
        }
        .background(Color(.systemGray6).opacity(0.5))
        .navigationTitle("Payment Method")
    }
}

private struct AddressesView: View {
    private let address = DemoProfile.current.address

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(Color("TuckBrown"))
                    Text(DemoProfile.current.name)
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
                    Spacer()
                    Text("Default")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color("TuckBrown"))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color("TuckBrown").opacity(0.12), in: .capsule)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(address.line1)
                    if let line2 = address.line2, !line2.isEmpty { Text(line2) }
                    Text("\(address.city), \(address.state) \(address.postalCode)")
                    Text(address.country)
                }
                .font(.system(size: 14)).foregroundStyle(Color(white: 0.3))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 24))
            .padding(.horizontal, 19).padding(.vertical, 12)
        }
        .background(Color(.systemGray6).opacity(0.5))
        .navigationTitle("Addresses")
    }
}
