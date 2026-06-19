import Foundation
import SwiftData

@Model
final class LocalWork {
    var id: String
    var createdAt: Date
    var capturedAt: Date
    var creatorId: String?
    var workType: String = "paper"
    var createdAroundKind: String = "captured_date"
    var createdAroundYear: Int?
    var createdAroundMonth: Int?
    var createdAroundSeason: String?
    var createdAroundAgeMonths: Int?
    var ageAtCreationMonths: Int?
    var title: String?
    var note: String?
    var childQuote: String?
    var isFavorite: Bool
    var isRepresentative: Bool = false
    var physicalStatus: String = "undecided"
    var originalPath: String?
    var thumbnailPath: String?
    var remoteArtworkId: String?
    var remoteUpdatedAt: String?
    var remoteArtworkJSON: String?
    var localUpdatedAt: Date?
    var lastSyncedAt: Date?

    var processingStatus: String = "ready"
    var processorSource: String?
    var processingError: String?
    var lastProcessedAt: Date?
    var aiTitle: String?
    var aiBrief: String?
    var aiDescription: String?
    var aiTags: String?
    var aiMaterials: String?
    var aiThemes: String?
    var aiColors: String?

    var displayTitle: String {
        title ?? aiTitle ?? (aiDescription.map { String($0.prefix(40)) } ?? "Untitled")
    }

