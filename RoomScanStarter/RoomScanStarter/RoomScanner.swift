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
    private var capturedRoom: CapturedRoom?

    var isSupported: Bool { RoomCaptureSession.isSupported }
    var showsCapture: Bool { phase == .scanning || phase == .processing || phase == .ready }

    func start() async {
        guard isSupported, !isSaving, phase != .permission,
              phase != .scanning, phase != .processing else { return }
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
        guard permitted else {
            errorMessage = "Camera access is required. Enable camera permission for this app in iPhone Settings."
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
        captureView = view
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    func stop() {
        guard phase == .scanning, let captureView else { return }
        phase = .processing
        // Keep the UIView mounted until didPresent delivers the processed room.
        captureView.captureSession.stop(pauseARSession: true)
    }

    func updateCounts(walls: Int, objects: Int, token: UUID) {
        guard token == scanID, phase == .scanning else { return }
        wallCount = walls
        objectCount = objects
    }

    func fail(_ message: String, token: UUID) {
        guard token == scanID, phase == .scanning || phase == .processing else { return }
        errorMessage = message
        phase = .failed
    }

    func receive(_ room: CapturedRoom, token: UUID) {
        guard token == scanID, phase == .scanning || phase == .processing else { return }
        guard !room.walls.isEmpty || !room.objects.isEmpty else {
            fail("No walls or furniture were detected. Scan again with both walls and the floor in view.", token: token)
            return
        }
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
                self.saveMessage = "Failed to save files: \(error.localizedDescription)"
                self.isSaving = false
            }
        }
    }

    /// A generic RoomPlan category can be given a useful name such as "vanity".
    @discardableResult
    func renameObject(id: String, label: String) -> Bool {
        guard !isSaving, var updated = document,
              let index = updated.objects.firstIndex(where: { $0.id == id }) else { return false }
        guard let files else {
            saveMessage = "Retry saving the files before saving this name."
            return false
        }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.objects[index].label = name.isEmpty ? nil : name
        do {
            try RoomExporter.write(updated, to: files.json)
            document = updated
            return true
        } catch {
            saveMessage = "Failed to save the updated name: \(error.localizedDescription)"
            return false
        }
    }
}
