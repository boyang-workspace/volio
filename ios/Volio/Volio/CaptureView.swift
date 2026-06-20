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
                onCapture: { payload in
                    saveImmediately(payload.originalData, previewData: payload.previewData, workType: activeWorkType)
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
        var loadedImages: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loadedImages.append(data)
            }
        }
        await MainActor.run {
            for data in loadedImages {
                Task {
                    await session.createWorkAsync(data: data, workType: "visual", createdAround: .unknown)
                }
            }
            isImportingPhotos = false
            photoPickerItems.removeAll()
            if !loadedImages.isEmpty {
                lastSavedCount = loadedImages.count
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

    private func saveImmediately(_ data: Data, previewData: Data?, workType: String) {
        Task {
            await session.createWorkAsync(data: data, previewData: previewData, workType: workType, createdAround: .unknown)
        }
        lastSavedCount += 1
    }
}

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let data: Data
}

enum CreationTimeDraftMode: String, CaseIterable, Identifiable {
    case recent
    case age
    case ageRange
    case year
    case season
    case lifeStage
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recently made"
        case .age: "Age"
        case .ageRange: "Age range"
        case .year: "Year"
        case .season: "Season"
        case .lifeStage: "Life stage"
        case .unknown: "Not sure"
        }
    }
}

struct CreationTimeDraft: Equatable {
    var mode: CreationTimeDraftMode = .unknown
    var exactDate = Date()
    var selectedAge = 5
    var ageStart = 5
    var ageEnd = 6
    var selectedYear = Calendar.current.component(.year, from: Date())
    var selectedMonth = Calendar.current.component(.month, from: Date())
    var selectedSeason = "spring"
    var lifeStageLabel = "Kindergarten"

    var input: CreatedAroundInput {
        switch mode {
        case .recent:
            return .capturedDate
        case .age:
            return .ageYears(selectedAge)
        case .ageRange:
            return .ageRange(ageStart, max(ageStart, ageEnd))
        case .year:
            return .year(selectedYear)
        case .season:
            return .season(selectedSeason, selectedYear)
        case .lifeStage:
            return .lifeStage(lifeStageLabel.lowercased().replacingOccurrences(of: " ", with: "_"), lifeStageLabel)
        case .unknown:
            return .unknown
        }
    }

    var displayLabel: String {
        switch mode {
        case .recent:
            return "Recently made"
        case .age:
            return "Age \(selectedAge)"
        case .ageRange:
            return "Around Age \(ageStart)-\(max(ageStart, ageEnd))"
        case .year:
            return "\(selectedYear)"
        case .season:
            return "\(selectedSeason.capitalized) \(selectedYear)"
        case .lifeStage:
            return lifeStageLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Life stage" : lifeStageLabel
        case .unknown:
            return "Not remembered yet"
        }
    }

    init(mode: CreationTimeDraftMode = .unknown) {
        self.mode = mode
    }

    init(work: LocalWork) {
        if work.creationTimeKind == .capturedDate {
            self.mode = .recent
        } else if work.creationTimeKind == .ageRange,
                  let start = work.creationAgeStartMonths,
                  let end = work.creationAgeEndMonths {
            self.mode = .ageRange
            self.ageStart = max(0, start) / 12
            self.ageEnd = max(self.ageStart, max(0, end) / 12)
        } else if let months = work.creationAgeStartMonths ?? work.createdAroundAgeMonths ?? work.ageAtCreationMonths {
            self.mode = .age
            self.selectedAge = max(0, months) / 12
        } else if work.creationTimeKind == .season, let season = work.creationSeasonRaw ?? work.createdAroundSeason {
            self.mode = .season
            self.selectedSeason = season
            self.selectedYear = work.creationYear ?? work.createdAroundYear ?? Calendar.current.component(.year, from: Date())
        } else if work.creationTimeKind == .lifeStage, let label = work.customTimeLabel {
            self.mode = .lifeStage
            self.lifeStageLabel = label
        } else if let year = work.creationYear ?? work.createdAroundYear {
            self.mode = .year
            self.selectedYear = year
        } else {
            self.mode = .unknown
        }
    }
}

