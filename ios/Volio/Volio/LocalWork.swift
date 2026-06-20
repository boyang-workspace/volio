import CoreGraphics
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
    var creationTimeKindRaw: String = CreationTimeKind.capturedDate.rawValue
    var creationDateStart: Date?
    var creationDateEnd: Date?
    var creationYear: Int?
    var creationMonth: Int?
    var creationSeasonRaw: String?
    var creationAgeStartMonths: Int?
    var creationAgeEndMonths: Int?
    var lifeStageID: String?
    var customTimeLabel: String?
    var timeConfidenceRaw: String = TimeConfidence.approximate.rawValue
    var timelinePlacementStateRaw: String = TimelinePlacementState.placed.rawValue
    var reviewStateRaw: String = ReviewState.reviewed.rawValue
    var timelineSortKey: Double?
    var displaySeed: Int64 = 0
    var lastSurfacedAt: Date?
    var surfaceCount: Int = 0
    var snoozedUntil: Date?
    var title: String?
    var note: String?
    var childQuote: String?
    var isFavorite: Bool
    var isRepresentative: Bool = false
    var physicalStatus: String = "undecided"
    var originalPath: String?
    var thumbnailPath: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
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

    var creationTimeKind: CreationTimeKind {
        CreationTimeKind(rawValue: creationTimeKindRaw) ?? CreationTimeKind(rawValue: createdAroundKind) ?? .unknown
    }

    var timeConfidence: TimeConfidence {
        TimeConfidence(rawValue: timeConfidenceRaw) ?? .unknown
    }

    var timelinePlacementState: TimelinePlacementState {
        TimelinePlacementState(rawValue: timelinePlacementStateRaw) ?? .unplaced
    }

    var reviewState: ReviewState {
        ReviewState(rawValue: reviewStateRaw) ?? .pending
    }

    var isTimeUnplaced: Bool {
        timelinePlacementState == .unplaced || creationTimeKind == .unknown || createdAroundKind == CreationTimeKind.unknown.rawValue
    }

    var createdAroundLabel: String {
        if let label = customTimeLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let start = creationAgeStartMonths {
            let end = creationAgeEndMonths
            return Self.ageRangeLabel(start: start, end: end)
        }
        if let months = createdAroundAgeMonths ?? ageAtCreationMonths {
            return Self.ageLabel(months)
        }
        if creationTimeKind == .year, let year = creationYear ?? createdAroundYear {
            return "\(year)"
        }
        if creationTimeKind == .season,
           let year = creationYear ?? createdAroundYear,
           let season = creationSeasonRaw ?? createdAroundSeason {
            return "\(season.capitalized) \(year)"
        }
        if let year = creationYear ?? createdAroundYear,
           let month = creationMonth ?? createdAroundMonth,
           (1...12).contains(month) {
            return "\(Calendar.current.monthSymbols[month - 1]) \(year)"
        }
        if creationTimeKind == .unknown || timelinePlacementState == .unplaced {
            return "Not remembered yet"
        }
        return capturedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var timelineGroupTitle: String {
        if timelinePlacementState == .unplaced || creationTimeKind == .unknown {
            return "Not remembered yet"
        }
        if let start = creationAgeStartMonths {
            let end = creationAgeEndMonths
            if let end, end != start {
                return "Around Age \(max(0, start) / 12)-\(max(0, end) / 12)"
            }
            return "Age \(max(0, start) / 12)"
        }
        if let months = createdAroundAgeMonths ?? ageAtCreationMonths {
            return "Age \(max(0, months) / 12)"
        }
        if let label = customTimeLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let year = creationYear ?? createdAroundYear {
            return "\(year)"
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

    var imageAspectRatio: CGFloat {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else { return 1 }
        return min(max(CGFloat(pixelWidth) / CGFloat(pixelHeight), 0.55), 1.65)
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
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
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
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.remoteArtworkId = remoteArtworkId
        self.remoteUpdatedAt = remoteUpdatedAt
        self.remoteArtworkJSON = remoteArtworkJSON
        self.localUpdatedAt = localUpdatedAt
        self.lastSyncedAt = lastSyncedAt
        self.isFavorite = false
        self.isRepresentative = false
        self.physicalStatus = "undecided"
        self.processingStatus = "ready"
        ensureFuzzyTimelineFields(profile: nil)
    }
}

enum CreationTimeKind: String, Codable, CaseIterable {
    case exactDate = "exact_date"
    case yearMonth = "year_month"
    case season
    case year
    case age
    case ageRange = "age_range"
    case lifeStage = "life_stage"
    case relative
    case capturedDate = "captured_date"
    case unknown
}

enum TimeConfidence: String, Codable, CaseIterable {
    case confirmed
    case approximate
    case suggested
    case unknown
}

enum TimelinePlacementState: String, Codable, CaseIterable {
    case placed
    case approximate
    case unplaced
}

enum ReviewState: String, Codable, CaseIterable {
    case pending
    case reviewed
}

struct CreationTimeDescriptor: Equatable {
    var kind: CreationTimeKind
    var dateStart: Date?
    var dateEnd: Date?
    var year: Int?
    var month: Int?
    var season: String?
    var ageStartMonths: Int?
    var ageEndMonths: Int?
    var lifeStageID: String?
    var label: String?
    var confidence: TimeConfidence
    var placement: TimelinePlacementState
    var reviewState: ReviewState
    var sortKey: Double?
}

struct CreationTimeSnapshot: Equatable {
    var createdAroundKind: String
    var createdAroundYear: Int?
    var createdAroundMonth: Int?
    var createdAroundSeason: String?
    var createdAroundAgeMonths: Int?
    var ageAtCreationMonths: Int?
    var creationTimeKindRaw: String
    var creationDateStart: Date?
    var creationDateEnd: Date?
    var creationYear: Int?
    var creationMonth: Int?
    var creationSeasonRaw: String?
    var creationAgeStartMonths: Int?
    var creationAgeEndMonths: Int?
    var lifeStageID: String?
    var customTimeLabel: String?
    var timeConfidenceRaw: String
    var timelinePlacementStateRaw: String
    var reviewStateRaw: String
    var timelineSortKey: Double?
    var snoozedUntil: Date?

    init(work: LocalWork) {
        createdAroundKind = work.createdAroundKind
        createdAroundYear = work.createdAroundYear
        createdAroundMonth = work.createdAroundMonth
        createdAroundSeason = work.createdAroundSeason
        createdAroundAgeMonths = work.createdAroundAgeMonths
        ageAtCreationMonths = work.ageAtCreationMonths
        creationTimeKindRaw = work.creationTimeKindRaw
        creationDateStart = work.creationDateStart
        creationDateEnd = work.creationDateEnd
        creationYear = work.creationYear
        creationMonth = work.creationMonth
        creationSeasonRaw = work.creationSeasonRaw
        creationAgeStartMonths = work.creationAgeStartMonths
        creationAgeEndMonths = work.creationAgeEndMonths
        lifeStageID = work.lifeStageID
        customTimeLabel = work.customTimeLabel
        timeConfidenceRaw = work.timeConfidenceRaw
        timelinePlacementStateRaw = work.timelinePlacementStateRaw
        reviewStateRaw = work.reviewStateRaw
        timelineSortKey = work.timelineSortKey
        snoozedUntil = work.snoozedUntil
    }

    func restore(to work: LocalWork) {
        work.createdAroundKind = createdAroundKind
        work.createdAroundYear = createdAroundYear
        work.createdAroundMonth = createdAroundMonth
        work.createdAroundSeason = createdAroundSeason
        work.createdAroundAgeMonths = createdAroundAgeMonths
        work.ageAtCreationMonths = ageAtCreationMonths
        work.creationTimeKindRaw = creationTimeKindRaw
        work.creationDateStart = creationDateStart
        work.creationDateEnd = creationDateEnd
        work.creationYear = creationYear
        work.creationMonth = creationMonth
        work.creationSeasonRaw = creationSeasonRaw
        work.creationAgeStartMonths = creationAgeStartMonths
        work.creationAgeEndMonths = creationAgeEndMonths
        work.lifeStageID = lifeStageID
        work.customTimeLabel = customTimeLabel
        work.timeConfidenceRaw = timeConfidenceRaw
        work.timelinePlacementStateRaw = timelinePlacementStateRaw
        work.reviewStateRaw = reviewStateRaw
        work.timelineSortKey = timelineSortKey
        work.snoozedUntil = snoozedUntil
        work.localUpdatedAt = Date()
    }
}

extension LocalWork {
    func applyCreationTime(_ descriptor: CreationTimeDescriptor, markUpdated: Bool = true) {
        creationTimeKindRaw = descriptor.kind.rawValue
        creationDateStart = descriptor.dateStart
        creationDateEnd = descriptor.dateEnd
        creationYear = descriptor.year
        creationMonth = descriptor.month
        creationSeasonRaw = descriptor.season
        creationAgeStartMonths = descriptor.ageStartMonths
        creationAgeEndMonths = descriptor.ageEndMonths
        lifeStageID = descriptor.lifeStageID
        customTimeLabel = descriptor.label
        timeConfidenceRaw = descriptor.confidence.rawValue
        timelinePlacementStateRaw = descriptor.placement.rawValue
        reviewStateRaw = descriptor.reviewState.rawValue
        timelineSortKey = descriptor.sortKey

        createdAroundKind = descriptor.kind.rawValue
        createdAroundYear = descriptor.year
        createdAroundMonth = descriptor.month
        createdAroundSeason = descriptor.season
        createdAroundAgeMonths = descriptor.ageStartMonths == descriptor.ageEndMonths ? descriptor.ageStartMonths : nil
        ageAtCreationMonths = createdAroundAgeMonths
        if markUpdated {
            localUpdatedAt = Date()
        }
    }

    @discardableResult
    func ensureFuzzyTimelineFields(profile: LocalProfile?) -> Bool {
        var didChange = false
        if displaySeed == 0 {
            displaySeed = Self.stableSeed(for: id)
            didChange = true
        }

        if creationTimeKindRaw.isEmpty ||
            (creationTimeKindRaw == CreationTimeKind.capturedDate.rawValue &&
             !createdAroundKind.isEmpty &&
             createdAroundKind != CreationTimeKind.capturedDate.rawValue &&
             creationDateStart == nil &&
             creationAgeStartMonths == nil &&
             creationYear == nil) {
            creationTimeKindRaw = createdAroundKind.isEmpty ? CreationTimeKind.unknown.rawValue : createdAroundKind
            didChange = true
        }

        if creationYear == nil, createdAroundYear != nil {
            creationYear = createdAroundYear
            didChange = true
        }
        if creationMonth == nil, createdAroundMonth != nil {
            creationMonth = createdAroundMonth
            didChange = true
        }
        if creationSeasonRaw == nil, createdAroundSeason != nil {
            creationSeasonRaw = createdAroundSeason
            didChange = true
        }
        if creationAgeStartMonths == nil, let months = createdAroundAgeMonths ?? ageAtCreationMonths {
            creationAgeStartMonths = months
            creationAgeEndMonths = months
            didChange = true
        }

        if timeConfidenceRaw.isEmpty || timeConfidenceRaw == TimeConfidence.approximate.rawValue && creationTimeKind == .unknown {
            timeConfidenceRaw = createdAroundKind == CreationTimeKind.unknown.rawValue ? TimeConfidence.unknown.rawValue : TimeConfidence.approximate.rawValue
            didChange = true
        }

        if timelinePlacementStateRaw.isEmpty ||
            (timelinePlacementStateRaw == TimelinePlacementState.placed.rawValue && creationTimeKind == .unknown) {
            timelinePlacementStateRaw = createdAroundKind == CreationTimeKind.unknown.rawValue ? TimelinePlacementState.unplaced.rawValue : TimelinePlacementState.placed.rawValue
            didChange = true
        }

        if reviewStateRaw.isEmpty {
            reviewStateRaw = ReviewState.reviewed.rawValue
            didChange = true
        }

        if creationDateStart == nil {
            if creationTimeKind == .year, let year = creationYear ?? createdAroundYear {
                creationDateStart = Self.date(year: year, month: 1, day: 1)
                creationDateEnd = Self.date(year: year, month: 12, day: 31)
                didChange = true
            } else if creationTimeKind == .yearMonth,
                      let year = creationYear ?? createdAroundYear,
                      let month = creationMonth ?? createdAroundMonth {
                creationDateStart = Self.date(year: year, month: month, day: 1)
                creationDateEnd = Self.monthEnd(year: year, month: month)
                didChange = true
            } else if creationTimeKind == .season,
                      let year = creationYear ?? createdAroundYear,
                      let season = creationSeasonRaw ?? createdAroundSeason {
                let range = Self.seasonRange(season: season, year: year)
                creationDateStart = range.start
                creationDateEnd = range.end
                didChange = true
            }
        }

        if timelineSortKey == nil {
            timelineSortKey = Self.sortKey(
                dateStart: creationDateStart,
                dateEnd: creationDateEnd,
                ageStartMonths: creationAgeStartMonths ?? createdAroundAgeMonths ?? ageAtCreationMonths,
                ageEndMonths: creationAgeEndMonths,
                year: creationYear ?? createdAroundYear,
                month: creationMonth ?? createdAroundMonth,
                capturedAt: capturedAt,
                placement: timelinePlacementState
            )
            didChange = timelineSortKey != nil || didChange
        }

        if creationTimeKind == .unknown || createdAroundKind == CreationTimeKind.unknown.rawValue {
            if timelinePlacementStateRaw != TimelinePlacementState.unplaced.rawValue {
                timelinePlacementStateRaw = TimelinePlacementState.unplaced.rawValue
                didChange = true
            }
        }

        if creationTimeKind == .capturedDate, createdAroundKind == CreationTimeKind.capturedDate.rawValue {
            if creationDateStart == nil {
                creationDateStart = Calendar.current.startOfDay(for: capturedAt)
                creationDateEnd = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: creationDateStart!)
                creationYear = Calendar.current.component(.year, from: capturedAt)
                creationMonth = Calendar.current.component(.month, from: capturedAt)
                didChange = true
            }
        }

        if let profile,
           creationDateStart == nil,
           let months = creationAgeStartMonths ?? createdAroundAgeMonths ?? ageAtCreationMonths,
           let birthDate = profile.birthDate {
            creationDateStart = Calendar.current.date(byAdding: .month, value: months, to: birthDate)
            creationDateEnd = creationDateStart
            timelineSortKey = creationDateStart?.timeIntervalSince1970
            didChange = true
        }

        return didChange
    }

    static func stableSeed(for id: String) -> Int64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int64(bitPattern: hash == 0 ? 1 : hash)
    }

    static func sortKey(
        dateStart: Date?,
        dateEnd: Date?,
        ageStartMonths: Int?,
        ageEndMonths: Int?,
        year: Int?,
        month: Int?,
        capturedAt: Date,
        placement: TimelinePlacementState
    ) -> Double? {
        guard placement != .unplaced else { return nil }
        if let start = dateStart {
            if let end = dateEnd {
                return (start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2
            }
            return start.timeIntervalSince1970
        }
        if let year, let month {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 15
            return Calendar.current.date(from: comps)?.timeIntervalSince1970
        }
        if let year {
            var comps = DateComponents()
            comps.year = year
            comps.month = 7
            comps.day = 1
            return Calendar.current.date(from: comps)?.timeIntervalSince1970
        }
        if let ageStartMonths {
            let ageEnd = ageEndMonths ?? ageStartMonths
            return 100_000_000 + Double(ageStartMonths + ageEnd) / 2
        }
        return capturedAt.timeIntervalSince1970
    }

    static func ageLabel(_ months: Int) -> String {
        let years = max(0, months) / 12
        let extra = max(0, months) % 12
        return extra == 0 ? "Age \(years)" : "Age \(years)y \(extra)m"
    }

    static func ageRangeLabel(start: Int, end: Int?) -> String {
        guard let end, end != start else { return ageLabel(start) }
        return "Around Age \(max(0, start) / 12)-\(max(0, end) / 12)"
    }

    static func date(year: Int, month: Int, day: Int) -> Date? {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = year
        comps.month = month
        comps.day = day
        return comps.date
    }

    static func monthEnd(year: Int, month: Int) -> Date? {
        guard let start = date(year: year, month: month, day: 1),
              let next = Calendar.current.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return Calendar.current.date(byAdding: .second, value: -1, to: next)
    }

    static func seasonRange(season: String, year: Int) -> (start: Date?, end: Date?) {
        switch season.lowercased() {
        case "spring":
            return (date(year: year, month: 3, day: 1), monthEnd(year: year, month: 5))
        case "summer":
            return (date(year: year, month: 6, day: 1), monthEnd(year: year, month: 8))
        case "fall", "autumn":
            return (date(year: year, month: 9, day: 1), monthEnd(year: year, month: 11))
        case "winter":
            return (date(year: year, month: 12, day: 1), monthEnd(year: year + 1, month: 2))
        default:
            return (date(year: year, month: 1, day: 1), monthEnd(year: year, month: 12))
        }
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
        let metadata = detailDateMetadata
        var artwork = macArtwork ?? Artwork(
            id: remoteArtworkId ?? id,
            childName: profileName,
            title: title,
            description: aiBrief,
            longDescription: aiDescription,
            childQuote: childQuote,
            parentNote: note,
            artworkDate: metadata.date,
            datePrecision: metadata.precision,
            dateNote: metadata.note,
            childAgeMonths: metadata.ageMonths,
            childAgeLabel: ageLabel(metadata.ageMonths),
            createdAroundLabel: createdAroundLabel,
            timelineGroup: timelineGroupTitle,
            workType: workType,
            medium: aiMaterials,
            physicalStatus: physicalStatus,
            width: pixelWidth,
            height: pixelHeight,
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

    private var detailDateMetadata: (date: String?, precision: String?, note: String?, ageMonths: Int?) {
        switch creationTimeKind {
        case .capturedDate:
            return (localDateString(from: capturedAt), "date", "Recently made", createdAroundAgeMonths ?? ageAtCreationMonths)
        case .exactDate:
            return (creationDateStart.map { localDateString(from: $0) }, "date", customTimeLabel, creationAgeStartMonths ?? createdAroundAgeMonths ?? ageAtCreationMonths)
        case .yearMonth:
            if let year = creationYear ?? createdAroundYear,
               let month = creationMonth ?? createdAroundMonth {
                return (String(format: "%04d-%02d", year, month), "month", customTimeLabel, nil)
            }
        case .season:
            if let year = creationYear ?? createdAroundYear,
               let season = creationSeasonRaw ?? createdAroundSeason {
                return ("\(year)", "season", season.capitalized, nil)
            }
        case .year:
            if let year = creationYear ?? createdAroundYear {
                return ("\(year)", "year", customTimeLabel, nil)
            }
        case .age, .ageRange:
            return (nil, "age", createdAroundLabel, creationAgeStartMonths ?? createdAroundAgeMonths ?? ageAtCreationMonths)
        case .lifeStage:
            return (nil, "unknown", createdAroundLabel, nil)
        case .relative, .unknown:
            break
        }
        return (nil, "unknown", "Date unknown", nil)
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
    var idempotencyKey: String
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
        idempotencyKey: String = "",
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
        self.idempotencyKey = idempotencyKey
        self.processorKind = processorKind
        self.status = status
        self.remoteJobId = remoteJobId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
        self.retryCount = retryCount
    }
}
