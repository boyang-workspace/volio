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
        self.localUpdatedAt = localUpdatedAt
        self.lastSyncedAt = lastSyncedAt
        self.isFavorite = false
        self.isRepresentative = false
        self.physicalStatus = "undecided"
        self.processingStatus = "ready"
    }
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
