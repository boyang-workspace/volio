import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct CaptureView: View {
    var autoOpenToken: Int = 0

    @Environment(VolioSession.self) private var session
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var activeWorkType = "visual"
    @State private var lastHandledAutoOpenToken = 0
    @State private var lastSavedCount = 0
    @State private var isImportingPhotos = false
    @State private var capturedPhotos: [CapturedPhoto] = []
    @State private var showReview = false
    @State private var workType: CaptureWorkType = .paper
    @State private var dateMode: BatchDateMode = .age
    @State private var selectedAge = 5
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var selectedSeason = "spring"

    private let accentColor = VolioTheme.accent
    private let seasons = ["spring", "summer", "fall", "winter"]

    var body: some View {
        NavigationStack {
            startView
                .background(VolioTheme.paper.ignoresSafeArea())
                .navigationTitle("Capture")
                .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: $showCamera) {
            StackCameraView(
                onCapture: { data in
                    saveImmediately(data, workType: activeWorkType)
                }
            )
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems, maxSelectionCount: 30, matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .onAppear {
            openCameraIfNeeded(for: autoOpenToken)
        }
        .onChange(of: autoOpenToken) { _, token in
            openCameraIfNeeded(for: token)
        }
    }

    private var startView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(VolioTheme.card)
                .frame(width: 86, height: 86)
                .background(VolioTheme.ink, in: RoundedRectangle(cornerRadius: 26))

            Text(lastSavedCount > 0 ? "\(lastSavedCount) saved" : "Ready to capture")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(VolioTheme.ink)

            Text(isImportingPhotos ? "Importing photos..." : "Use Add to take a photo or choose photos.")
                .font(.subheadline)
                .foregroundStyle(VolioTheme.mutedInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                openCamera(workType: "visual")
            } label: {
                Label("Open Camera", systemImage: "camera.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(VolioTheme.accent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var quickCaptureHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(VolioTheme.card)
                    .frame(width: 66, height: 66)
                    .background(VolioTheme.ink, in: RoundedRectangle(cornerRadius: 20))
                    .rotationEffect(.degrees(-2))
                Spacer()
                Text("VOLIO")
                    .font(.caption.weight(.black))
                    .tracking(2)
                    .foregroundStyle(VolioTheme.mutedInk)
            }

            Text("Open camera. Save first.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(VolioTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Shoot the work now. Add titles, age, notes, and AI polish later.")
                .font(.subheadline)
                .foregroundStyle(VolioTheme.mutedInk)

            Button {
                openCamera(workType: "visual")
            } label: {
                Label("Open Camera", systemImage: "camera.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(VolioTheme.accent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(VolioTheme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(VolioTheme.ink.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var recentHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(VolioTheme.mutedInk)
                    .textCase(.uppercase)
                Spacer()
                Text("\(min(session.works.count, 6)) shown")
                    .font(.caption)
                    .foregroundStyle(VolioTheme.mutedInk.opacity(0.8))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(Array(session.works.prefix(6))) { work in
                    WorkTile(work: work)
                }
            }
        }
        .padding(16)
        .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var savedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(VolioTheme.moss)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(lastSavedCount == 1 ? "Saved 1 work" : "Saved \(lastSavedCount) works")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(VolioTheme.ink)
                Text("You can refine details from Library.")
                    .font(.caption)
                    .foregroundStyle(VolioTheme.mutedInk)
            }
            Spacer()
        }
        .padding(14)
        .background(VolioTheme.moss.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
    }

    private func captureChip(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(VolioTheme.accent)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(VolioTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(VolioTheme.ink.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(capturedPhotos.count) works captured")
                        .font(.title2.bold())
                    Text("Set the rough creation time once for the whole batch.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                workTypePicker
                createdAroundPicker

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                    ForEach(capturedPhotos) { photo in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: UIImage(data: photo.data) ?? UIImage())
                                .resizable()
                                .scaledToFill()
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Button {
                                capturedPhotos.removeAll { $0.id == photo.id }
                                if capturedPhotos.isEmpty { showReview = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                                    .padding(4)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                        showReview = false
                    } label: {
                        Label("Add More", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        saveCaptured()
                    } label: {
                        Label("Save All", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .controlSize(.large)
                    .disabled(capturedPhotos.isEmpty)
                }
            }
            .padding(18)
        }
    }

    private var workTypePicker: some View {
        HStack(spacing: 10) {
            ForEach(CaptureWorkType.allCases) { type in
                Button {
                    workType = type
                } label: {
                    Label(type.title, systemImage: type.icon)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(workType == type ? accentColor.opacity(0.16) : Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(workType == type ? accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var createdAroundPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Made around")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Picker("Made around", selection: $dateMode) {
                ForEach(BatchDateMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if dateMode == .age {
                Stepper("Age \(selectedAge)", value: $selectedAge, in: 0...30)
                    .font(.headline)
            } else if dateMode == .year {
                HStack {
                    Picker("Season", selection: $selectedSeason) {
                        ForEach(seasons, id: \.self) { season in
                            Text(season.capitalized).tag(season)
                        }
                    }
                    Picker("Year", selection: $selectedYear) {
                        ForEach((2005...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                }
            } else {
                Label("You can refine the date later.", systemImage: "calendar.badge.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var createdAroundInput: CreatedAroundInput {
        switch dateMode {
        case .age:
            return .ageYears(selectedAge)
        case .year:
            return .season(selectedSeason, selectedYear)
        case .unknown:
            return .unknown
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await MainActor.run {
            isImportingPhotos = true
        }
        var loadedJPEGs: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.86) {
                    loadedJPEGs.append(jpeg)
                }
            }
        }
        await MainActor.run {
            for jpeg in loadedJPEGs {
                session.createWork(data: jpeg, workType: "visual", createdAround: .capturedDate)
            }
            isImportingPhotos = false
            photoPickerItems.removeAll()
            if !loadedJPEGs.isEmpty {
                lastSavedCount = loadedJPEGs.count
            }
        }
    }

    private func saveCaptured() {
        for photo in capturedPhotos {
            session.createWork(data: photo.data, workType: workType.rawValue, createdAround: createdAroundInput)
        }
        capturedPhotos.removeAll()
        showReview = false
    }

    private func openCamera(workType: String) {
        activeWorkType = workType
        showCamera = true
    }

    private func openCameraIfNeeded(for token: Int) {
        guard token > 0, token != lastHandledAutoOpenToken else { return }
        lastHandledAutoOpenToken = token
        openCamera(workType: "visual")
    }

    private func saveImmediately(_ data: Data, workType: String) {
        session.createWork(data: data, workType: workType, createdAround: .capturedDate)
        lastSavedCount += 1
    }
}

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let data: Data
}

struct WorkTile: View {
    var work: LocalWork

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalThumbnail(path: work.thumbnailPath ?? work.originalPath, workId: work.id)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(work.displayTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(work.createdAroundLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct LocalThumbnail: View {
    var path: String?
    var workId: String?
    @State private var image: UIImage?
    @State private var loadPath: String?

    var body: some View {
        Group {
            if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .background(.quaternary)
            } else {
            placeholder
            }
        }
        .task(id: path) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
    }

    @MainActor
    private func loadImage() async {
        let key = "\(workId ?? "")|\(path ?? "")"
        guard loadPath != key else { return }
        loadPath = key
        image = nil
        let candidates = [
            workId.map(ImageStorage.thumbnailPath(for:)),
            workId.map(ImageStorage.originalPath(for:)),
            path,
            inferredOriginalPath(from: path)
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            for path in candidates {
                if FileManager.default.fileExists(atPath: path),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let image = UIImage(data: data) {
                    return image
                }
            }
            return nil as UIImage?
        }.value
        if loadPath == key {
            image = loaded
        }
    }

    private func inferredOriginalPath(from path: String?) -> String? {
        guard let path, path.hasSuffix("thumbnail.jpg") else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("original.jpg").path
    }
}
