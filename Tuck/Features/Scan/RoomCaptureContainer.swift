import RoomPlan
import OSLog
import SwiftUI
import UIKit

@MainActor
struct RoomCaptureContainer: UIViewControllerRepresentable {
    let scanner: RoomScanner

    func makeCoordinator() -> Coordinator {
        Coordinator(scanner: scanner, token: scanner.scanID)
    }

    func makeUIViewController(context: Context) -> CaptureController {
        let controller = CaptureController()
        controller.captureView.isModelEnabled = false
        controller.captureView.delegate = context.coordinator
        // RoomCaptureView owns its session's live visualization callbacks.
        // App-level processed results use captureView.delegate only.
        controller.onAppear = { [weak scanner] view in scanner?.attach(view) }
        return controller
    }

    func updateUIViewController(_ uiViewController: CaptureController, context: Context) {}

    static func dismantleUIViewController(_ controller: CaptureController, coordinator: Coordinator) {
        controller.onAppear = nil
        controller.stopDiagnostics()
        controller.captureView.delegate = nil
        coordinator.detach(controller.captureView)
    }

    /// A SwiftUI appearance alone doesn't guarantee a window and nonzero bounds.
    final class CaptureController: UIViewController {
        let captureView = RoomCaptureView(frame: .zero)
        var onAppear: ((RoomCaptureView) -> Void)?
        private var didStart = false
        private var isVisible = false
        private var frameCheck: Timer?
        private var frameChecks = 0

        override func loadView() { view = captureView }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
            startWhenReady()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            startWhenReady()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isVisible = false
            stopDiagnostics()
        }

        private func startWhenReady() {
            guard isVisible, !didStart, captureView.window != nil,
                  captureView.bounds.width > 0, captureView.bounds.height > 0,
                  let onAppear else { return }
            didStart = true
            RoomScanDiagnostics.log.info("Capture view ready: \(self.captureView.bounds.width)x\(self.captureView.bounds.height)")
            onAppear(captureView)
            // Inspect currentFrame without replacing RoomPlan's AR/session delegates.
            frameCheck = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFirstFrame() }
            }
        }

        private func checkFirstFrame() {
            frameChecks += 1
            if let frame = captureView.captureSession.arSession.currentFrame {
                RoomScanDiagnostics.log.info("First AR camera frame received. Tracking: \(String(describing: frame.camera.trackingState), privacy: .public)")
                stopDiagnostics()
            } else if frameChecks >= 10 {
                RoomScanDiagnostics.log.warning("No AR camera frame after 10 seconds. Check device logs.")
                stopDiagnostics()
            }
        }

        func stopDiagnostics() {
            frameCheck?.invalidate()
            frameCheck = nil
        }
    }

    @MainActor
    @objc(TuckRoomCaptureCoordinator)
    final class Coordinator: NSObject, RoomCaptureViewDelegate {
        private weak var scanner: RoomScanner?
        private let token: UUID

        init(scanner: RoomScanner, token: UUID) {
            self.scanner = scanner
            self.token = token
        }

        // RoomCaptureViewDelegate inherits NSCoding. The coordinator isn't archived.
        nonisolated func encode(with coder: NSCoder) {}

        nonisolated required init?(coder: NSCoder) { return nil }

        // RoomPlan may invoke delegates off the main thread. Move state changes
        // to MainActor, and reject callbacks from a previous scan using token.
        nonisolated func captureView(
            shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?
        ) -> Bool {
            if let error {
                report(error.localizedDescription)
                return false
            }
            RoomScanDiagnostics.log.info("RoomPlan raw scan received; requesting processed result.")
            return true
        }

        nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
            if let error {
                report(error.localizedDescription)
                return
            }
            RoomScanDiagnostics.log.info("RoomPlan processed result: \(processedResult.walls.count) walls, \(processedResult.objects.count) objects")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanner?.receive(processedResult, token: self.token)
            }
        }

        func detach(_ view: RoomCaptureView) {
            scanner?.detach(view)
        }

        private nonisolated func report(_ message: String) {
            RoomScanDiagnostics.log.error("RoomPlan capture error: \(message, privacy: .public)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanner?.fail(message, token: self.token)
            }
        }
    }
}

/// Lifecycle events only; never logs images, room geometry, names or API keys.
enum RoomScanDiagnostics {
    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Tuck", category: "RoomScan")
}
