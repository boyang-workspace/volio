import Foundation
import SwiftData
import SwiftUI

enum VolioTheme {
    static let paper = Color(red: 0.98, green: 0.975, blue: 0.95)
    static let card = Color(red: 1.0, green: 0.995, blue: 0.975)
    static let ink = Color(red: 0.12, green: 0.13, blue: 0.13)
    static let mutedInk = Color(red: 0.42, green: 0.43, blue: 0.44)
    static let accent = Color(red: 0.94, green: 0.33, blue: 0.20)
    static let ochre = Color(red: 0.94, green: 0.66, blue: 0.20)
    static let moss = Color(red: 0.30, green: 0.56, blue: 0.42)
    static let blue = Color(red: 0.16, green: 0.42, blue: 0.78)
    static let glassTint = Color.white.opacity(0.26)
}

@Model
final class LocalProfile {
    var id: String = UUID().uuidString
    var name: String?
    var birthYear: Int?
    var birthMonth: Int?

    var displayAge: String? {
        guard let year = birthYear else { return nil }
        let age = Calendar.current.component(.year, from: Date()) - year
        return "Age \(age)"
    }

    init(id: String = UUID().uuidString, name: String? = nil, birthYear: Int? = nil, birthMonth: Int? = nil) {
        self.id = id
        self.name = name
        self.birthYear = birthYear
        self.birthMonth = birthMonth
    }

    func ageMonths(at date: Date) -> Int? {
        guard let birthYear else { return nil }
        let month = birthMonth ?? 6
        var birth = DateComponents()
        birth.year = birthYear
        birth.month = month
        birth.day = 1
        guard let birthDate = Calendar.current.date(from: birth), date >= birthDate else { return nil }
        let comps = Calendar.current.dateComponents([.month], from: birthDate, to: date)
        return comps.month
    }
}

@MainActor
@Observable
final class VolioSession {
    var works: [LocalWork] = []
    var macArtworks: [Artwork] = []
    var processingJobs: [LocalProcessingJob] = []
    var isLoading = false
    var errorMessage: String?
    var profile = LocalProfile()
    var pairedBaseURL = ""
    var pairedToken = ""
    var pairedHostName = ""
    var isShowingDetail = false

    private var modelContext: ModelContext?

    func setup(context: ModelContext) {
        modelContext = context
        refreshStoredPairing()
        loadFromSwiftData()
        if isMacPaired {
            Task { await refreshMacLibrary() }
        }
    }

    // MARK: - Local CRUD

    @discardableResult
    func createWork(
        data: Data,
        workType: String = "paper",
        createdAround: CreatedAroundInput = .capturedDate,
        autoProcess: Bool = true
    ) -> LocalWork {
        let id = UUID().uuidString
        let originalPath = ImageStorage.saveOriginal(id: id, data: data)
        let capturedAt = Date()
        let normalized = createdAround.normalized(profile: profile, capturedAt: capturedAt)

        let work = LocalWork(
            id: id,
            createdAt: Date(),
            capturedAt: capturedAt,
            creatorId: profile.id,
            workType: workType,
            createdAroundKind: normalized.kind,
            createdAroundYear: normalized.year,
            createdAroundMonth: normalized.month,
            createdAroundSeason: normalized.season,
            createdAroundAgeMonths: normalized.ageMonths,
            ageAtCreationMonths: normalized.ageMonths,
            originalPath: originalPath,
            thumbnailPath: originalPath
        )
        let originalAsset = LocalAsset(workId: id, role: "original", localPath: originalPath)
        let thumbnailAsset = LocalAsset(workId: id, role: "thumbnail", localPath: originalPath)
        modelContext?.insert(work)
        modelContext?.insert(originalAsset)
        modelContext?.insert(thumbnailAsset)
        works.insert(work, at: 0)
        try? modelContext?.save()

        Task.detached(priority: .utility) { [id] in
            let thumbData = ImageStorage.generateThumbnail(from: data)
            let thumbPath = ImageStorage.saveThumbnail(id: id, data: thumbData)
            Task { @MainActor in
                work.thumbnailPath = thumbPath
                thumbnailAsset.localPath = thumbPath
                try? self.modelContext?.save()
            }
        }

        if autoProcess {
            syncMacLibraryCopy(for: work, data: data)
            enqueueMacProcessing(for: work, assetIds: [originalAsset.id], data: data)
        }
        return work
    }

