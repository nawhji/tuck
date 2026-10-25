import SwiftUI
import WebKit

struct RoomStageView: View {
    let hasScannedSpace: Bool
    let onScanTap: () -> Void
    var onViewScan: (() -> Void)? = nil

    var body: some View {
        if hasScannedSpace {
            VStack(spacing: 4) {
                DemoRoomPreview()
                    .frame(width: min(UIScreen.main.bounds.width - 24, 480), height: 310)
                    .accessibilityLabel("Demo room. Drag to rotate and move furniture.")
                if let onViewScan {
                    Button("View measurements", action: onViewScan)
                        .font(.caption.weight(.medium))
                }
            }
        } else {
            Button(action: onScanTap) {
                VStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 46, weight: .ultraLight))
                    Text("Scan your space to start")
                        .font(.callout.weight(.medium))
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

/// Offline WebGL asset: same room and independent furniture as the HTML demo.
private struct DemoRoomPreview: View {
    @State private var failed = false

    var body: some View {
        ZStack {
            if failed {
                VStack(spacing: 4) {
                    DemoRoomThumbnail()
                    Text("3D preview unavailable on this device")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                DemoRoomWebView { failed = true }
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
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "previewError")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .white
        view.scrollView.backgroundColor = .white
        view.scrollView.isScrollEnabled = false
        view.allowsLinkPreview = false
        guard let url = Bundle.main.url(forResource: "DemoRoom", withExtension: "html") else {
            DispatchQueue.main.async(execute: onFailure)
            return view
        }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "previewError")
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onFailure: () -> Void
        init(onFailure: @escaping () -> Void) { self.onFailure = onFailure }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            onFailure()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFailure() }
    }
}

#Preview("Empty") { RoomStageView(hasScannedSpace: false) {} }
#Preview("Scanned") { RoomStageView(hasScannedSpace: true) {} }
