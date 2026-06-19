import Foundation

// MARK: - Old API Types (kept for future Mac Assist compatibility)

struct Child: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var birthDate: String?
    var notes: String?
    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case birthDate = "birth_date"
    }
}

struct ArtworkTag: Identifiable, Codable, Hashable {
    var id: String { "\(type):\(name)" }
    let name: String
    let type: String
    let source: String?
}

struct Artwork: Identifiable, Codable, Hashable {
    let id: String
    var childId: String?
    var childName: String?
    var childBirthDate: String?
    var batchName: String?
    var title: String?
    var description: String?
    var longDescription: String?
    var childQuote: String?
    var parentNote: String?
    var artworkDate: String?
    var datePrecision: String?
    var dateNote: String?
    var childAgeMonths: Int?
    var childAgeLabel: String?
    var createdAroundLabel: String?
    var timelineGroup: String?
    var workType: String?
    var stage: String?
    var medium: String?
    var story: String?
    var physicalStatus: String?
    var width: Int?
    var height: Int?
    var originalFilename: String?
    var thumbnailURL: String?
    var originalURL: String?
    var processedURL: String?
    var displayURL: String?
    var thumbnailAbsoluteURL: String?
    var originalAbsoluteURL: String?
    var processedAbsoluteURL: String?
    var displayAbsoluteURL: String?
    var aiStatus: String?
    var aiModel: String?
    var aiLocale: String?
    var aiError: String?
    var isFavorite: Boolish?
    var isRepresentative: Boolish?
    var clientWorkId: String?
    var createdAt: String?
    var updatedAt: String?
    var deletedAt: String?
    var tags: [ArtworkTag]?
    enum CodingKeys: String, CodingKey {
        case id, title, description, tags, medium, stage, story, width, height
        case childId = "child_id", childName = "child_name", childBirthDate = "child_birth_date"
        case batchName = "batch_name", longDescription = "long_description"
        case childQuote = "child_quote", parentNote = "parent_note"
        case artworkDate = "artwork_date", datePrecision = "date_precision", dateNote = "date_note"
        case childAgeMonths = "child_age_months", childAgeLabel = "child_age_label"
        case createdAroundLabel = "created_around_label", timelineGroup = "timeline_group"
        case workType = "work_type"
        case physicalStatus = "physical_status", originalFilename = "original_filename"
        case thumbnailURL = "thumbnail_url", originalURL = "original_url"
        case processedURL = "processed_url", displayURL = "display_url"
        case thumbnailAbsoluteURL = "thumbnail_absolute_url", originalAbsoluteURL = "original_absolute_url"
        case processedAbsoluteURL = "processed_absolute_url", displayAbsoluteURL = "display_absolute_url"
        case aiStatus = "ai_status", aiModel = "ai_model", aiLocale = "ai_locale", aiError = "ai_error"
        case isFavorite = "is_favorite", isRepresentative = "is_representative"
        case clientWorkId = "client_work_id", createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    init(
        id: String,
        childId: String? = nil,
        childName: String? = nil,
        childBirthDate: String? = nil,
        batchName: String? = nil,
        title: String? = nil,
        description: String? = nil,
        longDescription: String? = nil,
        childQuote: String? = nil,
        parentNote: String? = nil,
        artworkDate: String? = nil,
        datePrecision: String? = nil,
        dateNote: String? = nil,
        childAgeMonths: Int? = nil,
        childAgeLabel: String? = nil,
        createdAroundLabel: String? = nil,
        timelineGroup: String? = nil,
        workType: String? = nil,
        stage: String? = nil,
        medium: String? = nil,
        story: String? = nil,
        physicalStatus: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        originalFilename: String? = nil,
        thumbnailURL: String? = nil,
        originalURL: String? = nil,
        processedURL: String? = nil,
        displayURL: String? = nil,
        thumbnailAbsoluteURL: String? = nil,
        originalAbsoluteURL: String? = nil,
        processedAbsoluteURL: String? = nil,
        displayAbsoluteURL: String? = nil,
        aiStatus: String? = nil,
        aiModel: String? = nil,
        aiLocale: String? = nil,
        aiError: String? = nil,
        isFavorite: Boolish? = nil,
        isRepresentative: Boolish? = nil,
        clientWorkId: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        deletedAt: String? = nil,
        tags: [ArtworkTag]? = nil
    ) {
        self.id = id
        self.childId = childId
        self.childName = childName
        self.childBirthDate = childBirthDate
        self.batchName = batchName
        self.title = title
        self.description = description
        self.longDescription = longDescription
        self.childQuote = childQuote
        self.parentNote = parentNote
        self.artworkDate = artworkDate
        self.datePrecision = datePrecision
        self.dateNote = dateNote
        self.childAgeMonths = childAgeMonths
        self.childAgeLabel = childAgeLabel
        self.createdAroundLabel = createdAroundLabel
        self.timelineGroup = timelineGroup
        self.workType = workType
        self.stage = stage
        self.medium = medium
        self.story = story
        self.physicalStatus = physicalStatus
        self.width = width
        self.height = height
        self.originalFilename = originalFilename
        self.thumbnailURL = thumbnailURL
        self.originalURL = originalURL
        self.processedURL = processedURL
        self.displayURL = displayURL
        self.thumbnailAbsoluteURL = thumbnailAbsoluteURL
        self.originalAbsoluteURL = originalAbsoluteURL
        self.processedAbsoluteURL = processedAbsoluteURL
        self.displayAbsoluteURL = displayAbsoluteURL
        self.aiStatus = aiStatus
        self.aiModel = aiModel
        self.aiLocale = aiLocale
        self.aiError = aiError
        self.isFavorite = isFavorite
        self.isRepresentative = isRepresentative
        self.clientWorkId = clientWorkId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.tags = tags
    }
}

enum Boolish: Codable, Hashable {
    case bool(Bool), int(Int)
    var boolValue: Bool {
        switch self { case .bool(let v): v; case .int(let v): v != 0 }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else { self = .int((try? container.decode(Int.self)) ?? 0) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(boolValue)
    }
}

struct QueueStatus: Codable {
    var pending: Int; var processing: Int; var failed: Int; var paused: Bool; var canProcess: Bool; var workerActive: Bool?
    enum CodingKeys: String, CodingKey {
        case pending, processing, failed, paused
        case canProcess = "can_process"; case workerActive = "worker_active"
    }
}

struct OllamaStatus: Codable {
    var url: String; var model: String; var ok: Bool
}

struct Bootstrap: Codable {
    var desktop: DesktopInfo; var ollama: OllamaStatus; var queue: QueueStatus; var children: [Child]; var artworks: [Artwork]
}

struct DesktopInfo: Codable {
    var name: String; var host: String; var hostName: String; var baseURL: String
    enum CodingKeys: String, CodingKey {
        case name, host; case hostName = "host_name"; case baseURL = "base_url"
    }
}

struct PairingPayload: Codable {
    var type: String; var version: Int; var baseURL: String; var token: String; var hostName: String?
    enum CodingKeys: String, CodingKey {
        case type, version, token; case baseURL = "base_url"; case hostName = "host_name"
    }
}

struct ImportPhoto: Identifiable, Hashable {
    let id = UUID(); let data: Data; let filename: String
}

struct ImportResponse: Codable {
    var child: Child?
    var batch: ImportBatch?
    var imported: [ImportedArtwork]
    var autoAnalyze: Bool?

