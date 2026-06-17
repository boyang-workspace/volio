import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

private enum CaptureSheet: Identifiable {
    case stackCamera
    case addChild

    var id: String {
        switch self {
        case .stackCamera: "stack-camera"
        case .addChild: "add-child"
        }
    }
}

struct CaptureView: View {
    @Environment(VolioSession.self) private var session
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photos: [ImportPhoto] = []
    @State private var selectedChildId = ""
    @State private var workType: CaptureWorkType = .paper
    @State private var dateMode: BatchDateMode = .age
    @State private var selectedAgeYears = 6
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var activeSheet: CaptureSheet?
    @State private var isUploading = false
    @State private var lastResult: String?

    private var selectedChild: Child? {
        let id = selectedChildId.isEmpty ? (session.selectedChildId ?? session.children.first?.id) : selectedChildId
        return session.children.first(where: { $0.id == id })
    }

    private var canUpload: Bool {
        selectedChild != nil && !photos.isEmpty && !isUploading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    modeCards
                    batchContext
                    sourceCards
                    selectedStrip
                    queueCard
                    resultCard
                }
                .padding(18)
                .padding(.bottom, 72)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Capture")
            .toolbar {
                Menu {
                    Button("Refresh Desktop") {
                        Task { await session.refresh() }
                    }
                    Button("Pair Again", role: .destructive) {
                        session.forgetPairing()
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
            .safeAreaInset(edge: .bottom) {
                uploadBar
            }
            .onAppear {
                selectedChildId = selectedChildId.isEmpty ? (session.selectedChildId ?? session.children.first?.id ?? "") : selectedChildId
                selectedAgeYears = defaultAgeYears()
            }
            .onChange(of: selectedItems) { _, items in
                Task { await loadPhotos(items) }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .stackCamera:
                    StackCameraView { data in
                        photos.append(ImportPhoto(data: data, filename: "stack-\(photos.count + 1)-\(Int(Date().timeIntervalSince1970)).jpg"))
                    }
                case .addChild:
                    AddChildSheet { child in
                        selectedChildId = child.id
                    }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From pile to timeline")
                .font(.largeTitle.bold())
            Text("Batch capture once, set age once, let Volio Desktop organize the rest.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var modeCards: some View {
        HStack(spacing: 12) {
            ForEach(CaptureWorkType.allCases) { type in
                Button {
                    workType = type
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: type.icon)
                            .font(.title2.weight(.semibold))
                        Text(type.title)
                            .font(.headline)
                        Text(type.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        workType == type ? Color.blue.opacity(0.13) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(workType == type ? Color.blue : Color.clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var batchContext: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Batch details", systemImage: "rectangle.stack.badge.person.crop")
                .font(.headline)

            HStack(spacing: 10) {
                Menu {
                    ForEach(session.children) { child in
                        Button(child.name) {
                            selectedChildId = child.id
                            session.selectedChildId = child.id
                            selectedAgeYears = defaultAgeYears(for: child)
                        }
                    }
                    Button("Add Child...") {
                        activeSheet = .addChild
                    }
                } label: {
                    PillLabel(
                        icon: "person.fill",
                        title: selectedChild?.name ?? "Choose child",
                        tint: .blue
                    )
                }

                Menu {
                    ForEach(BatchDateMode.allCases) { mode in
                        Button(mode.title) {
                            dateMode = mode
                        }
                    }
                } label: {
                    PillLabel(icon: "calendar", title: dateMode.title, tint: .purple)
                }
            }

            dateControl
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var dateControl: some View {
        switch dateMode {
        case .age:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Created around")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Age \(selectedAgeYears)")
                        .font(.headline)
                }
                Stepper("Age \(selectedAgeYears)", value: $selectedAgeYears, in: 0...18)
                    .labelsHidden()
                Text("Every photo in this batch will enter the Age \(selectedAgeYears) timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .year:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Created around")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(selectedYear))
                        .font(.headline)
                }
                Stepper("Year \(selectedYear)", value: $selectedYear, in: 2005...Calendar.current.component(.year, from: Date()))
                    .labelsHidden()
                Text("Use this for old artwork when age is uncertain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .unknown:
            Label("Volio will keep these in Date unknown until you organize them.", systemImage: "questionmark.folder")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sourceCards: some View {
        VStack(spacing: 12) {
            Button {
                activeSheet = .stackCamera
            } label: {
                SourceCard(
                    icon: "square.stack.3d.down.right.fill",
                    title: "Stack Scan",
                    subtitle: "Keep the camera open and capture a pile quickly",
                    badge: photos.isEmpty ? "Best for history" : "\(photos.count) ready",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            PhotosPicker(selection: $selectedItems, maxSelectionCount: 60, matching: .images) {
                SourceCard(
                    icon: "photo.on.rectangle.angled",
                    title: "Import from Photos",
                    subtitle: "Select old artwork photos already on your iPhone",
                    badge: "Multi-select",
                    tint: .green
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var selectedStrip: some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(photos.count) selected", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        photos.removeAll()
                        selectedItems.removeAll()
                    }
                    .font(.caption.weight(.semibold))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(photos) { photo in
                            if let image = UIImage(data: photo.data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    @ViewBuilder
    private var queueCard: some View {
        if let queue = session.queue {
            HStack(spacing: 12) {
                Image(systemName: queue.processing > 0 || queue.workerActive == true ? "wand.and.stars" : "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(queue.processing > 0 || queue.pending > 0 ? .blue : .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(queue.processing > 0 || queue.pending > 0 ? "Volio Desktop is organizing" : "Desktop queue ready")
                        .font(.subheadline.weight(.semibold))
                    Text("Processing \(queue.processing) · Waiting \(queue.pending) · Failed \(queue.failed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        if let lastResult {
            Label(lastResult, systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var uploadBar: some View {
        VStack(spacing: 8) {
            Button {
                Task { await upload() }
            } label: {
                HStack {
                    if isUploading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    Text(uploadTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canUpload)

            Text(uploadContext)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var uploadTitle: String {
        if photos.isEmpty { return "Add photos first" }
        if selectedChild == nil { return "Choose child" }
        return "Add \(photos.count) to Timeline"
    }

    private var uploadContext: String {
        let child = selectedChild?.name ?? "No child"
        switch dateMode {
        case .age: return "\(child) · Age \(selectedAgeYears) · \(workType.title)"
        case .year: return "\(child) · \(selectedYear) · \(workType.title)"
        case .unknown: return "\(child) · Date unknown · \(workType.title)"
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [ImportPhoto] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.86) else { continue }
            loaded.append(ImportPhoto(data: jpeg, filename: "volio-import-\(index + 1).jpg"))
        }
        photos = loaded
    }

    private func upload() async {
        guard let client = session.client, let child = selectedChild else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            try await client.importPhotos(
                photos,
                childId: child.id,
                childName: child.name,
                batchName: batchName(for: child),
                artworkDate: artworkDateValue,
                datePrecision: dateMode.rawValue,
                dateNote: dateNoteValue,
                childAgeMonths: dateMode == .age ? selectedAgeYears * 12 : nil,
                workType: workType.rawValue,
                autoAnalyze: true
            )
            let count = photos.count
            photos.removeAll()
            selectedItems.removeAll()
            lastResult = "\(count) works added. Open Timeline to see \(child.name) at \(dateMode == .age ? "Age \(selectedAgeYears)" : dateNoteValue)."
            await session.refresh()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private func batchName(for child: Child) -> String {
        switch dateMode {
        case .age: "\(child.name) · Age \(selectedAgeYears)"
        case .year: "\(child.name) · \(selectedYear)"
        case .unknown: "\(child.name) · Date unknown"
        }
    }

    private var artworkDateValue: String {
        switch dateMode {
        case .age: ""
        case .year: String(selectedYear)
        case .unknown: ""
        }
    }

    private var dateNoteValue: String {
        switch dateMode {
        case .age: "Around age \(selectedAgeYears)"
        case .year: "Around \(selectedYear)"
        case .unknown: "Creation date unknown"
        }
    }

    private func defaultAgeYears(for child: Child? = nil) -> Int {
        guard let child = child ?? selectedChild,
              let birthDate = child.birthDate,
              let year = Int(birthDate.prefix(4)) else {
            return selectedAgeYears
        }
        let currentYear = Calendar.current.component(.year, from: Date())
        return min(18, max(0, currentYear - year))
    }
}

private struct PillLabel: View {
    var icon: String
    var title: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct SourceCard: View {
    var icon: String
    var title: String
    var subtitle: String
    var badge: String
    var tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(badge)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct AddChildSheet: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 6
    @State private var birthMonth = 6
    @State private var onlyYear = false
    @State private var isSaving = false
    var onCreated: (Child) -> Void

    private var birthDateValue: String {
        onlyYear ? String(birthYear) : String(format: "%04d-%02d", birthYear, birthMonth)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Child") {
                    TextField("Nickname", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Birth") {
                    Toggle("Only birth year", isOn: $onlyYear)
                    Picker("Birth year", selection: $birthYear) {
                        ForEach((2005...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    if !onlyYear {
                        Picker("Birth month", selection: $birthMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Child")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let client = session.client else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let child = try await client.addChild(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                birthDate: birthDateValue
            )
            await session.refresh()
            onCreated(child)
            dismiss()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}

struct StackCameraView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> StackCameraViewController {
        let controller = StackCameraViewController()
        controller.onCapture = onCapture
        controller.onClose = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: StackCameraViewController, context: Context) {}
}

final class StackCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let countLabel = UILabel()
    private var capturedCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCamera()
        configureOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input),
              captureSession.canAddOutput(photoOutput) else {
            captureSession.commitConfiguration()
            showCameraUnavailable()
            return
        }
        captureSession.addInput(input)
        captureSession.addOutput(photoOutput)
        captureSession.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        Task.detached { [captureSession] in
            captureSession.startRunning()
        }
    }

    private func configureOverlay() {
        let doneButton = UIButton(type: .system)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.tintColor = .white
        doneButton.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        doneButton.layer.cornerRadius = 18
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        countLabel.text = "0 captured"
        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        countLabel.layer.cornerRadius = 18
        countLabel.clipsToBounds = true
        countLabel.textAlignment = .center

        let shutter = UIButton(type: .system)
        shutter.backgroundColor = .white
        shutter.layer.cornerRadius = 36
        shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
        shutter.layer.borderWidth = 6
        shutter.addTarget(self, action: #selector(capture), for: .touchUpInside)

        [doneButton, countLabel, shutter].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            doneButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            countLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),
            countLabel.heightAnchor.constraint(equalToConstant: 36),

            shutter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            shutter.widthAnchor.constraint(equalToConstant: 72),
            shutter.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    private func showCameraUnavailable() {
        let label = UILabel()
        label.text = "Camera unavailable"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func capture() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func close() {
        captureSession.stopRunning()
        onClose?()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.86) else {
            return
        }
        capturedCount += 1
        countLabel.text = "\(capturedCount) captured"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCapture?(jpeg)
    }
}