    func deleteWork(_ work: LocalWork) {
        let remoteId = work.remoteArtworkId
        ImageStorage.deleteWork(work.id)
        modelContext?.delete(work)
        works.removeAll { $0.id == work.id }
        try? modelContext?.save()
        if let remoteId, let client = macClient {
            Task { try? await client.deleteArtwork(id: remoteId) }
        }
    }

    func toggleFavorite(_ work: LocalWork) {
        work.isFavorite.toggle()
        work.localUpdatedAt = Date()
        try? modelContext?.save()
        pushWorkMetadataToMac(work)
    }

    func updateWork(_ work: LocalWork, title: String? = nil, note: String? = nil, childQuote: String? = nil) {
        if let title { work.title = title }
        if let note { work.note = note }
        if let childQuote { work.childQuote = childQuote }
        work.localUpdatedAt = Date()
        try? modelContext?.save()
        pushWorkMetadataToMac(work)
    }

    func retryProcessing(_ work: LocalWork) {
        guard let path = work.originalPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            errorMessage = "Original image is missing."
            return
        }
        enqueueMacProcessing(for: work, assetIds: [], data: data, isRetry: true)
    }

    // MARK: - SwiftData

    private func loadFromSwiftData() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<LocalWork>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        works = (try? context.fetch(descriptor)) ?? []
        let jobDescriptor = FetchDescriptor<LocalProcessingJob>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        processingJobs = (try? context.fetch(jobDescriptor)) ?? []
        migrateLegacyAssetsIfNeeded(context: context)
    }

    private func migrateLegacyAssetsIfNeeded(context: ModelContext) {
        var didChange = false
        for work in works {
            if work.localUpdatedAt == nil {
                work.localUpdatedAt = work.createdAt
                didChange = true
            }
            if work.creatorId == nil {
                work.creatorId = profile.id
                didChange = true
            }
            let workId = work.id
            let assetDescriptor = FetchDescriptor<LocalAsset>(
                predicate: #Predicate { $0.workId == workId }
            )
            let existing = (try? context.fetch(assetDescriptor)) ?? []
            if existing.isEmpty {
                if let path = work.originalPath {
                    context.insert(LocalAsset(workId: work.id, role: "original", localPath: path))
                    didChange = true
                }
                if let path = work.thumbnailPath {
                    context.insert(LocalAsset(workId: work.id, role: "thumbnail", localPath: path))
                    didChange = true
                }
            }
            if work.createdAroundKind.isEmpty {
                work.createdAroundKind = "captured_date"
                didChange = true
            }
        }
        if didChange {
            try? context.save()
        }
    }

    // MARK: - Mac Assist (optional)

    @ObservationIgnored @AppStorage("volio.baseURL") private var storedBaseURL = ""
    @ObservationIgnored @AppStorage("volio.token") private var storedToken = ""
    @ObservationIgnored @AppStorage("volio.hostName") private var storedHostName = ""

    var isMacPaired: Bool {
        !pairedBaseURL.isEmpty && !pairedToken.isEmpty
    }

    var macHostName: String { pairedHostName }

    func pair(with payload: PairingPayload) {
        storedBaseURL = payload.baseURL
        storedToken = payload.token
        storedHostName = payload.hostName ?? URL(string: payload.baseURL)?.host ?? "Volio Desktop"
        refreshStoredPairing()
        Task { await refreshMacLibrary() }
    }

    func forgetMac() {
        storedBaseURL = ""
        storedToken = ""
        storedHostName = ""
        refreshStoredPairing()
        macArtworks = []
    }

    private var macClient: VolioAPIClient? {
        guard isMacPaired else { return nil }
        return VolioAPIClient(baseURL: pairedBaseURL, token: pairedToken)
    }

    func refreshStoredPairing() {
        pairedBaseURL = storedBaseURL
        pairedToken = storedToken
        pairedHostName = storedHostName
    }

    func refreshLibrary(showError: Bool = false) async {
        loadFromSwiftData()
        if isMacPaired {
            await refreshMacLibrary(showError: showError)
        }
    }

    func refreshMacLibrary(showError: Bool = false) async {
        guard let client = macClient else { return }
        do {
            let bootstrap = try await client.bootstrap()
            macArtworks = bootstrap.artworks
            await mergeMacArtworks(bootstrap.artworks, client: client)
        } catch {
            if showError {
                errorMessage = "Could not reach Volio Desktop."
            }
        }
    }

    func refreshWorkFromMac(_ work: LocalWork) async {
        guard let remoteId = work.remoteArtworkId, let client = macClient else { return }
        do {
            let remote = try await client.artwork(id: remoteId)
            await ensureLocalMedia(for: work, remote: remote, client: client)
            apply(remote: remote, to: work)
            work.lastSyncedAt = Date()
            try? modelContext?.save()
        } catch {
            work.processingError = "Could not refresh details from Mac."
            try? modelContext?.save()
        }
    }

    private func enqueueMacProcessing(for work: LocalWork, assetIds: [String], data: Data, isRetry: Bool = false) {
        guard isMacPaired, let client = macClient else {
            work.processingStatus = "waiting_for_mac"
            try? modelContext?.save()
            return
        }
        work.processingStatus = "queued"
        work.processorSource = "mac"
        work.processingError = nil
        let job = LocalProcessingJob(workId: work.id, assetIds: assetIds.joined(separator: ","), status: "queued")
        if isRetry {
            job.retryCount += 1
        }
        modelContext?.insert(job)
        processingJobs.insert(job, at: 0)
        try? modelContext?.save()

        Task {
            await runMacProcessing(job: job, work: work, data: data, client: client)
        }
    }

    private func syncMacLibraryCopy(for work: LocalWork, data: Data) {
        guard isMacPaired, let client = macClient else { return }
        Task {
            do {
                let metadata = macImportMetadata(for: work)
                let response = try await client.importPhotos(
                    [ImportPhoto(data: data, filename: "\(work.id).jpg")],
                    childId: nil,
                    childName: profile.name?.isEmpty == false ? profile.name! : "Creator",
                    batchName: "iPhone Capture",
                    artworkDate: metadata.date,
                    datePrecision: metadata.precision,
                    dateNote: metadata.note,
                    childAgeMonths: work.createdAroundAgeMonths ?? work.ageAtCreationMonths,
                    workType: work.workType,
                    autoAnalyze: true,
                    clientWorkId: work.id
                )
                if let imported = response.imported.first {
                    work.remoteArtworkId = imported.id
                    work.lastSyncedAt = Date()
                    try? modelContext?.save()
                }
                await refreshMacLibrary()
            } catch {
                // Local capture is the source of truth; Mac sync can retry through the next capture or manual refresh.
            }
        }
    }

    private func pushWorkMetadataToMac(_ work: LocalWork) {
        guard isMacPaired, let client = macClient, let remoteId = work.remoteArtworkId else { return }
        Task {
            do {
                let metadata = macImportMetadata(for: work)
                var patch: [String: EncodableValue] = [
                    "title": .string(work.title ?? ""),
                    "parent_note": .string(work.note ?? ""),
                    "child_quote": .string(work.childQuote ?? ""),
                    "date_note": .string(metadata.note),
                    "date_precision": .string(metadata.precision),
                    "work_type": .string(work.workType),
                    "physical_status": .string(work.physicalStatus),
                    "is_favorite": .bool(work.isFavorite),
                    "is_representative": .bool(work.isRepresentative)
                ]
                if !metadata.date.isEmpty {
                    patch["artwork_date"] = .string(metadata.date)
                }
                if let months = work.createdAroundAgeMonths ?? work.ageAtCreationMonths {
                    patch["child_age_months"] = .int(months)
                }
                let remote = try await client.updateArtwork(id: remoteId, patch: patch)
                work.remoteUpdatedAt = remote.updatedAt
                work.lastSyncedAt = Date()
                try? modelContext?.save()
                await refreshMacLibrary()
            } catch {
                work.processingError = "Mac sync failed. Changes are saved on this iPhone."
                try? modelContext?.save()
            }
        }
    }

    private func mergeMacArtworks(_ artworks: [Artwork], client: VolioAPIClient) async {
        let activeRemoteIds = Set(artworks.map(\.id))
        for local in works where local.remoteArtworkId != nil {
            if let remoteId = local.remoteArtworkId, !activeRemoteIds.contains(remoteId), local.lastSyncedAt != nil {
                ImageStorage.deleteWork(local.id)
                modelContext?.delete(local)
            }
        }
        works.removeAll { work in
            guard let remoteId = work.remoteArtworkId, work.lastSyncedAt != nil else { return false }
            return !activeRemoteIds.contains(remoteId)
        }
        try? modelContext?.save()

        for remote in artworks {
            if let local = works.first(where: { $0.id == remote.clientWorkId || $0.remoteArtworkId == remote.id }) {
                local.remoteArtworkId = remote.id
                await ensureLocalMedia(for: local, remote: remote, client: client)
                if shouldApplyRemote(remote, to: local) {
                    apply(remote: remote, to: local)
                    local.lastSyncedAt = Date()
                    try? modelContext?.save()
                } else if let localUpdated = local.localUpdatedAt,
                          let synced = local.lastSyncedAt,
                          localUpdated > synced {
                    pushWorkMetadataToMac(local)
                }
            } else {
                await importRemoteArtwork(remote, client: client)
            }
        }
    }

    private func ensureLocalMedia(for work: LocalWork, remote: Artwork, client: VolioAPIClient) async {
        let expectedOriginal = ImageStorage.originalPath(for: work.id)
        let expectedThumbnail = ImageStorage.thumbnailPath(for: work.id)
        let hasOriginal = ImageStorage.hasOriginal(id: work.id)

        if hasOriginal {
            if work.originalPath != expectedOriginal {
                work.originalPath = expectedOriginal
            }
            if ImageStorage.hasThumbnail(id: work.id), work.thumbnailPath != expectedThumbnail {
                work.thumbnailPath = expectedThumbnail
            }
            return
        }

        guard let data = await downloadRemoteImage(remote, client: client) else {
            work.processingError = "Could not download image from Mac. Pull to sync again."
            return
        }

        work.originalPath = ImageStorage.saveOriginal(id: work.id, data: data)
        work.thumbnailPath = ImageStorage.saveThumbnail(id: work.id, data: ImageStorage.generateThumbnail(from: data))
    }

    private func shouldApplyRemote(_ remote: Artwork, to local: LocalWork) -> Bool {
        guard let remoteDate = Self.serverDate(remote.updatedAt) else { return false }
        let localDate = local.localUpdatedAt ?? local.createdAt
        let lastSync = local.lastSyncedAt ?? .distantPast
        return remoteDate > lastSync && remoteDate >= localDate
    }

    private func apply(remote: Artwork, to local: LocalWork) {
        local.store(remoteArtwork: remote)
        if let title = remote.title, !title.isEmpty { local.title = title }
        if let note = remote.parentNote { local.note = note }
        if let quote = remote.childQuote { local.childQuote = quote }
        local.aiBrief = cleanText(remote.description)
        let longDescription = cleanText(remote.longDescription)
        local.aiDescription = longDescription == local.aiBrief ? nil : longDescription
        if let tags = remote.tags?.map(\.name), !tags.isEmpty { local.aiTags = tags.joined(separator: ", ") }
        if let medium = remote.medium { local.aiMaterials = medium }
        if let workType = remote.workType { local.workType = workType }
        if let physicalStatus = remote.physicalStatus { local.physicalStatus = physicalStatus }
        local.isFavorite = remote.isFavorite?.boolValue ?? local.isFavorite
        local.isRepresentative = remote.isRepresentative?.boolValue ?? local.isRepresentative
        local.remoteUpdatedAt = remote.updatedAt
        local.localUpdatedAt = Self.serverDate(remote.updatedAt) ?? local.localUpdatedAt
    }

    private func importRemoteArtwork(_ remote: Artwork, client: VolioAPIClient) async {
        guard let data = await downloadRemoteImage(remote, client: client) else {
            errorMessage = "Could not download an image from Volio Desktop."
            return
        }
        let work = createWork(
            data: data,
            workType: remote.workType ?? "artwork",
            createdAround: createdAroundInput(from: remote),
            autoProcess: false
        )
        work.remoteArtworkId = remote.id
        work.remoteUpdatedAt = remote.updatedAt
        apply(remote: remote, to: work)
        work.lastSyncedAt = Date()
        try? modelContext?.save()
    }

    private func downloadRemoteImage(_ remote: Artwork, client: VolioAPIClient) async -> Data? {
        let candidates = [
            remote.originalAbsoluteURL,
            remote.displayAbsoluteURL,
            remote.thumbnailAbsoluteURL
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        for rawURL in candidates {
            if let data = try? await client.imageData(from: rawURL), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private func createdAroundInput(from remote: Artwork) -> CreatedAroundInput {
        if let months = remote.childAgeMonths {
            return .ageYears(max(0, months) / 12)
        }
        if let date = remote.artworkDate, let year = Int(date.prefix(4)) {
            return .year(year)
        }
        return .unknown
    }

    private static func serverDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func macImportMetadata(for work: LocalWork) -> (date: String, precision: String, note: String) {
        if work.createdAroundKind == "age" {
            return ("", "age", work.createdAroundLabel)
        }
        if work.createdAroundKind == "season", let year = work.createdAroundYear, let season = work.createdAroundSeason {
            return ("\(year)", "season", season.capitalized)
        }
        if work.createdAroundKind == "year", let year = work.createdAroundYear {
            return ("\(year)", "year", "")
        }
        if work.createdAroundKind == "unknown" {
            return ("", "unknown", "Date unknown")
        }
        return (Self.dayFormatter.string(from: work.capturedAt), "day", "")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func runMacProcessing(job: LocalProcessingJob, work: LocalWork, data: Data, client: VolioAPIClient) async {
        do {
            job.status = "uploading"
            work.processingStatus = "uploading"
            job.updatedAt = Date()
            try? modelContext?.save()
            let response = try await client.createProcessingJob(work: work, imageData: ImageStorage.processingDerivative(from: data))
            job.remoteJobId = response.id
            job.status = response.status
            work.processingStatus = response.status
            job.updatedAt = Date()
            apply(processorResponse: response, to: work, job: job)
            try? modelContext?.save()
            if response.status != "succeeded", response.status != "failed" {
                try await pollMacProcessing(job: job, work: work, client: client)
            }
        } catch {
            job.status = "failed"
            job.errorMessage = error.localizedDescription
            job.updatedAt = Date()
            work.processingStatus = "failed"
            work.processingError = error.localizedDescription
            errorMessage = "Mac Assist could not process a work."
            try? modelContext?.save()
        }
    }

    private func pollMacProcessing(job: LocalProcessingJob, work: LocalWork, client: VolioAPIClient) async throws {
        guard let remoteJobId = job.remoteJobId else { return }
        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let response = try await client.processingJob(id: remoteJobId)
            job.status = response.status
            job.updatedAt = Date()
            work.processingStatus = response.status
            apply(processorResponse: response, to: work, job: job)
            try? modelContext?.save()
            if response.status == "succeeded" || response.status == "failed" {
                return
            }
        }
        job.status = "failed"
        job.errorMessage = "Mac Assist took too long. Try again later."
        work.processingStatus = "failed"
        work.processingError = job.errorMessage
        try? modelContext?.save()
    }

    private func apply(processorResponse response: ProcessorJobResponse, to work: LocalWork, job: LocalProcessingJob) {
        if let result = response.result {
            work.aiTitle = result.title
            work.aiBrief = cleanText(result.description)
            let longDescription = cleanText(result.longDescription)
            work.aiDescription = longDescription == work.aiBrief ? nil : longDescription
            work.aiTags = result.tags?.joined(separator: ", ")
            work.aiMaterials = result.materials?.joined(separator: ", ")
            work.aiThemes = result.themes?.joined(separator: ", ")
            work.aiColors = result.colors?.joined(separator: ", ")
            work.lastProcessedAt = Date()
            work.processingStatus = "succeeded"
            work.processingError = nil
            job.status = "succeeded"
        } else if response.status == "failed" {
            work.processingStatus = "failed"
            work.processingError = response.errorMessage
            job.status = "failed"
            job.errorMessage = response.errorMessage
        }
    }

    private func cleanText(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

enum CreatedAroundInput: Equatable {
    case capturedDate
    case year(Int)
    case season(String, Int)
    case ageYears(Int)
    case unknown

    func normalized(profile: LocalProfile, capturedAt: Date) -> CreatedAroundNormalized {
        switch self {
        case .capturedDate:
            let comps = Calendar.current.dateComponents([.year, .month], from: capturedAt)
            return CreatedAroundNormalized(
                kind: "captured_date",
                year: comps.year,
                month: comps.month,
                season: nil,
                ageMonths: profile.ageMonths(at: capturedAt)
            )
        case .year(let year):
            return CreatedAroundNormalized(kind: "year", year: year, month: nil, season: nil, ageMonths: nil)
        case .season(let season, let year):
            return CreatedAroundNormalized(kind: "season", year: year, month: nil, season: season, ageMonths: nil)
        case .ageYears(let years):
            return CreatedAroundNormalized(kind: "age", year: nil, month: nil, season: nil, ageMonths: years * 12)
        case .unknown:
            return CreatedAroundNormalized(kind: "unknown", year: nil, month: nil, season: nil, ageMonths: nil)
        }
    }
}

struct CreatedAroundNormalized {
    var kind: String
    var year: Int?
    var month: Int?
    var season: String?
    var ageMonths: Int?
}