    enum CodingKeys: String, CodingKey {
        case child, batch, imported
        case autoAnalyze = "auto_analyze"
    }
}

struct ImportBatch: Codable, Hashable {
    var id: String
    var name: String?
}

struct ImportedArtwork: Codable, Hashable {
    var id: String
    var originalFilename: String?
    var clientWorkId: String?
    var reused: Bool?

    enum CodingKeys: String, CodingKey {
        case id, reused
        case originalFilename = "original_filename"
        case clientWorkId = "client_work_id"
    }
}

struct ProcessorJobResponse: Codable {
    var id: String
    var status: String
    var workId: String?
    var errorMessage: String?
    var result: ProcessorResult?

    enum CodingKeys: String, CodingKey {
        case id, status, result
        case workId = "work_id"
        case errorMessage = "error_message"
    }
}

struct ProcessorResult: Codable {
    var title: String?
    var description: String?
    var longDescription: String?
    var workType: String?
    var materials: [String]?
    var themes: [String]?
    var objects: [String]?
    var colors: [String]?
    var techniques: [String]?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case title, description, materials, themes, objects, colors, techniques, tags
        case longDescription = "long_description"
        case workType = "work_type"
    }
}

// MARK: - Legacy VolioSession extension for unused views (EditionView, BatchRevealView)

extension VolioSession {
    var editions: [Edition] { [] }
    var children: [Child] { [] }
    var selectedChildId: String? { nil }
    func createEdition(title: String, subtitle: String, workIds: [String], coverWorkId: String?, creatorName: String?) -> Edition {
        Edition(id: UUID().uuidString, title: title, subtitle: subtitle, workIds: workIds, coverWorkId: coverWorkId, creatorName: creatorName, createdAt: Date())
    }
    func editionPage(for edition: Edition) -> EditionPage {
        EditionPage(edition: edition, works: [], coverWork: nil)
    }
    var client: VolioAPIClient? { nil }
}

// MARK: - Edition Types

struct Edition: Identifiable, Codable {
    let id: String; var title: String; var subtitle: String?; var workIds: [String]
    var coverWorkId: String?; var creatorName: String?; var createdAt: Date
    var workCount: Int { workIds.count }
}

struct EditionPage {
    let edition: Edition; let works: [Artwork]; let coverWork: Artwork?
}

enum CaptureWorkType: String, CaseIterable, Identifiable {
    case paper, object
    var id: String { rawValue }
    var title: String { self == .paper ? "Paper" : "Object" }
    var icon: String { self == .paper ? "doc.viewfinder" : "cube" }
    var subtitle: String {
        self == .paper ? "Drawings, worksheets, paintings" : "Clay, Lego, craft models"
    }
}

enum BatchDateMode: String, CaseIterable, Identifiable {
    case age, year, unknown
    var id: String { rawValue }
    var title: String {
        switch self { case .age: "Age"; case .year: "Year"; case .unknown: "Unknown" }
    }
}
