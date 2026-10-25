import SwiftUI

@MainActor
struct ScanView: View {
    @StateObject private var scanner: RoomScanner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @State private var confirmsDiscard = false
    private let autoStart: Bool
    private let onSaved: (RoomDocument, ScanFiles) -> Void

    /// Pass a scanner only to inject a fixed state (SwiftUI previews).
    init(scanner: RoomScanner? = nil, onSaved: @escaping (RoomDocument, ScanFiles) -> Void = { _, _ in }) {
        _scanner = StateObject(wrappedValue: scanner ?? RoomScanner())
        autoStart = scanner == nil
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack {
                    Label("Walls \(scanner.wallCount)", systemImage: "square.split.2x2")
                    Spacer()
                    Label("Furniture \(scanner.objectCount)", systemImage: "sofa")
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
                        ProgressView("Preparing 3D room…")
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
            .navigationTitle("Scan My Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if scanner.phase == .scanning || scanner.phase == .processing ||
                            (scanner.document != nil && scanner.files == nil) {
                            confirmsDiscard = true
                        } else {
                            finishAndDismiss()
                        }
                    }
                    .disabled(scanner.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if scanner.phase == .ready {
                        Button("Use in Home") { finishAndDismiss() }
                            .disabled(scanner.isSaving || scanner.files == nil)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task { if autoStart { await scanner.start() } }
        .onDisappear { scanner.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                if scanner.phase == .permission { scanner.cancel() }
                else { scanner.stop() }
            }
        }
        .confirmationDialog("Discard this scan?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Scan", role: .destructive) { finishAndDismiss() }
            Button("Continue Scanning", role: .cancel) {}
        }
    }

    private func finishAndDismiss() {
        if let document = scanner.document, let files = scanner.files {
            onSaved(document, files)
        }
        scanner.cancel()
        dismiss()
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: scanner.isSupported ? "viewfinder" : "iphone.slash")
                .font(.system(size: 46))
            Text(scanner.isSupported ? "Move slowly around the room so the walls and furniture stay in view."
                 : "RoomPlan scanning requires an iPhone or iPad with LiDAR.")
                .multilineTextAlignment(.center)
            Text("Your 3D room and measurements will be saved after scanning.")
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
                Label("Finish Scan", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .processing, .permission:
            ProgressView(scanner.phase == .permission ? "Checking camera access…" : "Please wait…")
        case .ready:
            if scanner.isSaving {
                ProgressView("Saving measurements and 3D model…")
            } else if scanner.files != nil {
                Label("Saved on iPhone", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let files = scanner.files {
                    ShareLink(item: files.json) {
                        Label("Share JSON", systemImage: "square.and.arrow.up")
                    }
                    if let model = files.model {
                        ShareLink(item: model) {
                            Label("Share 3D Model", systemImage: "cube")
                        }
                    }
                }
                if !scanner.isSaving && (scanner.files == nil || scanner.files?.model == nil) {
                    Button("Retry Save") { scanner.save() }
                }
                Spacer(minLength: 0)
                Button("Scan Again") {
                    Task { await scanner.start() }
                }
                .disabled(scanner.isSaving)
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        case .idle, .failed:
            if scanner.phase == .failed {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button { Task { await scanner.start() } } label: {
                Label("Start Room Scan", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!scanner.isSupported)
        }
    }

    private func resultList(_ document: RoomDocument) -> some View {
        VStack(spacing: 8) {
            Picker("Measurements", selection: $selection) {
                Text("Furniture").tag(0)
                Text("Walls & Structure").tag(1)
            }
            .pickerStyle(.segmented)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if selection == 0 {
                        if document.objects.isEmpty {
                            Text("No furniture detected.").foregroundStyle(.secondary)
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
            Text("Width × height × depth · estimated along local axes.")
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
                TextField("Name this item (e.g. vanity)", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                Button(name == savedName ? "Saved" : "Save Name") { commit() }
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
#Preview("Before Scan") {
    ScanView(scanner: .preview(phase: .idle))
}

#Preview("Scan Result") {
    ScanView(scanner: .preview(phase: .ready, document: .sample))
}

#Preview("Error") {
    ScanView(scanner: .preview(phase: .failed, error: "Camera access is required. Enable camera permission for this app in iPhone Settings."))
}
#endif
