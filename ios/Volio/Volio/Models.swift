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

    var birthDate: Date? {
        guard let birthYear else { return nil }
        let month = birthMonth ?? 6
        var birth = DateComponents()
        birth.year = birthYear
        birth.month = month
        birth.day = 1
        return Calendar.current.date(from: birth)
    }

    init(id: String = UUID().uuidString, name: String? = nil, birthYear: Int? = nil, birthMonth: Int? = nil) {
        self.id = id
        self.name = name
        self.birthYear = birthYear
        self.birthMonth = birthMonth
    }

    func ageMonths(at date: Date) -> Int? {
        guard let birthDate, date >= birthDate else { return nil }
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
    private var didSetup = false
    private var isRefreshingMacLibrary = false
    private var deferredRefreshTask: Task<Void, Never>?
    private var macCopyFlushTask: Task<Void, Never>?
    private var pendingMacCopyIDs = Set<String>()

    func setup(context: ModelContext) {
        if didSetup {
            modelContext = context
            return
        }
        VolioPerformance.begin("app_setup")
        didSetup = true
        modelContext = context
        refreshStoredPairing()
        loadFromSwiftData()
        if isMacPaired {
            requestMacLibraryRefresh(delayNanoseconds: 700_000_000)
        }
        VolioPerformance.end("app_setup")
    }

    // MARK: - Local CRUD

    @discardableResult
    func createWork(
        data: Data,
        workType: String = "paper",
        createdAround: CreatedAroundInput = .unknown,
        autoProcess: Bool = true
    ) -> LocalWork {
        let id = UUID().uuidString
        let originalPath = ImageStorage.saveOriginal(id: id, data: data)
        let metadata = ImageStorage.imageMetadata(from: data)
        let capturedAt = Date()
        let normalized = createdAround.normalized(profile: profile, capturedAt: capturedAt)
        let descriptor = createdAround.descriptor(profile: profile, capturedAt: capturedAt)

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
            thumbnailPath: nil,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight
        )
        work.applyCreationTime(descriptor, markUpdated: false)
        let originalChecksum = ImageStorage.stableDataChecksum(data)
        let originalAsset = LocalAsset(
            workId: id,
            role: "original",
            localPath: originalPath,
            width: metadata.pixelWidth,
            height: metadata.pixelHeight,
            checksum: originalChecksum
        )
        modelContext?.insert(work)
        modelContext?.insert(originalAsset)
        works.insert(work, at: 0)
        try? modelContext?.save()

        Task.detached(priority: .utility) { [id] in
            let thumbData = ImageStorage.generateThumbnail(from: data)
            let thumbPath = ImageStorage.saveThumbnail(id: id, data: thumbData)
            Task { @MainActor in
                work.thumbnailPath = thumbPath
                let thumbnailAsset = LocalAsset(
                    workId: id,
                    role: "thumbnail",
                    localPath: thumbPath,
                    width: metadata.pixelWidth,
                    height: metadata.pixelHeight,
                    checksum: originalChecksum
                )
                self.modelContext?.insert(thumbnailAsset)
                try? self.modelContext?.save()
            }
        }

        if autoProcess {
            enqueueMacLibraryCopy(for: work)
            enqueueMacProcessing(for: work, assetIds: [originalAsset.id], data: data)
        }
        return work
    }

    @discardableResult
    func createWorkAsync(
        data: Data,
        previewData: Data? = nil,
        workType: String = "paper",
        createdAround: CreatedAroundInput = .unknown,
        autoProcess: Bool = true
    ) async -> LocalWork {
        let ingested = await ImageIngestService.shared.ingest(data: data, previewData: previewData)
        return insertIngestedWork(
            ingested,
            workType: workType,
            createdAround: createdAround,
            autoProcess: autoProcess,
            processingData: data
        )
    }

    @discardableResult
    private func insertIngestedWork(
        _ ingested: IngestedImage,
        workType: String,
        createdAround: CreatedAroundInput,
        autoProcess: Bool,
        processingData: Data?
    ) -> LocalWork {
        let capturedAt = Date()
        let normalized = createdAround.normalized(profile: profile, capturedAt: capturedAt)
        let descriptor = createdAround.descriptor(profile: profile, capturedAt: capturedAt)
        let work = LocalWork(
            id: ingested.workID,
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
            originalPath: ingested.originalPath,
            thumbnailPath: ingested.thumbnailPath,
            pixelWidth: ingested.pixelWidth,
            pixelHeight: ingested.pixelHeight
        )
        work.applyCreationTime(descriptor, markUpdated: false)
        let originalAsset = LocalAsset(
            workId: work.id,
            role: "original",
            localPath: ingested.originalPath,
            width: ingested.pixelWidth,
            height: ingested.pixelHeight,
            checksum: ingested.checksum
        )
        modelContext?.insert(work)
        modelContext?.insert(originalAsset)
        if let thumbnailPath = ingested.thumbnailPath {
            modelContext?.insert(LocalAsset(
                workId: work.id,
                role: "thumbnail",
                localPath: thumbnailPath,
                width: ingested.pixelWidth,
                height: ingested.pixelHeight,
                checksum: ingested.checksum
            ))
        }
        works.insert(work, at: 0)
        try? modelContext?.save()

        if autoProcess {
            enqueueMacLibraryCopy(for: work)
            if let processingData {
                enqueueMacProcessing(for: work, assetIds: [originalAsset.id], data: processingData)
            }
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

    func updateCreationTime(_ work: LocalWork, createdAround: CreatedAroundInput) {
        let descriptor = createdAround.descriptor(profile: profile, capturedAt: work.capturedAt)
        work.applyCreationTime(descriptor)
        work.snoozedUntil = nil
        try? modelContext?.save()
        pushWorkMetadataToMac(work)
    }

    func updateCreationTime(workIDs: [String], createdAround: CreatedAroundInput, overrides: [String: CreatedAroundInput] = [:]) {
        for id in workIDs {
            guard let work = works.first(where: { $0.id == id }) else { continue }
            let input = overrides[id] ?? createdAround
            let descriptor = input.descriptor(profile: profile, capturedAt: work.capturedAt)
            work.applyCreationTime(descriptor)
            work.snoozedUntil = nil
        }
        try? modelContext?.save()
        for id in workIDs {
            if let work = works.first(where: { $0.id == id }) {
                pushWorkMetadataToMac(work)
            }
        }
    }

    func markWorksSurfaced(_ workIDs: [String]) {
        guard !workIDs.isEmpty else { return }
        let now = Date()
        for id in workIDs {
            guard let work = works.first(where: { $0.id == id }) else { continue }
            work.lastSurfacedAt = now
            work.surfaceCount += 1
        }
        try? modelContext?.save()
    }

    func snoozeUnplacedWork(_ work: LocalWork, days: Int = 14) {
        work.snoozedUntil = Calendar.current.date(byAdding: .day, value: days, to: Date())
        work.lastSurfacedAt = Date()
        work.surfaceCount += 1
        work.localUpdatedAt = Date()
        try? modelContext?.save()
    }

    func restoreCreationTime(_ work: LocalWork, snapshot: CreationTimeSnapshot) {
        snapshot.restore(to: work)
        try? modelContext?.save()
        pushWorkMetadataToMac(work)
    }

    func retryProcessing(_ work: LocalWork) {
        guard let path = work.originalPath else {
            errorMessage = "Original image is missing."
            return
        }
        Task {
            guard let data = await ImageIngestService.shared.data(at: path) else {
                errorMessage = "Original image is missing."
                return
            }
            enqueueMacProcessing(for: work, assetIds: [], data: data, isRetry: true)
        }
    }

    // MARK: - SwiftData

    private func loadFromSwiftData() {
        guard let context = modelContext else { return }
        VolioPerformance.begin("swiftdata_fetch")
        let descriptor = FetchDescriptor<LocalWork>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        do {
            works = try context.fetch(descriptor)
        } catch {
            errorMessage = works.isEmpty
                ? "Could not load the iPhone library."
                : "Could not refresh the iPhone library. Showing saved works."
            VolioPerformance.end("swiftdata_fetch")
            return
        }

        let jobDescriptor = FetchDescriptor<LocalProcessingJob>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        do {
            processingJobs = try context.fetch(jobDescriptor)
        } catch {
            processingJobs = []
        }
        VolioPerformance.end("swiftdata_fetch")
        if localMigrationVersion < targetLocalMigrationVersion {
            migrateLegacyAssetsIfNeeded(context: context)
            localMigrationVersion = targetLocalMigrationVersion
        }
    }

    private func migrateLegacyAssetsIfNeeded(context: ModelContext) {
        VolioPerformance.begin("legacy_migration")
        var didChange = false
        let allAssets = (try? context.fetch(FetchDescriptor<LocalAsset>())) ?? []
        let assetsByWorkID = Dictionary(grouping: allAssets, by: \.workId)
        for work in works {
            if work.localUpdatedAt == nil {
                work.localUpdatedAt = work.createdAt
                didChange = true
            }
            if work.creatorId == nil {
                work.creatorId = profile.id
                didChange = true
            }
            let existing = assetsByWorkID[work.id] ?? []
            if existing.isEmpty {
                if let path = work.originalPath {
                    context.insert(LocalAsset(
                        workId: work.id,
                        role: "original",
                        localPath: path,
                        width: work.pixelWidth,
                        height: work.pixelHeight
                    ))
                    didChange = true
                }
                if let path = work.thumbnailPath {
                    context.insert(LocalAsset(
                        workId: work.id,
                        role: "thumbnail",
                        localPath: path,
                        width: work.pixelWidth,
                        height: work.pixelHeight
                    ))
                    didChange = true
                }
            }
            if work.createdAroundKind.isEmpty {
                work.createdAroundKind = "captured_date"
                didChange = true
            }
            if work.ensureFuzzyTimelineFields(profile: profile) {
                didChange = true
            }
        }
        if didChange {
            try? context.save()
        }
        VolioPerformance.end("legacy_migration")
    }

    // MARK: - Mac Assist (optional)

    @ObservationIgnored @AppStorage("volio.baseURL") private var storedBaseURL = ""
    @ObservationIgnored @AppStorage("volio.token") private var storedToken = ""
    @ObservationIgnored @AppStorage("volio.hostName") private var storedHostName = ""
    @ObservationIgnored @AppStorage("volio.localMigrationVersion") private var localMigrationVersion = 0
    private let targetLocalMigrationVersion = 2

    var isMacPaired: Bool {
        !pairedBaseURL.isEmpty && !pairedToken.isEmpty
    }

    var macHostName: String { pairedHostName }

    func pair(with payload: PairingPayload) {
        storedBaseURL = payload.baseURL
        storedToken = payload.token
        storedHostName = payload.hostName ?? URL(string: payload.baseURL)?.host ?? "Volio Desktop"
        refreshStoredPairing()
        requestMacLibraryRefresh(delayNanoseconds: 250_000_000)
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
        if works.isEmpty {
            loadFromSwiftData()
        }
        if isMacPaired {
            await refreshMacLibrary(showError: showError, force: true)
        }
    }

    func refreshMacLibrary(showError: Bool = false, force: Bool = false) async {
        guard let client = macClient else { return }
        if isRefreshingMacLibrary, !force { return }
        isRefreshingMacLibrary = true
        defer { isRefreshingMacLibrary = false }
        do {
            let bootstrap = try await client.bootstrap()
            macArtworks = bootstrap.artworks
            await mergeMacArtworks(bootstrap.artworks, client: client)
        } catch {
            if showError {
                errorMessage = macRefreshErrorMessage(for: error)
            }
        }
    }

    private func macRefreshErrorMessage(for error: Error) -> String {
        if let apiError = error as? VolioAPIError {
            switch apiError {
            case .server(let message):
                if message.localizedCaseInsensitiveContains("pair") ||
                    message.localizedCaseInsensitiveContains("token") ||
                    message.localizedCaseInsensitiveContains("unauthorized") {
                    return "Pair with Volio Desktop again. Showing the iPhone library."
                }
                if !message.isEmpty {
                    return "\(message) Showing the iPhone library."
                }
            }
        }
        return "Volio Desktop is unavailable. Showing the iPhone library."
    }

    func requestMacLibraryRefresh(delayNanoseconds: UInt64 = 900_000_000) {
        guard isMacPaired else { return }
        deferredRefreshTask?.cancel()
        deferredRefreshTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshMacLibrary()
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
        let idempotencyKey = Self.processingIdempotencyKey(work: work, assetIds: assetIds, data: data)
        if let existing = processingJobs.first(where: { job in
            job.processorKind == "mac" &&
            job.idempotencyKey == idempotencyKey &&
            ["pending", "queued", "uploading", "processing", "succeeded", "complete"].contains(job.status)
        }) {
            work.processingStatus = existing.status == "complete" ? "succeeded" : existing.status
            work.processorSource = "mac"
            try? modelContext?.save()
            return
        }
        if !isRetry,
           processingJobs.contains(where: { job in
               job.processorKind == "mac" &&
               job.idempotencyKey == idempotencyKey &&
               job.status == "failed"
           }) {
            work.processingStatus = "failed"
            try? modelContext?.save()
            return
        }
        work.processingStatus = "queued"
        work.processorSource = "mac"
        work.processingError = nil
        let job = LocalProcessingJob(
            workId: work.id,
            assetIds: assetIds.joined(separator: ","),
            idempotencyKey: idempotencyKey,
            status: "queued"
        )
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

    func flushMacSyncBatch() {
        macCopyFlushTask?.cancel()
        macCopyFlushTask = Task(priority: .utility) { [weak self] in
            await self?.flushPendingMacCopies()
        }
    }

    private func enqueueMacLibraryCopy(for work: LocalWork) {
        guard isMacPaired else { return }
        pendingMacCopyIDs.insert(work.id)
        macCopyFlushTask?.cancel()
        macCopyFlushTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushPendingMacCopies()
        }
    }

    private func flushPendingMacCopies() async {
        guard isMacPaired, let client = macClient, !pendingMacCopyIDs.isEmpty else { return }
        VolioPerformance.begin("mac_batch_sync")
        let ids = Array(pendingMacCopyIDs)
        pendingMacCopyIDs.removeAll()

        var groups: [String: MacCopyBatch] = [:]
        for id in ids {
            guard let work = works.first(where: { $0.id == id }),
                  work.remoteArtworkId == nil,
                  let path = work.originalPath,
                  let data = await ImageIngestService.shared.data(at: path)
            else { continue }
            let metadata = macImportMetadata(for: work)
            let key = [
                metadata.date,
                metadata.precision,
                metadata.note,
                metadata.ageMonths.map(String.init) ?? "",
                work.workType
            ].joined(separator: "\u{1F}")
            if groups[key] == nil {
                groups[key] = MacCopyBatch(metadata: metadata, workType: work.workType)
            }
            groups[key]?.items.append(MacCopyItem(work: work, data: data))
        }

        for batch in groups.values {
            do {
                let response = try await client.importPhotos(
                    batch.items.map { ImportPhoto(data: $0.data, filename: "\($0.work.id).jpg") },
                    childId: nil,
                    childName: profile.name?.isEmpty == false ? profile.name! : "Creator",
                    batchName: "iPhone Capture",
                    artworkDate: batch.metadata.date,
                    datePrecision: batch.metadata.precision,
                    dateNote: batch.metadata.note,
                    childAgeMonths: batch.metadata.ageMonths,
                    workType: batch.workType,
                    autoAnalyze: false,
                    clientWorkId: batch.items.count == 1 ? batch.items.first?.work.id : nil,
                    clientWorkIds: batch.items.map { $0.work.id }
                )
                let importedByClientID = Dictionary(uniqueKeysWithValues: response.imported.compactMap { item -> (String, ImportedArtwork)? in
                    guard let clientWorkId = item.clientWorkId, !clientWorkId.isEmpty else { return nil }
                    return (clientWorkId, item)
                })
                for (index, item) in batch.items.enumerated() {
                    let imported = importedByClientID[item.work.id] ?? (response.imported.indices.contains(index) ? response.imported[index] : nil)
                    guard let imported else { continue }
                    item.work.remoteArtworkId = imported.id
                    item.work.remoteUpdatedAt = nil
                    item.work.localUpdatedAt = item.work.localUpdatedAt ?? item.work.createdAt
                    item.work.processingError = nil
                    item.work.lastSyncedAt = Date()
                }
                if !batch.items.isEmpty {
                    try? modelContext?.save()
                }
            } catch {
                for item in batch.items {
                    pendingMacCopyIDs.insert(item.work.id)
                }
            }
        }
        requestMacLibraryRefresh(delayNanoseconds: 250_000_000)
        VolioPerformance.end("mac_batch_sync")
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
                if let months = metadata.ageMonths {
                    patch["child_age_months"] = .int(months)
                }
                let remote = try await client.updateArtwork(id: remoteId, patch: patch)
                work.remoteUpdatedAt = remote.updatedAt
                work.lastSyncedAt = Date()
                try? modelContext?.save()
                requestMacLibraryRefresh(delayNanoseconds: 600_000_000)
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
                if hasLocalOriginal(for: local) {
                    local.remoteArtworkId = nil
                    local.remoteUpdatedAt = nil
                    local.lastSyncedAt = nil
                    local.processingError = "Saved on this iPhone. Volio will copy it to Desktop again."
                    local.localUpdatedAt = local.localUpdatedAt ?? Date()
                    enqueueMacLibraryCopy(for: local)
                } else {
                    local.processingError = "The Desktop copy is missing, and the original is not on this iPhone."
                }
            }
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

    private func hasLocalOriginal(for work: LocalWork) -> Bool {
        if ImageStorage.hasOriginal(id: work.id) {
            return true
        }
        guard let path = work.originalPath else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
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

        let ingested = await ImageIngestService.shared.ingest(data: data, workID: work.id)
        work.originalPath = ingested.originalPath
        work.thumbnailPath = ingested.thumbnailPath
        work.pixelWidth = ingested.pixelWidth
        work.pixelHeight = ingested.pixelHeight
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
        local.pixelWidth = remote.width ?? local.pixelWidth
        local.pixelHeight = remote.height ?? local.pixelHeight
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
        let work = await createWorkAsync(
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
        let precision = remote.datePrecision?.lowercased()
        let dateText = remote.artworkDate ?? ""
        if precision == "date",
           let date = Self.dayFormatter.date(from: dateText) {
            return .exactDate(date)
        }
        if precision == "month",
           dateText.count >= 7,
           let year = Int(dateText.prefix(4)),
           let month = Int(dateText.dropFirst(5).prefix(2)) {
            return .yearMonth(year, month)
        }
        if precision == "season",
           let year = Int(dateText.prefix(4)),
           let season = remote.dateNote?.lowercased(),
           !season.isEmpty {
            return .season(season, year)
        }
        if let year = Int(dateText.prefix(4)) {
            return .year(year)
        }
        if let note = remote.dateNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty,
           note.lowercased() != "date unknown" {
            let id = note.lowercased().replacingOccurrences(of: " ", with: "_")
            return .lifeStage(id, note)
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

    private func macImportMetadata(for work: LocalWork) -> (date: String, precision: String, note: String, ageMonths: Int?) {
        switch work.creationTimeKind {
        case .capturedDate:
            return (Self.dayFormatter.string(from: work.capturedAt), "date", "Recently made", work.createdAroundAgeMonths ?? work.ageAtCreationMonths)
        case .exactDate:
            let date = work.creationDateStart ?? work.capturedAt
            return (Self.dayFormatter.string(from: date), "date", work.customTimeLabel ?? "", work.creationAgeStartMonths ?? work.createdAroundAgeMonths ?? work.ageAtCreationMonths)
        case .yearMonth:
            if let year = work.creationYear ?? work.createdAroundYear,
               let month = work.creationMonth ?? work.createdAroundMonth {
                return (String(format: "%04d-%02d", year, month), "month", work.customTimeLabel ?? "", nil)
            }
        case .season:
            if let year = work.creationYear ?? work.createdAroundYear,
               let season = work.creationSeasonRaw ?? work.createdAroundSeason {
                return ("\(year)", "season", season.capitalized, nil)
            }
        case .year:
            if let year = work.creationYear ?? work.createdAroundYear {
                return ("\(year)", "year", work.customTimeLabel ?? "", nil)
            }
        case .age:
            return ("", "age", work.createdAroundLabel, work.creationAgeStartMonths ?? work.createdAroundAgeMonths ?? work.ageAtCreationMonths)
        case .ageRange:
            return ("", "age", work.createdAroundLabel, work.creationAgeStartMonths ?? work.createdAroundAgeMonths ?? work.ageAtCreationMonths)
        case .lifeStage:
            return ("", "unknown", work.createdAroundLabel, nil)
        case .relative, .unknown:
            break
        }
        return ("", "unknown", "Date unknown", nil)
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

    private static func processingIdempotencyKey(work: LocalWork, assetIds _: [String], data: Data) -> String {
        return [
            work.id,
            ImageStorage.stableDataChecksum(data),
            "analysis-v1"
        ].joined(separator: ":")
    }
}

private struct MacCopyItem {
    var work: LocalWork
    var data: Data
}

private struct MacCopyBatch {
    var metadata: (date: String, precision: String, note: String, ageMonths: Int?)
    var workType: String
    var items: [MacCopyItem] = []
}

enum CreatedAroundInput: Equatable {
    case capturedDate
    case exactDate(Date)
    case yearMonth(Int, Int)
    case year(Int)
    case season(String, Int)
    case ageYears(Int)
    case ageRange(Int, Int)
    case lifeStage(String, String)
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
        case .exactDate(let date):
            let comps = Calendar.current.dateComponents([.year, .month], from: date)
            return CreatedAroundNormalized(
                kind: "exact_date",
                year: comps.year,
                month: comps.month,
                season: nil,
                ageMonths: profile.ageMonths(at: date)
            )
        case .yearMonth(let year, let month):
            return CreatedAroundNormalized(kind: "year_month", year: year, month: month, season: nil, ageMonths: nil)
        case .year(let year):
            return CreatedAroundNormalized(kind: "year", year: year, month: nil, season: nil, ageMonths: nil)
        case .season(let season, let year):
            return CreatedAroundNormalized(kind: "season", year: year, month: nil, season: season, ageMonths: nil)
        case .ageYears(let years):
            return CreatedAroundNormalized(kind: "age", year: nil, month: nil, season: nil, ageMonths: years * 12)
        case .ageRange(let start, let end):
            return CreatedAroundNormalized(kind: "age_range", year: nil, month: nil, season: nil, ageMonths: start * 12)
        case .lifeStage:
            return CreatedAroundNormalized(kind: "life_stage", year: nil, month: nil, season: nil, ageMonths: nil)
        case .unknown:
            return CreatedAroundNormalized(kind: "unknown", year: nil, month: nil, season: nil, ageMonths: nil)
        }
    }

    func descriptor(profile: LocalProfile, capturedAt: Date) -> CreationTimeDescriptor {
        switch self {
        case .capturedDate:
            let start = Calendar.current.startOfDay(for: capturedAt)
            let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start)
            let comps = Calendar.current.dateComponents([.year, .month], from: capturedAt)
            return CreationTimeDescriptor(
                kind: .capturedDate,
                dateStart: start,
                dateEnd: end,
                year: comps.year,
                month: comps.month,
                season: nil,
                ageStartMonths: profile.ageMonths(at: capturedAt),
                ageEndMonths: profile.ageMonths(at: capturedAt),
                lifeStageID: nil,
                label: "Recently made",
                confidence: .confirmed,
                placement: .placed,
                reviewState: .reviewed,
                sortKey: capturedAt.timeIntervalSince1970
            )
        case .exactDate(let date):
            let start = Calendar.current.startOfDay(for: date)
            let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start)
            let comps = Calendar.current.dateComponents([.year, .month], from: date)
            return CreationTimeDescriptor(
                kind: .exactDate,
                dateStart: start,
                dateEnd: end,
                year: comps.year,
                month: comps.month,
                season: nil,
                ageStartMonths: profile.ageMonths(at: date),
                ageEndMonths: profile.ageMonths(at: date),
                lifeStageID: nil,
                label: nil,
                confidence: .confirmed,
                placement: .placed,
                reviewState: .reviewed,
                sortKey: date.timeIntervalSince1970
            )
        case .yearMonth(let year, let month):
            let start = LocalWork.date(year: year, month: month, day: 1)
            let end = LocalWork.monthEnd(year: year, month: month)
            return CreationTimeDescriptor(
                kind: .yearMonth,
                dateStart: start,
                dateEnd: end,
                year: year,
                month: month,
                season: nil,
                ageStartMonths: nil,
                ageEndMonths: nil,
                lifeStageID: nil,
                label: nil,
                confidence: .approximate,
                placement: .approximate,
                reviewState: .reviewed,
                sortKey: LocalWork.sortKey(dateStart: start, dateEnd: end, ageStartMonths: nil, ageEndMonths: nil, year: year, month: month, capturedAt: capturedAt, placement: .approximate)
            )
        case .year(let year):
            let start = LocalWork.date(year: year, month: 1, day: 1)
            let end = LocalWork.monthEnd(year: year, month: 12)
            return CreationTimeDescriptor(
                kind: .year,
                dateStart: start,
                dateEnd: end,
                year: year,
                month: nil,
                season: nil,
                ageStartMonths: nil,
                ageEndMonths: nil,
                lifeStageID: nil,
                label: nil,
                confidence: .approximate,
                placement: .approximate,
                reviewState: .reviewed,
                sortKey: LocalWork.sortKey(dateStart: start, dateEnd: end, ageStartMonths: nil, ageEndMonths: nil, year: year, month: nil, capturedAt: capturedAt, placement: .approximate)
            )
        case .season(let season, let year):
            let range = LocalWork.seasonRange(season: season, year: year)
            return CreationTimeDescriptor(
                kind: .season,
                dateStart: range.start,
                dateEnd: range.end,
                year: year,
                month: nil,
                season: season,
                ageStartMonths: nil,
                ageEndMonths: nil,
                lifeStageID: nil,
                label: "\(season.capitalized) \(year)",
                confidence: .approximate,
                placement: .approximate,
                reviewState: .reviewed,
                sortKey: LocalWork.sortKey(dateStart: range.start, dateEnd: range.end, ageStartMonths: nil, ageEndMonths: nil, year: year, month: nil, capturedAt: capturedAt, placement: .approximate)
            )
        case .ageYears(let years):
            let months = years * 12
            let dates = ageRangeDates(startMonths: months, endMonths: months, profile: profile)
            return CreationTimeDescriptor(
                kind: .age,
                dateStart: dates.start,
                dateEnd: dates.end,
                year: nil,
                month: nil,
                season: nil,
                ageStartMonths: months,
                ageEndMonths: months,
                lifeStageID: nil,
                label: "Age \(years)",
                confidence: .approximate,
                placement: .approximate,
                reviewState: .reviewed,
                sortKey: LocalWork.sortKey(dateStart: dates.start, dateEnd: dates.end, ageStartMonths: months, ageEndMonths: months, year: nil, month: nil, capturedAt: capturedAt, placement: .approximate)
            )
        case .ageRange(let start, let end):
            let startMonths = min(start, end) * 12
            let endMonths = max(start, end) * 12
            let dates = ageRangeDates(startMonths: startMonths, endMonths: endMonths, profile: profile)
            return CreationTimeDescriptor(
                kind: .ageRange,
                dateStart: dates.start,
                dateEnd: dates.end,
                year: nil,
                month: nil,
                season: nil,
                ageStartMonths: startMonths,
                ageEndMonths: endMonths,
                lifeStageID: nil,
                label: "Around Age \(min(start, end))-\(max(start, end))",
                confidence: .approximate,
                placement: .approximate,
                reviewState: .reviewed,
                sortKey: LocalWork.sortKey(dateStart: dates.start, dateEnd: dates.end, ageStartMonths: startMonths, ageEndMonths: endMonths, year: nil, month: nil, capturedAt: capturedAt, placement: .approximate)
            )
        case .lifeStage(let id, let label):
            return CreationTimeDescriptor(
                kind: .lifeStage,
                dateStart: nil,
                dateEnd: nil,
                year: nil,
                month: nil,
                season: nil,
                ageStartMonths: nil,
                ageEndMonths: nil,
                lifeStageID: id,
                label: label,
                confidence: .approximate,
                placement: .approximate,
                reviewState: .reviewed,
                sortKey: nil
            )
        case .unknown:
            return CreationTimeDescriptor(
                kind: .unknown,
                dateStart: nil,
                dateEnd: nil,
                year: nil,
                month: nil,
                season: nil,
                ageStartMonths: nil,
                ageEndMonths: nil,
                lifeStageID: nil,
                label: nil,
                confidence: .unknown,
                placement: .unplaced,
                reviewState: .pending,
                sortKey: nil
            )
        }
    }

    private func ageRangeDates(startMonths: Int, endMonths: Int, profile: LocalProfile) -> (start: Date?, end: Date?) {
        guard let birthDate = profile.birthDate else { return (nil, nil) }
        let start = Calendar.current.date(byAdding: .month, value: startMonths, to: birthDate)
        let end = Calendar.current.date(byAdding: .month, value: endMonths + 12, to: birthDate)
        return (start, end)
    }
}

struct CreatedAroundNormalized {
    var kind: String
    var year: Int?
    var month: Int?
    var season: String?
    var ageMonths: Int?
}
