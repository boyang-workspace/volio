import SwiftUI
import PhotosUI

struct OnboardingFlowView: View {
    @Environment(VolioSession.self) private var session
    @State private var step = 1
    @State private var capturedImageData: Data?
    @State private var creatorName = ""
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 6
    @State private var birthMonth = 6
    @State private var onlyYear = false
    @State private var isSaving = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var onboardingComplete = false

    var body: some View {
        Group {
            if onboardingComplete {
                RootTabsView()
            } else {
                VStack {
                    switch step {
                    case 1: welcomeStep
                    case 2: captureStep
                    case 3: creatorStep
                    case 4: revealStep
                    default: welcomeStep
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Every creation\nhas a place.")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Collect, organize, and revisit creative works — from the first drawing to the latest masterpiece.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 14) {
                Button {
                    withAnimation { step = 2 }
                } label: {
                    Label("Start with a work", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    withAnimation { step = 2 }
                } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Step 2: First Capture

    private var captureStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if let data = capturedImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 16, y: 4)

                Text("Artwork captured")
                    .font(.headline)
                    .foregroundStyle(.green)

                Button {
                    withAnimation { step = 3 }
                } label: {
                    Label("Next", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
            } else {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 48))
                    .foregroundStyle(.quaternary)

                Text("Take a photo of the first work")
                    .font(.title3.weight(.semibold))
                Text("Volio will crop and organize it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    Button {
                        showCamera = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.title)
                            Text("Camera")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 1, matching: .images) {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title)
                            Text("Photos")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .fullScreenCover(isPresented: $showCamera) {
            FirstCaptureCameraView { data in
                capturedImageData = data
                showCamera = false
            }
        }
        .onChange(of: selectedItems) { _, items in
            Task { await loadFirstPhoto(items) }
        }
    }

    // MARK: - Step 3: Creator

    private var creatorStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    Text("Who made this?")
                        .font(.largeTitle.bold())
                    Text("Volio uses birth month to place each work at the right age.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    TextField("Name", text: $creatorName)
                        .textInputAutocapitalization(.words)
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Toggle("I only know the birth year", isOn: $onlyYear)

                    Picker("Birth year", selection: $birthYear) {
                        ForEach((2005...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 118)

                    if !onlyYear {
                        Picker("Birth month", selection: $birthMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(Calendar.current.monthSymbols[month - 1]).tag(month)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 118)
                    }
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)

                HStack(spacing: 12) {
                    Button {
                        withAnimation { step = 2 }
                    } label: {
                        Text("Back")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        Task { await saveCreator() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("Continue", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(22)
        }
    }

    // MARK: - Step 4: Reveal

    private var revealStep: some View {
        VStack(spacing: 24) {
            Spacer()

            if let data = capturedImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
            }

            VStack(spacing: 6) {
                Text("Your first work is now in Volio.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                if !creatorName.isEmpty {
                    Text("\(creatorName) · First work")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 14) {
                Button {
                    onboardingComplete = true
                } label: {
                    Label("Go to Timeline", systemImage: "clock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onboardingComplete = true
                    // Will navigate to Capture tab
                } label: {
                    Label("Scan more works", systemImage: "square.stack.3d.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Actions

    private func loadFirstPhoto(_ items: [PhotosPickerItem]) async {
        guard let item = items.first,
              let data = try? await item.loadTransferable(type: Data.self) else { return }
        capturedImageData = data
    }

    private func saveCreator() async {
        guard let client = session.client else { return }
        let name = creatorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        let birthDate = onlyYear ? String(birthYear) : String(format: "%04d-%02d", birthYear, birthMonth)
        do {
            let child = try await client.addChild(name: name, birthDate: birthDate)
            session.children = [child]
            session.selectedChildId = child.id
            if let data = capturedImageData {
                try? await client.importPhotos(
                    [ImportPhoto(data: data, filename: "first-work.jpg")],
                    childId: child.id,
                    childName: child.name,
                    batchName: "\(child.name) · First work",
                    artworkDate: "",
                    datePrecision: "age",
                    dateNote: "First work",
                    childAgeMonths: defaultAgeMonths(for: child),
                    workType: "paper",
                    autoAnalyze: true
                )
            }
            await session.refresh()
            withAnimation { step = 4 }
        } catch {
            session.errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func defaultAgeMonths(for child: Child) -> Int {
        guard let birthDate = child.birthDate,
              let year = Int(birthDate.prefix(4)) else { return 72 }
        let currentYear = Calendar.current.component(.year, from: Date())
        return max(0, (currentYear - year) * 12)
    }
}

// MARK: - First Capture Camera

struct FirstCaptureCameraView: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void
        let dismiss: () -> Void

        init(onCapture: @escaping (Data) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.86) {
                onCapture(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
