import RoomPlan
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
        controller.captureView.captureSession.delegate = context.coordinator
        controller.onAppear = { [weak scanner] view in scanner?.attach(view) }
        return controller
    }

    func updateUIViewController(_ uiViewController: CaptureController, context: Context) {}

    static func dismantleUIViewController(_ controller: CaptureController, coordinator: Coordinator) {
        controller.onAppear = nil
        controller.captureView.delegate = nil
        controller.captureView.captureSession.delegate = nil
        controller.captureView.captureSession.stop(pauseARSession: true)
    }

    /// Start only once the camera view has a window and a laid-out size.
    final class CaptureController: UIViewController {
        let captureView = RoomCaptureView(frame: .zero)
        var onAppear: ((RoomCaptureView) -> Void)?
        private var didStart = false

        override func loadView() { view = captureView }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didStart else { return }
            didStart = true
            onAppear?(captureView)
        }
    }

    @MainActor
    @objc(TuckRoomCaptureCoordinator)
    final class Coordinator: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
        private weak var scanner: RoomScanner?
        private let token: UUID

        init(scanner: RoomScanner, token: UUID) {
            self.scanner = scanner
            self.token = token
        }

        // The current RoomPlan SDK makes its delegate protocols NSCoding. The
        // coordinator is never archived, so these only satisfy the conformance.
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
            return true
        }

        nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
            if let error {
                report(error.localizedDescription)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanner?.receive(processedResult, token: self.token)
            }
        }

        nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            let walls = room.walls.count
            let objects = room.objects.count
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanner?.updateCounts(walls: walls, objects: objects, token: self.token)
            }
        }

        nonisolated func captureSession(
            _ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?
        ) {
            if let error { report(error.localizedDescription) }
            // Success is handled only by captureView(didPresent:error:).
        }

        private nonisolated func report(_ message: String) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanner?.fail(message, token: self.token)
            }
        }
    }
}
