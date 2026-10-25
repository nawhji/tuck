import SwiftUI
import WebKit

struct RoomStageView: View {
    let hasScannedSpace: Bool
    let onScanTap: () -> Void
    var onViewScan: (() -> Void)? = nil
    var viewportSize: CGSize? = nil
    var previewController: RoomPreviewController? = nil
    var moveEnabled = false
    var inchesEnabled = false
    var dimensionInsets = EdgeInsets()
    var initialLayout: RoomLayoutSnapshot? = nil
    var scannedRoom: RoomDocument? = nil
    @StateObject private var fallbackController = RoomPreviewController()

    var body: some View {
        if hasScannedSpace {
            ZStack(alignment: .bottom) {
                DemoRoomPreview(controller: previewController ?? fallbackController,
                                initialLayout: initialLayout, moveEnabled: moveEnabled, inchesEnabled: inchesEnabled, dimensionInsets: dimensionInsets, scannedRoom: scannedRoom)
                    .accessibilityLabel(moveEnabled ? "Room. Drag furniture to move along one axis." : "Room. Drag to rotate. Pinch to zoom.")
                if let onViewScan {
                    Button("View measurements", action: onViewScan)
                        .font(.caption.weight(.medium)).padding(8)
                }
            }
            .frame(width: viewportSize?.width, height: viewportSize?.height ?? 310)
        } else {
            Button(action: onScanTap) {
                VStack(spacing: 14) {
                    Image(systemName: "plus").font(.system(size: 46, weight: .ultraLight))
                    Text("Scan your space to start").font(.callout.weight(.medium))
                }
                .foregroundStyle(Color("GrayScale300"))
                .frame(width: 250, height: 250)
                .contentShape(Circle())
                .overlay {
                    Circle().stroke(Color("GrayScale300"), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 4]))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DemoRoomPreview: View {
    let controller: RoomPreviewController
    let initialLayout: RoomLayoutSnapshot?
    let moveEnabled: Bool
    let inchesEnabled: Bool
    let dimensionInsets: EdgeInsets
    let scannedRoom: RoomDocument?
    @State private var failed = false
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if failed {
                VStack(spacing: 4) {
                    if scannedRoom == nil && initialLayout?.scannedRoom == nil { DemoRoomThumbnail() }
                    Text("3D preview unavailable on this device")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                DemoRoomWebView(controller: controller, initialLayout: initialLayout,
                                moveEnabled: moveEnabled, inchesEnabled: inchesEnabled, dimensionInsets: dimensionInsets, scannedRoom: scannedRoom,
                                onReady: { isLoading = false }, onFailure: { failed = true })
                    .opacity(isLoading ? 0 : 1)
                    .allowsHitTesting(!isLoading)
                if isLoading { ProgressView("Loading room…") }
            }
        }
        .background(.white)
    }
}

struct DemoRoomThumbnail: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "DemoRoomPreview", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "cube.transparent").resizable().scaledToFit().padding(20)
        }
    }
}

private struct DemoRoomWebView: UIViewRepresentable {
    let controller: RoomPreviewController
    let initialLayout: RoomLayoutSnapshot?
    let moveEnabled: Bool
    let inchesEnabled: Bool
    let dimensionInsets: EdgeInsets
    let scannedRoom: RoomDocument?
    let onReady: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, onReady: onReady, onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "previewError")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .white
        view.scrollView.backgroundColor = .white
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsLinkPreview = false
        controller.attach(view, layout: initialLayout, moveEnabled: moveEnabled, scannedRoom: scannedRoom)
        controller.setDimensionOptions(enabled: inchesEnabled, insets: dimensionInsets)
        guard let url = Bundle.main.url(forResource: "DemoRoom", withExtension: "html") else {
            DispatchQueue.main.async(execute: onFailure)
            return view
        }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        controller.setMoveEnabled(moveEnabled)
        controller.setDimensionOptions(enabled: inchesEnabled, insets: dimensionInsets)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.controller.detach(uiView)
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "previewError")
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let controller: RoomPreviewController
        let onReady: () -> Void
        let onFailure: () -> Void
        init(controller: RoomPreviewController, onReady: @escaping () -> Void, onFailure: @escaping () -> Void) {
            self.controller = controller
            self.onReady = onReady
            self.onFailure = onFailure
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                do { try await controller.didLoad(webView); onReady() }
                catch { onFailure() }
            }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { onFailure() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFailure() }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onFailure() }
    }
}

#Preview("Empty") { RoomStageView(hasScannedSpace: false) {} }
#Preview("Scanned") { RoomStageView(hasScannedSpace: true) {} }
