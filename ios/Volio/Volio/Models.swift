import Foundation
import SwiftUI

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
    var medium: String?
    var thumbnailURL: String?
    var originalURL: String?
    var processedURL: String?
    var displayURL: String?
    var thumbnailAbsoluteURL: String?
    var originalAbsoluteURL: String?
    var processedAbsoluteURL: String?
    var displayAbsoluteURL: String?
    var aiStatus: String?
    var aiError: String?
    var isFavorite: Boolish?
    var isRepresentative: Boolish?
    var tags: [ArtworkTag]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, tags
        case childId = "child_id"
        case childName = "child_name"
        case childBirthDate = "child_birth_date"
        case batchName = "batch_name"
        case longDescription = "long_description"
        case childQuote = "child_quote"
        case parentNote = "parent_note"
        case artworkDate = "artwork_date"
        case datePrecision = "date_precision"
        case dateNote = "date_note"
        case childAgeMonths = "child_age_months"
        case childAgeLabel = "child_age_label"
        case createdAroundLabel = "created_around_label"
        case timelineGroup = "timeline_group"
        case workType = "work_type"
        case medium
        case thumbnailURL = "thumbnail_url"
        case originalURL = "original_url"
        case processedURL = "processed_url"
        case displayURL = "display_url"
        case thumbnailAbsoluteURL = "thumbnail_absolute_url"
        case originalAbsoluteURL = "original_absolute_url"
        case processedAbsoluteURL = "processed_absolute_url"
        case displayAbsoluteURL = "display_absolute_url"
        case aiStatus = "ai_status"
        case aiError = "ai_error"
        case isFavorite = "is_favorite"
        case isRepresentative = "is_representative"
    }
}

enum Boolish: Codable, Hashable {
    case bool(Bool)
    case int(Int)

    var boolValue: Bool {
        switch self {
        case .bool(let value): value
        case .int(let value): value != 0
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .int((try? container.decode(Int.self)) ?? 0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(boolValue)
    }
}

struct QueueStatus: Codable {
    var pending: Int
    var processing: Int
    var failed: Int
    var paused: Bool
    var canProcess: Bool
    var workerActive: Bool?

    enum CodingKeys: String, CodingKey {
        case pending, processing, failed, paused
        case canProcess = "can_process"
        case workerActive = "worker_active"
    }
}

struct OllamaStatus: Codable {
    var url: String
    var model: String
    var ok: Bool
}

struct Bootstrap: Codable {
    var desktop: DesktopInfo
    var ollama: OllamaStatus
    var queue: QueueStatus
    var children: [Child]
    var artworks: [Artwork]
}

struct DesktopInfo: Codable {
    var name: String
    var host: String
    var hostName: String
    var baseURL: String

    enum CodingKeys: String, CodingKey {
        case name, host
        case hostName = "host_name"
        case baseURL = "base_url"
    }
}

struct PairingPayload: Codable {
    var type: String
    var version: Int
    var baseURL: String
    var token: String
    var hostName: String?

    enum CodingKeys: String, CodingKey {
        case type, version, token
        case baseURL = "base_url"
        case hostName = "host_name"
    }
}

struct ImportPhoto: Identifiable, Hashable {
    let id = UUID()
    let data: Data
    let filename: String
}

enum CaptureWorkType: String, CaseIterable, Identifiable {
    case paper
    case object

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .object: "Object"
        }
    }

    var icon: String {
        switch self {
        case .paper: "doc.viewfinder"
        case .object: "cube"
        }
    }

    var subtitle: String {
        switch self {
        case .paper: "Drawings, worksheets, paintings"
        case .object: "Clay, Lego, craft models"
        }
    }
}

enum BatchDateMode: String, CaseIterable, Identifiable {
    case age
    case year
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .age: "Age"
        case .year: "Year"
        case .unknown: "Unknown"
        }
    }
}

@Observable
final class VolioSession {
    @ObservationIgnored @AppStorage("volio.baseURL") private var storedBaseURL = ""
    @ObservationIgnored @AppStorage("volio.token") private var storedToken = ""
    @ObservationIgnored @AppStorage("volio.hostName") private var storedHostName = ""

    var baseURL: String = ""
    var token: String = ""
    var hostName: String = ""
    var children: [Child] = []
    var artworks: [Artwork] = []
    var queue: QueueStatus?
    var ollama: OllamaStatus?
    var selectedChildId: String?
    var errorMessage: String?
    var isLoading = false

    init() {
        baseURL = storedBaseURL
        token = storedToken
        hostName = storedHostName
    }

    var isPaired: Bool {
        !baseURL.isEmpty && !token.isEmpty
    }

    var client: VolioAPIClient? {
        guard isPaired else { return nil }
        return VolioAPIClient(baseURL: baseURL, token: token)
    }

    func pair(with payload: PairingPayload) {
        baseURL = payload.baseURL
        token = payload.token
        hostName = payload.hostName ?? URL(string: payload.baseURL)?.host ?? "Volio Desktop"
        storedBaseURL = baseURL
        storedToken = token
        storedHostName = hostName
    }

    func pair(with url: URL) {
        guard url.scheme == "volio",
              url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let baseURL = components.queryItems?.first(where: { $0.name == "base_url" })?.value,
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return
        }
        let hostName = components.queryItems?.first(where: { $0.name == "host_name" })?.value
        pair(with: PairingPayload(
            type: "volio-ios-pairing",
            version: 1,
            baseURL: baseURL,
            token: token,
            hostName: hostName
        ))
    }

    func forgetPairing() {
        baseURL = ""
        token = ""
        hostName = ""
        children = []
        artworks = []
        queue = nil
        ollama = nil
        storedBaseURL = ""
        storedToken = ""
        storedHostName = ""
    }

    @MainActor
    func refresh() async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do {
            let bootstrap = try await client.bootstrap()
            children = bootstrap.children
            artworks = bootstrap.artworks
            queue = bootstrap.queue
            ollama = bootstrap.ollama
            hostName = bootstrap.desktop.hostName
            storedHostName = hostName
            if selectedChildId == nil || !children.contains(where: { $0.id == selectedChildId }) {
                selectedChildId = children.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
