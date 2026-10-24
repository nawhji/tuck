import SwiftUI

@MainActor
struct ScanView: View {
    @StateObject private var scanner: RoomScanner
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0

    /// Pass a scanner only to inject a fixed state (SwiftUI previews).
    init(scanner: RoomScanner? = nil) {
        _scanner = StateObject(wrappedValue: scanner ?? RoomScanner())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    Label("벽 \(scanner.wallCount)", systemImage: "square.split.2x2")
                    Spacer()
                    Label("가구 \(scanner.objectCount)", systemImage: "sofa")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                ZStack {
                    if scanner.showsCapture {
                        RoomCaptureContainer(scanner: scanner)
                            .id(scanner.scanID)
                    } else {
                        placeholder
                    }
                    if scanner.phase == .processing {
                        ProgressView("3D 공간 정리 중…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 220)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                if let document = scanner.document {
                    resultList(document)
                }

                if let message = scanner.errorMessage ?? scanner.saveMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                controls
            }
            .padding()
            .background(Color(.systemBackground))
            .navigationTitle("내 방 스캔")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { scanner.stop() }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: scanner.isSupported ? "viewfinder" : "iphone.slash")
                .font(.system(size: 46))
            Text(scanner.isSupported ? "벽과 가구가 함께 보이도록\n방을 천천히 둘러봐 주세요."
                 : "RoomPlan 스캔에는 LiDAR가 있는\n아이폰 또는 아이패드가 필요해요.")
                .multilineTextAlignment(.center)
            Text("스캔 후 3D 공간과 치수가 저장돼요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var controls: some View {
        switch scanner.phase {
        case .scanning:
            Button { scanner.stop() } label: {
                Label("스캔 완료", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .processing, .permission:
            ProgressView(scanner.phase == .permission ? "카메라 확인 중…" : "잠시만 기다려 주세요…")
        case .ready:
            if scanner.isSaving {
                ProgressView("치수와 3D 파일 저장 중…")
            }
            HStack {
                if let files = scanner.files {
                    ShareLink(item: files.json) {
                        Label("JSON 공유", systemImage: "square.and.arrow.up")
                    }
                    if let model = files.model {
                        ShareLink(item: model) {
                            Label("3D 공유", systemImage: "cube")
                        }
                    }
                }
                if !scanner.isSaving && (scanner.files == nil || scanner.files?.model == nil) {
                    Button("저장 재시도") { scanner.save() }
                }
                Spacer(minLength: 0)
                Button("다시 스캔") {
                    Task { await scanner.start() }
                }
                .disabled(scanner.isSaving)
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        case .idle, .failed:
            Button { Task { await scanner.start() } } label: {
                Label("방 스캔 시작", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!scanner.isSupported)
        }
    }

    private func resultList(_ document: RoomDocument) -> some View {
        VStack(spacing: 8) {
            Picker("측정 결과", selection: $selection) {
                Text("가구").tag(0)
                Text("벽·구조").tag(1)
            }
            .pickerStyle(.segmented)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if selection == 0 {
                        if document.objects.isEmpty {
                            Text("인식된 가구가 없어요.").foregroundStyle(.secondary)
                        }
                        ForEach(document.objects) { object in
                            ObjectRow(object: object, disabled: scanner.isSaving) { name in
                                scanner.renameObject(id: object.id, label: name)
                            }
                        }
                    } else {
                        ForEach(document.structures) { item in
                            HStack {
                                Text(item.category)
                                Spacer()
                                Text(item.sizeDescription).monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 150)
            Text("가로 × 높이 × 깊이 · 측정값은 추정치예요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct ObjectRow: View {
    let object: RoomElement
    let disabled: Bool
    let onRename: (String) -> Bool
    @State private var name: String
    @State private var savedName: String

    init(object: RoomElement, disabled: Bool, onRename: @escaping (String) -> Bool) {
        self.object = object
        self.disabled = disabled
        self.onRename = onRename
        _name = State(initialValue: object.label ?? "")
        _savedName = State(initialValue: object.label ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(object.category).fontWeight(.medium)
                Spacer()
                Text(object.sizeDescription).monospacedDigit()
            }
            .font(.subheadline)
            HStack {
                TextField("이름 붙이기 (예: 화장대)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                Button(name == savedName ? "저장됨" : "이름 저장") { commit() }
                    .disabled(disabled || name == savedName)
            }
            .font(.caption)
            .disabled(disabled)
        }
    }

    private func commit() {
        if onRename(name) { savedName = name }
    }
}

#if DEBUG
#Preview("시작 전") {
    ScanView(scanner: .preview(phase: .idle))
}

#Preview("스캔 결과") {
    ScanView(scanner: .preview(phase: .ready, document: .sample))
}

#Preview("오류") {
    ScanView(scanner: .preview(phase: .failed, error: "카메라 접근이 필요해요. 아이폰 설정에서 이 앱의 카메라 권한을 켜주세요."))
}
#endif
