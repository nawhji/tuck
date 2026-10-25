import SwiftUI

struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var showsSavedRoom = false
    @State private var favorites = FavoritesStore()
    @StateObject private var preview = RoomPreviewController()
    @GestureState private var dragOffset: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    @State private var moveEnabled = false
    @State private var moveNotice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var showLeaveDialog = false
    @State private var showNewRoomName = false
    @State private var showExistingRooms = false
    @State private var existingRooms: [RoomLibraryEntry] = []
    @State private var roomName = ""
    @State private var saveError: String?
    @State private var isSavingRoom = false
    @State private var isLoadingRooms = false

    init(model: HomeViewModel = HomeViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.white.ignoresSafeArea()
                stage(in: geometry)
                sheetLayer(in: geometry)
            }
        }
        .animation(.spring(duration: 0.35), value: isInputFocused)
        .preferredColorScheme(.light)
        .environment(favorites)
        .sheet(isPresented: $model.isProfilePresented) {
            ProfileView(name: model.userName, initial: model.userInitial, favorites: favorites, onOpenRoom: { entry in
                moveEnabled = false
                preview.setMoveEnabled(false)
                model.openSavedRoom(entry)
            })
        }
        .onChange(of: model.isProfilePresented) { _, presented in
            if presented { isInputFocused = false }
        }
        .task { await model.prepareLibrary() }
        .sheet(isPresented: $showsSavedRoom) {
            if let scan = model.savedScan { SavedRoomView(scan: scan) }
        }
        .sheet(isPresented: $showExistingRooms) {
            existingRoomPicker
        }
        .confirmationDialog("Save this room?", isPresented: $showLeaveDialog, titleVisibility: .visible) {
            if !existingRooms.isEmpty {
                Button("Save to existing room") { showExistingRooms = true }
            }
            Button("Save as new room") {
                roomName = ""
                showNewRoomName = true
            }
            Button("Delete current room", role: .destructive) { leaveRoom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save your layout before leaving. Deleting the current room keeps previously saved rooms.")
        }
        .alert("Save new room", isPresented: $showNewRoomName) {
            TextField("Room name", text: $roomName)
            Button("Save") { saveRoom(existingID: nil) }
                .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomName.count > 60)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Give your room a name.") }
        .alert("Tuck", isPresented: Binding(
            get: { !model.isProfilePresented && !model.isPresentingScan && !showsSavedRoom && !showExistingRooms &&
                (saveError != nil || model.scanLoadError != nil || favorites.errorMessage != nil) },
            set: { if !$0 { saveError = nil; model.scanLoadError = nil; favorites.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil; model.scanLoadError = nil; favorites.errorMessage = nil }
        } message: { Text(saveError ?? model.scanLoadError ?? favorites.errorMessage ?? "") }
        .fullScreenCover(isPresented: $model.isPresentingScan) {
            DemoScanView(
                onFinish: { scan in
                    moveEnabled = false
                    model.finishScan(scan)
                },
                onCancel: { model.isPresentingScan = false }
            )
        }
        .onChange(of: model.isPresentingScan) { _, presented in
            if presented { isInputFocused = false }
        }
        .onChange(of: isInputFocused) { _, focused in
            if focused { model.sheetDetent = .expanded }
        }
        .onDisappear { noticeTask?.cancel() }
    }

    private func height(in geometry: GeometryProxy) -> CGFloat {
        let detent: SheetDetent = isInputFocused ? .expanded : model.sheetDetent
        let base = CGFloat(HomeSheetLayout.height(detent, availableHeight: Double(geometry.size.height)))
        let maximum = CGFloat(HomeSheetLayout.height(.expanded, availableHeight: Double(geometry.size.height)))
        return min(max(base - dragOffset, CGFloat(HomeSheetLayout.minimizedHeight)), maximum)
    }

    private func stage(in geometry: GeometryProxy) -> some View {
        let sheetHeight = height(in: geometry)
        let collapsed = CGFloat(HomeSheetLayout.height(.collapsed, availableHeight: Double(geometry.size.height)))
        let expansion = min(max((collapsed - sheetHeight) / max(collapsed - CGFloat(HomeSheetLayout.minimizedHeight), 1), 0), 1)
        let top = CGFloat(model.hasScannedSpace ? 84 : 55) * (1 - expansion) - geometry.safeAreaInsets.top * expansion
        let bottom = (geometry.size.height - sheetHeight - 54) * (1 - expansion) + (geometry.size.height + geometry.safeAreaInsets.bottom) * expansion
        let viewport = CGSize(width: geometry.size.width, height: max(160, bottom - top))
        return ZStack(alignment: .topLeading) {
            RoomStageView(hasScannedSpace: model.hasScannedSpace,
                          onScanTap: model.startScan,
                          onViewScan: model.savedScan == nil ? nil : { showsSavedRoom = true },
                          viewportSize: viewport,
                          previewController: preview,
                          moveEnabled: moveEnabled,
                          initialLayout: model.activeLayout,
                          scannedRoom: model.activeLayout == nil ? model.savedScan?.document : model.activeLayout?.scannedRoom)
                .id(model.sceneID)
                .frame(width: viewport.width, height: viewport.height)
                .position(x: geometry.size.width / 2, y: top + viewport.height / 2)
            HomeHeader(initial: model.userInitial, onAvatarTap: model.openProfile)
                .padding(.top, 8)
            if model.hasScannedSpace {
                Button(action: prepareToLeave) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.body)
                    .foregroundStyle(Color("TuckBrown"))
                    .padding(.vertical, 8)
                }
                .disabled(isSavingRoom || isLoadingRooms)
                .padding(.leading, 19).padding(.top, 49)
                .accessibilityLabel("Back. Save or delete the current room.")
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func sheetLayer(in geometry: GeometryProxy) -> some View {
        let sheetHeight = height(in: geometry)
        let collapsed = CGFloat(HomeSheetLayout.height(.collapsed, availableHeight: Double(geometry.size.height)))
        let toolsVisible = !isInputFocused && sheetHeight <= collapsed + 16
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                if let moveNotice {
                    Text(moveNotice)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .background(Color("TuckBrown").opacity(0.94), in: Capsule())
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .allowsHitTesting(false)
                }
                HStack(spacing: 10) {
                    if model.hasScannedSpace { moveButton }
                    cameraButton
                }
            }
            .padding(.trailing, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(toolsVisible ? 1 : 0)
            .allowsHitTesting(toolsVisible)
            ChatSheet(
                title: model.sheetTitle, messages: model.messages,
                selectedProductID: model.selectedProductID, draft: $model.draft,
                isInputFocused: $isInputFocused, canSend: model.canSend,
                dragGesture: sheetDrag(availableHeight: geometry.size.height),
                onSend: model.send, onImage: model.attachImage, onSelect: model.toggleSelection,
                isMinimized: sheetHeight < 90,
                onExpand: { withAnimation(.spring(duration: 0.35)) { model.sheetDetent = .collapsed } }
            )
            .frame(height: sheetHeight)
        }
    }

    private var cameraButton: some View {
        Button(action: model.startScan) {
            Image(systemName: "camera")
                .font(.system(size: 20)).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color(.systemGray3), in: Circle())
        }
        .accessibilityLabel("Scan space")
    }

    private var moveButton: some View {
        Button(action: toggleMoveMode) {
            Image("FurnitureMove")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 21, height: 21)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(moveEnabled ? Color("TuckBrown") : Color(.systemGray3), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if moveEnabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color("TuckBrown"))
                            .frame(width: 14, height: 14)
                            .background(.white, in: Circle())
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .accessibilityLabel("Furniture move mode")
        .accessibilityValue(moveEnabled ? "On" : "Off")
    }

    private func toggleMoveMode() {
        moveEnabled.toggle()
        preview.setMoveEnabled(moveEnabled)
        noticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            moveNotice = "Furniture move mode " + (moveEnabled ? "on" : "off")
        }
        UISelectionFeedbackGenerator().selectionChanged()
        noticeTask = Task {
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { moveNotice = nil }
        }
    }

    private func sheetDrag(availableHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragOffset) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let detent: SheetDetent = isInputFocused ? .expanded : model.sheetDetent
                let current = CGFloat(HomeSheetLayout.height(detent, availableHeight: Double(availableHeight))) - value.translation.height
                let projected = current - (value.predictedEndTranslation.height - value.translation.height) * 0.3
                let target = HomeSheetLayout.nearest(projectedHeight: Double(projected), availableHeight: Double(availableHeight))
                withAnimation(.spring(duration: 0.35)) { model.sheetDetent = target }
                if target != .expanded { isInputFocused = false }
            }
    }

    private func prepareToLeave() {
        guard !isLoadingRooms, !isSavingRoom else { return }
        isInputFocused = false
        isLoadingRooms = true
        Task {
            defer { isLoadingRooms = false }
            do {
                existingRooms = try await Task.detached(priority: .userInitiated) { try RoomLibraryStore.all() }.value
                showLeaveDialog = true
            } catch { saveError = error.localizedDescription }
        }
    }

    private var existingRoomPicker: some View {
        NavigationStack {
            List(existingRooms) { entry in
                Button { saveRoom(existingID: entry.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.name).foregroundStyle(.primary)
                        Text(entry.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
                .disabled(isSavingRoom)
            }
            .overlay { if isSavingRoom { ProgressView("Saving room…") } }
            .navigationTitle("Save to existing room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showExistingRooms = false }.disabled(isSavingRoom) } }
        }
    }

    private func saveRoom(existingID: String?) {
        guard !isSavingRoom else { return }
        isSavingRoom = true
        Task {
            defer { isSavingRoom = false }
            do {
                let layout = try await preview.snapshot()
                let name = roomName
                try await Task.detached(priority: .userInitiated) {
                    if let existingID { try RoomLibraryStore.saveExisting(id: existingID, layout: layout) }
                    else { _ = try RoomLibraryStore.saveNew(name: name, layout: layout) }
                }.value
                showExistingRooms = false
                leaveRoom()
            } catch {
                showExistingRooms = false
                saveError = error.localizedDescription
            }
        }
    }

    private func leaveRoom() {
        noticeTask?.cancel()
        moveNotice = nil
        moveEnabled = false
        preview.setMoveEnabled(false)
        model.removeCurrentRoom()
    }
}

#if DEBUG
#Preview("Default") { HomeView(model: .preview(.empty)) }
#Preview("Scanned") { HomeView(model: .preview(.scanned)) }
#endif
