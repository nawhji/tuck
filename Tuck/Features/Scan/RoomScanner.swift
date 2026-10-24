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
    // Without LiDAR (Simulator, SwiftUI previews) there is no camera view to show.
    var showsCapture: Bool {
        isSupported && (phase == .scanning || phase == .processing || phase == .ready)
    }

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
            errorMessage = "카메라 접근이 필요해요. 아이폰 설정에서 이 앱의 카메라 권한을 켜주세요."
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
            fail("인식된 벽이나 가구가 없어요. 벽과 바닥이 함께 보이도록 다시 스캔해주세요.", token: token)
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
                self.saveMessage = "파일 저장에 실패했어요: \(error.localizedDescription)"
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
            saveMessage = "이름을 저장하기 전에 파일 저장을 다시 시도해주세요."
            return false
        }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.objects[index].label = name.isEmpty ? nil : name
        do {
            try RoomExporter.write(updated, to: files.json)
            document = updated
            return true
        } catch {
            saveMessage = "이름 변경을 파일에 저장하지 못했어요: \(error.localizedDescription)"
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
