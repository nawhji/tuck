import SwiftUI

struct HomeView: View {
    @State private var model: HomeViewModel
    @State private var showsSavedRoom = false
    @State private var favorites = FavoritesStore()
    @GestureState private var dragOffset: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    private static let collapsedFraction: CGFloat = 0.36
    private static let expandedFraction: CGFloat = 2.0 / 3.0

    init(model: HomeViewModel = HomeViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            stage
            sheetLayer
        }
        .animation(.spring(duration: 0.35), value: isInputFocused)
        .preferredColorScheme(.light)
        .environment(favorites)
        .sheet(isPresented: $model.isProfilePresented) {
            ProfileView(name: model.userName, initial: model.userInitial, favorites: favorites)
        }
        .onChange(of: model.isProfilePresented) { _, presented in
            if presented { isInputFocused = false }
        }
        .task { await model.restoreLatestScan() }
        .sheet(isPresented: $showsSavedRoom) {
            if let scan = model.savedScan { SavedRoomView(scan: scan) }
        }
        .alert("Tuck", isPresented: Binding(
            get: { !model.isProfilePresented && !model.isPresentingScan && !showsSavedRoom &&
                (model.scanLoadError != nil || favorites.errorMessage != nil) },
            set: { if !$0 { model.scanLoadError = nil; favorites.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.scanLoadError = nil; favorites.errorMessage = nil }
        } message: { Text(model.scanLoadError ?? favorites.errorMessage ?? "") }
        .fullScreenCover(isPresented: $model.isPresentingScan) {
            DemoScanView(
                onFinish: { scan in
                    if let scan { model.acceptScan(document: scan.document, files: scan.files) }
                    model.finishDemoScan()
                },
                onCancel: { model.isPresentingScan = false }
            )
        }
        .onChange(of: model.isPresentingScan) { _, presented in
            if presented { isInputFocused = false }
        }
    }

    /// 방 영역과 헤더. 키보드가 올라와도 움직이지 않는다.
    private var stage: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                RoomStageView(hasScannedSpace: model.hasScannedSpace, onScanTap: model.startScan, onViewScan: model.savedScan == nil ? nil : { showsSavedRoom = true })
                    .position(x: proxy.size.width / 2, y: stageCenterY(safeTop: proxy.safeAreaInsets.top))
                HomeHeader(initial: model.userInitial, onAvatarTap: model.openProfile)
                    .padding(.top, max(proxy.safeAreaInsets.top + 2, 0))
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.keyboard)
    }

    /// 헤더 하단과 접힌 시트 상단 사이의 정중앙.
    private func stageCenterY(safeTop: CGFloat) -> CGFloat {
        let headerBottom = max(safeTop + 2, 0) + 35
        let sheetTop = UIScreen.main.bounds.height * (1 - Self.collapsedFraction)
        return (headerBottom + sheetTop) / 2
    }

    /// 화면 하단에 붙은 시트. 키보드가 올라오면 입력창과 함께 밀려 올라간다.
    private var sheetLayer: some View {
        GeometryReader { proxy in
            let screen = UIScreen.main.bounds.height
            let height = min(sheetHeight(screen: screen), proxy.size.height - 56)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                cameraButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                    .opacity(isCollapsedLook(screen: screen) ? 1 : 0)
                ChatSheet(
                    title: model.sheetTitle,
                    messages: model.messages,
                    selectedProductID: model.selectedProductID,
                    draft: $model.draft,
                    isInputFocused: $isInputFocused,
                    canSend: model.canSend,
                    dragGesture: sheetDrag(screen: screen),
                    onSend: model.send,
                    onImage: model.attachImage,
                    onSelect: model.toggleSelection
                )
                .frame(height: height)
            }
        }
    }

    private var cameraButton: some View {
        Button(action: model.startScan) {
            Image(systemName: "camera")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color(.systemGray3), in: .circle)
        }
        .accessibilityLabel("Scan space")
    }

    // MARK: - Sheet geometry

    private func detentHeight(_ detent: SheetDetent, screen: CGFloat) -> CGFloat {
        screen * (detent == .collapsed ? Self.collapsedFraction : Self.expandedFraction)
    }

    /// 드래그 중에는 손가락을 따라, 아니면 현재 detent 높이. 위로 끌면(translation < 0) 높아진다.
    private func sheetHeight(screen: CGFloat) -> CGFloat {
        // 입력 중에는 상태를 바꾸지 않고 높이만 펼친다. (포커스 도중 상태를 바꾸면 포커스를 잃는다)
        let detent: SheetDetent = isInputFocused ? .expanded : model.sheetDetent
        let base = detentHeight(detent, screen: screen) - dragOffset
        return min(max(base, detentHeight(.collapsed, screen: screen)), detentHeight(.expanded, screen: screen))
    }

    private func isCollapsedLook(screen: CGFloat) -> Bool {
        model.sheetDetent == .collapsed && dragOffset == 0 && !isInputFocused
    }

    private func sheetDrag(screen: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragOffset) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                settle(translation: value.translation.height, predicted: value.predictedEndTranslation.height, screen: screen)
            }
    }

    private func settle(translation: CGFloat, predicted: CGFloat, screen: CGFloat) {
        let detent: SheetDetent = isInputFocused ? .expanded : model.sheetDetent
        let current = detentHeight(detent, screen: screen) - translation
        let projected = current - (predicted - translation) * 0.3
        let midpoint = (detentHeight(.collapsed, screen: screen) + detentHeight(.expanded, screen: screen)) / 2
        let target: SheetDetent = projected > midpoint ? .expanded : .collapsed
        withAnimation(.spring(duration: 0.35)) {
            model.sheetDetent = target
        }
        if target == .collapsed { isInputFocused = false }
    }
}

#if DEBUG
#Preview("Default") { HomeView(model: .preview(.empty)) }
#Preview("Scanned") { HomeView(model: .preview(.scanned)) }
#Preview("Asking") { HomeView(model: .preview(.asking)) }
#Preview("Answer") { HomeView(model: .preview(.answer)) }
#Preview("Simulation") { HomeView(model: .preview(.simulation)) }
#endif
