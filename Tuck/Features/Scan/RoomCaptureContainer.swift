import RoomPlan
import SwiftUI

@MainActor
struct RoomCaptureContainer: UIViewRepresentable {
    let scanner: RoomScanner

    func makeCoordinator() -> Coordinator {
        Coordinator(scanner: scanner, token: scanner.scanID)
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.isModelEnabled = true
        view.delegate = context.coordinator
        view.captureSession.delegate = context.coordinator
        scanner.attach(view)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Coordinator) {
        uiView.delegate = nil
        uiView.captureSession.delegate = nil
        uiView.captureSession.stop(pauseARSession: true)
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

        nonisolated required init?(coder: NSCoder) { nil }

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
