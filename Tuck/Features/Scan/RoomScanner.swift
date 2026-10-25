import AVFoundation
import Combine
import Foundation
import RoomPlan

@MainActor
final class RoomScanner: ObservableObject {
    enum Phase: Equatable { case idle, permission, scanning, processing, ready, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var scanID = UUID()
    @Published private(set) var document: RoomDocument?
    @Published private(set) var files: ScanFiles?
    @Published private(set) var isSaving = false
    @Published private(set) var wallCount = 0
    @Published private(set) var objectCount = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var saveMessage: String?

    private weak var captureView: RoomCaptureView?
    private var captureNeedsStop = false
    private var capturedRoom: CapturedRoom?
    private var processingTimeout: Task<Void, Never>?

    var isSupported: Bool { RoomCaptureSession.isSupported }
    // Without LiDAR (Simulator, SwiftUI previews) there is no camera view to show.
    var showsCapture: Bool {
        isSupported && (phase == .scanning || phase == .processing || phase == .ready)
    }

    func start() async {
        guard isSupported, !isSaving, phase != .permission,
              phase != .scanning, phase != .processing else { return }
        releaseCapture()
        scanID = UUID()
        let requestID = scanID
        phase = .permission
        errorMessage = nil
        saveMessage = nil

        let permitted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permitted = true
        case .notDetermined:
            permitted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            permitted = false
        }
        guard requestID == scanID, phase == .permission else { return }
        guard permitted else {
            errorMessage = "Camera access is required. Enable it in Settings."
            phase = .failed
            return
        }

        document = nil
        files = nil
        capturedRoom = nil
        wallCount = 0
        objectCount = 0
        scanID = UUID()
        phase = .scanning
        // RoomCaptureContainer creates the view and starts its session.
    }

    func attach(_ view: RoomCaptureView) {
        guard phase == .scanning, captureView == nil else { return }
        captureView = view
        captureNeedsStop = true
        RoomScanDiagnostics.log.info("Starting RoomPlan capture session.")
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        RoomScanDiagnostics.log.info("RoomPlan captureSession.run returned.")
    }

    func stop() {
        guard phase == .scanning, captureNeedsStop, let captureView else { return }
        captureNeedsStop = false
        phase = .processing
        RoomScanDiagnostics.log.info("Stopping RoomPlan for processing.")
        // Keep the UIView mounted until didPresent delivers the processed room.
        captureView.captureSession.stop(pauseARSession: true)
        let token = scanID
        processingTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, self.phase == .processing else { return }
            self.fail("Room processing timed out. Please scan again.", token: token)
        }
    }

    /// Invalidate permission requests and late RoomPlan callbacks before stopping.
    func cancel() {
        scanID = UUID()
        processingTimeout?.cancel()
        processingTimeout = nil
        releaseCapture()
        isSaving = false
        phase = .idle
    }

    /// Stop a mounted view once without overwriting RoomCaptureView's internal delegate.
    func detach(_ view: RoomCaptureView) {
        guard captureView === view else { return }
        releaseCapture()
    }

    private func releaseCapture() {
        guard let view = captureView else { captureNeedsStop = false; return }
        captureView = nil
        if captureNeedsStop {
            captureNeedsStop = false
            RoomScanDiagnostics.log.info("Releasing active RoomPlan capture session.")
            view.captureSession.stop(pauseARSession: true)
        } else {
            // A processing session has already received stop(); don't submit it twice.
            view.captureSession.arSession.pause()
        }
    }

    func updateCounts(walls: Int, objects: Int, token: UUID) {
        guard token == scanID, phase == .scanning else { return }
        if wallCount != walls { wallCount = walls }
        if objectCount != objects { objectCount = objects }
    }

    func fail(_ message: String, token: UUID) {
        guard token == scanID, phase == .scanning || phase == .processing else { return }
        processingTimeout?.cancel()
        processingTimeout = nil
        errorMessage = message
        phase = .failed
    }

    func receive(_ room: CapturedRoom, token: UUID) {
        guard token == scanID, phase == .scanning || phase == .processing else { return }
        guard !room.walls.isEmpty || !room.objects.isEmpty else {
            fail("No walls or furniture were detected. Scan the walls and floor together.", token: token)
            return
        }
        processingTimeout?.cancel()
        processingTimeout = nil
        capturedRoom = room
        document = RoomDocument(room: room)
        wallCount = room.walls.count
        objectCount = room.objects.count
        phase = .ready
        save()
    }

    func save() {
        guard !isSaving, let capturedRoom, let document else { return }
        isSaving = true
        saveMessage = nil
        let token = scanID
        Task { [weak self] in
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    try RoomExporter.save(room: capturedRoom, document: document)
                }.value
                guard let self, self.scanID == token else { return }
                self.files = files
                self.saveMessage = files.modelWarning
                self.isSaving = false
            } catch {
                guard let self, self.scanID == token else { return }
                self.saveMessage = "Could not save the scan: \(error.localizedDescription)"
                self.isSaving = false
            }
        }
    }

    /// A generic RoomPlan category can be given a useful name such as "화장대".
    @discardableResult
    func renameObject(id: String, label: String) -> Bool {
        guard !isSaving, var updated = document,
              let index = updated.objects.firstIndex(where: { $0.id == id }) else { return false }
        guard let files else {
            saveMessage = "Save the scan before renaming an item."
            return false
        }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.objects[index].label = name.isEmpty ? nil : name
        do {
            try RoomExporter.write(updated, to: files.json)
            document = updated
            return true
        } catch {
            saveMessage = "Could not save the new name: \(error.localizedDescription)"
            return false
        }
    }
}

#if DEBUG
extension RoomScanner {
    /// Scanner in a fixed state with sample data, for SwiftUI previews.
    static func preview(
        phase: Phase, document: RoomDocument? = nil, error: String? = nil
    ) -> RoomScanner {
        let scanner = RoomScanner()
        scanner.phase = phase
        scanner.document = document
        scanner.wallCount = document?.walls.count ?? 0
        scanner.objectCount = document?.objects.count ?? 0
        scanner.errorMessage = error
        return scanner
    }
}
#endif