struct BatchReviewView: View {
    @Environment(VolioSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let works: [LocalWork]
    @State private var batchDraft = CreationTimeDraft(mode: .unknown)
    @State private var overrides: [String: CreationTimeDraft] = [:]
    @State private var overrideWorkID: String?
    @State private var overrideDraft = CreationTimeDraft(mode: .unknown)

    private var workIDs: [String] {
        works.map(\.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    CreationTimePicker(title: "These works were made around", draft: $batchDraft)
                    workCarousel
                    footerActions
                }
                .padding(18)
            }
            .background(VolioTheme.paper.ignoresSafeArea())
            .navigationTitle("Batch Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        session.flushMacSyncBatch()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { overrideWorkID != nil },
                set: { if !$0 { overrideWorkID = nil } }
            )) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let work = overrideTarget {
                                BatchReviewTile(work: work, label: nil)
                                    .frame(maxWidth: 220)
                            }
                            CreationTimePicker(title: "This work was made around", draft: $overrideDraft)
                        }
                        .padding(18)
                    }
                    .background(VolioTheme.paper.ignoresSafeArea())
                    .navigationTitle("Single Work")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { overrideWorkID = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if let id = overrideWorkID {
                                    overrides[id] = overrideDraft
                                }
                                overrideWorkID = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When were these made?")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(VolioTheme.ink)
            Text("Originals are already saved on this iPhone. Set a rough time now, or let them resurface in Timeline later.")
                .font(.subheadline)
                .foregroundStyle(VolioTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var workCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(works.count) Works")
                .font(.caption.weight(.bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(VolioTheme.mutedInk)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(works.enumerated()), id: \.element.id) { index, work in
                        Button {
                            overrideWorkID = work.id
                            overrideDraft = overrides[work.id] ?? batchDraft
                        } label: {
                            BatchReviewTile(
                                work: work,
                                label: overrides[work.id]?.displayLabel,
                                tilt: cardTilt(for: index)
                            )
                                .frame(width: 184)
                        }
                        .buttonStyle(.plain)
                    }
                    if works.isEmpty {
                        savingPlaceholder
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var savingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(VolioTheme.accent)
            Text("Saving photos...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VolioTheme.mutedInk)
        }
        .frame(width: 184, height: 224)
        .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func cardTilt(for index: Int) -> Double {
        let values = [-2.8, 1.8, -1.2, 2.4]
        return values[index % values.count]
    }

    private var footerActions: some View {
        VStack(spacing: 10) {
            Button {
                let inputs = overrides.mapValues(\.input)
                session.updateCreationTime(workIDs: workIDs, createdAround: batchDraft.input, overrides: inputs)
                session.flushMacSyncBatch()
                dismiss()
            } label: {
                Label("Place in Timeline", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(VolioTheme.accent)
            .controlSize(.large)

            Button {
                session.flushMacSyncBatch()
                dismiss()
            } label: {
                Text("Remember later")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .controlSize(.large)
        }
    }

    private var overrideTarget: LocalWork? {
        guard let overrideWorkID else { return nil }
        return works.first(where: { $0.id == overrideWorkID }) ?? session.works.first(where: { $0.id == overrideWorkID })
    }
}

struct CreationTimePicker: View {
    var title: String
    @Binding var draft: CreationTimeDraft
    private let seasons = ["spring", "summer", "fall", "winter"]
    private let currentYear = Calendar.current.component(.year, from: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(VolioTheme.mutedInk)
                .textCase(.uppercase)

            FlowLayout(spacing: 8, rowSpacing: 8) {
                ForEach(CreationTimeDraftMode.allCases) { mode in
                    Button {
                        draft.mode = mode
                    } label: {
                        Text(mode.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(draft.mode == mode ? VolioTheme.accent.opacity(0.16) : Color.white.opacity(0.72), in: Capsule())
                            .foregroundStyle(draft.mode == mode ? VolioTheme.accent : VolioTheme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }

            modeControls
        }
        .padding(16)
        .background(VolioTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var modeControls: some View {
        switch draft.mode {
        case .recent:
            Label("Use the captured date as the creation time.", systemImage: "calendar.badge.clock")
                .font(.subheadline)
                .foregroundStyle(VolioTheme.mutedInk)
        case .age:
            Stepper("Age \(draft.selectedAge)", value: $draft.selectedAge, in: 0...30)
                .font(.headline)
        case .ageRange:
            VStack(spacing: 8) {
                Stepper("From age \(draft.ageStart)", value: $draft.ageStart, in: 0...30)
                Stepper("To age \(max(draft.ageStart, draft.ageEnd))", value: $draft.ageEnd, in: draft.ageStart...30)
            }
            .font(.headline)
        case .year:
            Picker("Year", selection: $draft.selectedYear) {
                ForEach((2000...currentYear).reversed(), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
        case .season:
            HStack {
                Picker("Season", selection: $draft.selectedSeason) {
                    ForEach(seasons, id: \.self) { season in
                        Text(season.capitalized).tag(season)
                    }
                }
                Picker("Year", selection: $draft.selectedYear) {
                    ForEach((2000...currentYear).reversed(), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 128)
        case .lifeStage:
            TextField("Kindergarten, first grade...", text: $draft.lifeStageLabel)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
        case .unknown:
            Label("Volio will gently resurface these in Timeline later.", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(VolioTheme.mutedInk)
        }
    }
}

private struct BatchReviewTile: View {
    var work: LocalWork
    var label: String?
    var tilt: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalThumbnail(
                path: work.thumbnailPath ?? work.originalPath,
                workId: work.id,
                targetSize: CGSize(width: 420, height: 420)
            )
                .aspectRatio(work.imageAspectRatio, contentMode: .fill)
                .frame(height: 172)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: VolioTheme.ink.opacity(0.12), radius: 12, y: 8)
                .rotationEffect(.degrees(tilt))
            if let label {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VolioTheme.accent)
                    .lineLimit(1)
            } else {
                Text("Batch time")
                    .font(.caption2)
                    .foregroundStyle(VolioTheme.mutedInk)
                    .lineLimit(1)
            }
        }
    }
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
    var targetSize = CGSize(width: 240, height: 240)

    var body: some View {
        CachedArtworkImage(
            workID: workId,
            thumbnailPath: path,
            originalPath: inferredOriginalPath(from: path),
            targetSize: targetSize
        )
        .background(.quaternary)
    }

    private func inferredOriginalPath(from path: String?) -> String? {
        guard let path, path.hasSuffix("thumbnail.jpg") else { return path }
        return URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("original.jpg").path
    }
}
