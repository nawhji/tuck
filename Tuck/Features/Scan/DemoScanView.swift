import AVFoundation
import RoomPlan
import SwiftUI

/// Figma scan flow. The finish destination is always the bundled demo room.
@MainActor
struct DemoScanView: View {
    let onFinish: () -> Void
    let onCancel: () -> Void
    @StateObject private var scanner = RoomScanner()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var cameraAllowed = false
    @State private var cameraActive = true
    @State private var cameraMessage: String?
    @State private var progress: CGFloat = 0.04
    @State private var isFinishing = false
    @State private var finishTask: Task<Void, Never>?

    private var supportsLiDAR: Bool { RoomCaptureSession.isSupported }
    private let brown = Color(red: 0.29, green: 0.208, blue: 0.169)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            camera
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 10) {
                    if !supportsLiDAR {
                        Text("⚠️ LiDAR scanning is not supported on this device.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    if let cameraMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cameraMessage).font(.caption).foregroundStyle(.white.opacity(0.8))
                            if !cameraAllowed, let settings = URL(string: UIApplication.openSettingsURLString) {
                                Button("Open Settings") { openURL(settings) }
                                    .font(.caption.weight(.medium)).foregroundStyle(.white)
                            }
                        }
                    } else if scanner.phase == .failed {
                        Text("Room scanning is unavailable. You can still open the demo room.")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
                scanPanel
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .task { await startCamera() }
        .task {
            // Presentation activity only, deliberately not a measured coverage percentage.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard !isFinishing, scenePhase == .active else { continue }
                withAnimation(.linear(duration: 0.18)) {
                    progress += (0.92 - progress) * 0.022
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                guard !isFinishing else { return }
                Task { await startCamera() }
            } else {
                cameraActive = false
                scanner.stop()
            }
        }
        .onDisappear {
            cameraActive = false
            finishTask?.cancel()
            scanner.stop()
        }
    }

    @ViewBuilder private var camera: some View {
        if cameraAllowed && cameraActive {
            if supportsLiDAR && scanner.showsCapture {
                RoomCaptureContainer(scanner: scanner).id(scanner.scanID)
            } else if !supportsLiDAR || scanner.phase == .failed {
                PlainCameraPreview { cameraMessage = $0 }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                finishTask?.cancel()
                scanner.stop()
                cameraActive = false
                onCancel()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.15), in: Circle())
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Cancel scan")
            .disabled(isFinishing)
            Spacer(minLength: 0)
            Text("Move slowly to scan your space")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(brown)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.white, in: Capsule())
            Spacer(minLength: 0)
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var scanPanel: some View {
        VStack(spacing: 17) {
            Capsule().fill(Color.black.opacity(0.10)).frame(width: 34, height: 4)
            Text(isFinishing ? "Opening your demo room…" : "Scanning the room…")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.09))
                    Capsule().fill(brown).frame(width: max(6, proxy.size.width * progress))
                }
            }
            .frame(height: 4)
            .accessibilityLabel("Scan in progress")
            Button(action: finish) {
                HStack(spacing: 8) {
                    if isFinishing { ProgressView().tint(.white) }
                    Text(isFinishing ? "Opening…" : "Finish scan").font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 46)
                .foregroundStyle(.white).background(brown, in: Capsule())
            }
            .disabled(isFinishing)
            Text("A demo room opens after scanning.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 18)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25))
    }

    private func startCamera() async {
        guard !isFinishing, scenePhase == .active else { return }
        let permitted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permitted = true
        case .notDetermined: permitted = await AVCaptureDevice.requestAccess(for: .video)
        default: permitted = false
        }
        guard !Task.isCancelled, !isFinishing else { return }
        cameraAllowed = permitted
        cameraActive = scenePhase == .active
        guard permitted else {
            cameraMessage = "Camera access is off. You can still finish and open the demo room."
            return
        }
        cameraMessage = nil
        if supportsLiDAR { await scanner.start() }
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeOut(duration: 0.25)) { progress = 1 }
        scanner.stop()
        finishTask = Task {
            // Give real RoomPlan a bounded opportunity to finish; never block the demo on it.
            if supportsLiDAR {
                for _ in 0..<25 {
                    if scanner.phase == .ready || scanner.phase == .failed { break }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            } else {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            cameraActive = false
            onFinish()
        }
    }
}

/// Regular camera preview for devices without RoomPlan / LiDAR. No recording or audio.
private struct PlainCameraPreview: UIViewRepresentable {
    let onError: (String) -> Void

    func makeUIView(context: Context) -> PlainCameraView {
        let view = PlainCameraView()
        view.onError = onError
        view.start()
        return view
    }
    func updateUIView(_ uiView: PlainCameraView, context: Context) {}
    static func dismantleUIView(_ uiView: PlainCameraView, coordinator: Void) { uiView.stop() }
}

private final class PlainCameraView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "tuck.demo.camera", qos: .userInitiated)
    var onError: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preview.videoGravity = .resizeAspectFill
        preview.session = session
    }
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    func start() {
        let session = session
        let report = onError
        queue.async {
            session.beginConfiguration()
            session.sessionPreset = .high
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { report?("Camera is unavailable. You can still open the demo room.") }
                    return
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { report?("Camera could not start. You can still open the demo room.") }
                    return
                }
                session.addInput(input)
                session.commitConfiguration()
                session.startRunning()
            } catch {
                session.commitConfiguration()
                DispatchQueue.main.async { report?("Camera could not start. You can still open the demo room.") }
            }
        }
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
}