    var createdAroundLabel: String {
        if let months = createdAroundAgeMonths ?? ageAtCreationMonths {
            let years = max(0, months) / 12
            let extra = max(0, months) % 12
            return extra == 0 ? "Age \(years)" : "Age \(years)y \(extra)m"
        }
        if createdAroundKind == "year", let year = createdAroundYear {
            return "\(year)"
        }
        if createdAroundKind == "season", let year = createdAroundYear, let season = createdAroundSeason {
            return "\(season.capitalized) \(year)"
        }
        if let year = createdAroundYear, let month = createdAroundMonth, (1...12).contains(month) {
            return "\(Calendar.current.monthSymbols[month - 1]) \(year)"
        }
        if createdAroundKind == "unknown" {
            return "Date unknown"
        }
        return capturedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var timelineGroupTitle: String {
        if let months = createdAroundAgeMonths ?? ageAtCreationMonths {
            return "Age \(max(0, months) / 12)"
        }
        if let year = createdAroundYear {
            return "\(year)"
        }
        if createdAroundKind == "unknown" {
            return "Date unknown"
        }
        return Calendar.current.component(.year, from: capturedAt).description
    }

    var searchableText: String {
        [
            title,
            aiTitle,
            note,
            childQuote,
            aiBrief,
            aiDescription,
            aiTags,
            aiMaterials,
            aiThemes,
            aiColors,
            workType,
            isFavorite ? "favorite favorites" : nil,
            isRepresentative ? "representative" : nil,
            physicalStatus,
            createdAroundLabel,
            timelineGroupTitle
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        capturedAt: Date = Date(),
        creatorId: String? = nil,
        workType: String = "paper",
        createdAroundKind: String = "captured_date",
        createdAroundYear: Int? = nil,
        createdAroundMonth: Int? = nil,
        createdAroundSeason: String? = nil,
        createdAroundAgeMonths: Int? = nil,
        ageAtCreationMonths: Int? = nil,
        originalPath: String? = nil,
        thumbnailPath: String? = nil,
        remoteArtworkId: String? = nil,
        remoteUpdatedAt: String? = nil,
        remoteArtworkJSON: String? = nil,
        localUpdatedAt: Date? = Date(),
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.creatorId = creatorId
        self.workType = workType
        self.createdAroundKind = createdAroundKind
        self.createdAroundYear = createdAroundYear
        self.createdAroundMonth = createdAroundMonth
        self.createdAroundSeason = createdAroundSeason
        self.createdAroundAgeMonths = createdAroundAgeMonths
        self.ageAtCreationMonths = ageAtCreationMonths
        self.originalPath = originalPath
        self.thumbnailPath = thumbnailPath
        self.remoteArtworkId = remoteArtworkId
        self.remoteUpdatedAt = remoteUpdatedAt
        self.remoteArtworkJSON = remoteArtworkJSON
        self.localUpdatedAt = localUpdatedAt
        self.lastSyncedAt = lastSyncedAt
        self.isFavorite = false
        self.isRepresentative = false
        self.physicalStatus = "undecided"
        self.processingStatus = "ready"
    }
}

extension LocalWork {
    var macArtwork: Artwork? {
        guard let remoteArtworkJSON,
              let data = remoteArtworkJSON.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder.volio.decode(Artwork.self, from: data)
    }

    func store(remoteArtwork: Artwork) {
        guard let data = try? JSONEncoder().encode(remoteArtwork),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        remoteArtworkJSON = json
    }

    func detailArtwork(profileName: String?) -> Artwork {
        var artwork = macArtwork ?? Artwork(
            id: remoteArtworkId ?? id,
            childName: profileName,
            title: title,
            description: aiBrief,
            longDescription: aiDescription,
            childQuote: childQuote,
            parentNote: note,
            artworkDate: localDateString(from: capturedAt),
            datePrecision: createdAroundKind,
            dateNote: createdAroundLabel,
            childAgeMonths: createdAroundAgeMonths ?? ageAtCreationMonths,
            childAgeLabel: ageLabel(createdAroundAgeMonths ?? ageAtCreationMonths),
            createdAroundLabel: createdAroundLabel,
            timelineGroup: timelineGroupTitle,
            workType: workType,
            medium: aiMaterials,
            physicalStatus: physicalStatus,
            originalFilename: originalPath.map { URL(fileURLWithPath: $0).lastPathComponent },
            aiStatus: processingStatus == "succeeded" ? "completed" : processingStatus,
            aiError: processingError,
            isFavorite: .bool(isFavorite),
            isRepresentative: .bool(isRepresentative),
            clientWorkId: id,
            createdAt: localDateTimeString(from: createdAt),
            updatedAt: localUpdatedAt.map { localDateTimeString(from: $0) },
            tags: localArtworkTags
        )

        artwork.title = title ?? artwork.title
        artwork.description = aiBrief ?? artwork.description
        artwork.longDescription = aiDescription ?? artwork.longDescription
        artwork.childQuote = childQuote ?? artwork.childQuote
        artwork.parentNote = note ?? artwork.parentNote
        artwork.createdAroundLabel = artwork.createdAroundLabel ?? createdAroundLabel
        artwork.timelineGroup = artwork.timelineGroup ?? timelineGroupTitle
        artwork.workType = workType
        artwork.medium = aiMaterials ?? artwork.medium
        artwork.physicalStatus = physicalStatus
        artwork.aiStatus = artwork.aiStatus ?? (processingStatus == "succeeded" ? "completed" : processingStatus)
        artwork.aiError = processingError ?? artwork.aiError
        artwork.isFavorite = .bool(isFavorite)
        artwork.isRepresentative = .bool(isRepresentative)
        artwork.tags = mergeTags(artwork.tags, localArtworkTags)
        return artwork
    }

    private var localArtworkTags: [ArtworkTag]? {
        let typedGroups: [(String?, String)] = [
            (aiTags, "tag"),
            (aiMaterials, "material"),
            (aiThemes, "theme"),
            (aiColors, "color")
        ]
        let tags = typedGroups.flatMap { values, type in
            splitCSV(values).map { ArtworkTag(name: $0, type: type, source: "ios") }
        }
        return tags.isEmpty ? nil : tags
    }

    private func mergeTags(_ primary: [ArtworkTag]?, _ secondary: [ArtworkTag]?) -> [ArtworkTag]? {
        var seen = Set<String>()
        let merged = ((primary ?? []) + (secondary ?? [])).filter { tag in
            let key = "\(tag.type.lowercased()):\(tag.name.lowercased())"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        return merged.isEmpty ? nil : merged
    }

    private func splitCSV(_ value: String?) -> [String] {
        (value ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func ageLabel(_ months: Int?) -> String? {
        guard let months else { return nil }
        let years = max(0, months) / 12
        let extra = max(0, months) % 12
        return extra == 0 ? "Age \(years)" : "Age \(years)y \(extra)m"
    }

    private func localDateString(from date: Date) -> String {
        Self.localDayFormatter.string(from: date)
    }

    private func localDateTimeString(from date: Date) -> String {
        Self.localDateTimeFormatter.string(from: date)
    }

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let localDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}

@Model
final class LocalAsset {
    var id: String
    var workId: String
    var assetType: String
    var role: String
    var localPath: String
    var mimeType: String?
    var width: Int?
    var height: Int?
    var duration: Double?
    var checksum: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        workId: String,
        assetType: String = "image",
        role: String,
        localPath: String,
        mimeType: String? = "image/jpeg",
        width: Int? = nil,
        height: Int? = nil,
        duration: Double? = nil,
        checksum: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workId = workId
        self.assetType = assetType
        self.role = role
        self.localPath = localPath
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.duration = duration
        self.checksum = checksum
        self.createdAt = createdAt
    }
}

@Model
final class LocalProcessingJob {
    var id: String
    var workId: String
    var assetIds: String
    var processorKind: String
    var status: String
    var remoteJobId: String?
    var createdAt: Date
    var updatedAt: Date
    var errorMessage: String?
    var retryCount: Int

    init(
        id: String = UUID().uuidString,
        workId: String,
        assetIds: String = "",
        processorKind: String = "mac",
        status: String = "queued",
        remoteJobId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        errorMessage: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.workId = workId
        self.assetIds = assetIds
        self.processorKind = processorKind
        self.status = status
        self.remoteJobId = remoteJobId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
        self.retryCount = retryCount
    }
}
