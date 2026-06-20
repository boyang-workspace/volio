import Foundation

struct VolioAPIClient {
    let baseURL: String
    let token: String

    private var root: URL {
        URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }

    func bootstrap() async throws -> Bootstrap {
        try await get("/api/ios/bootstrap")
    }

    func artworks(childId: String? = nil) async throws -> [Artwork] {
        var query: [URLQueryItem] = []
        if let childId, !childId.isEmpty {
            query.append(URLQueryItem(name: "child_id", value: childId))
        }
        return try await get("/api/ios/artworks", query: query)
    }

    func artwork(id: String) async throws -> Artwork {
        try await get("/api/ios/artworks/\(id)")
    }

    func updateArtwork(id: String, patch: [String: EncodableValue]) async throws -> Artwork {
        let body = try JSONEncoder().encode(patch)
        return try await request("/api/ios/artworks/\(id)", method: "PATCH", body: body)
    }

    func deleteArtwork(id: String) async throws {
        var request = authorizedRequest(path: "/api/ios/artworks/\(id)")
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    func analyzeArtwork(id: String) async throws {
        let _: EmptyResponse = try await request("/api/ios/artworks/\(id)/analyze", method: "POST", body: Data("{}".utf8))
    }

    func queueStatus() async throws -> QueueStatus {
        try await get("/api/ios/ai/queue")
    }

    func addChild(name: String, birthDate: String?) async throws -> Child {
        let body = try JSONEncoder().encode([
            "name": EncodableValue.string(name),
            "birth_date": EncodableValue.string(birthDate ?? "")
        ])
        return try await request("/api/ios/children", method: "POST", body: body)
    }

    func importPhotos(
        _ photos: [ImportPhoto],
        childId: String?,
        childName: String,
        batchName: String,
        artworkDate: String,
        datePrecision: String,
        dateNote: String,
        childAgeMonths: Int?,
        workType: String,
        autoAnalyze: Bool,
        clientWorkId: String? = nil,
        clientWorkIds: [String]? = nil
    ) async throws -> ImportResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "token", value: token, boundary: boundary)
        body.appendMultipartField(name: "child_id", value: childId ?? "", boundary: boundary)
        body.appendMultipartField(name: "child_name", value: childName, boundary: boundary)
        body.appendMultipartField(name: "batch_name", value: batchName, boundary: boundary)
        body.appendMultipartField(name: "artwork_date", value: artworkDate, boundary: boundary)
        body.appendMultipartField(name: "date_precision", value: datePrecision, boundary: boundary)
        body.appendMultipartField(name: "date_note", value: dateNote, boundary: boundary)
        body.appendMultipartField(name: "child_age_months", value: childAgeMonths.map(String.init) ?? "", boundary: boundary)
        body.appendMultipartField(name: "client_work_id", value: clientWorkId ?? "", boundary: boundary)
        body.appendMultipartField(name: "client_work_ids", value: (clientWorkIds ?? []).joined(separator: ","), boundary: boundary)
        body.appendMultipartField(name: "work_type", value: workType, boundary: boundary)
        body.appendMultipartField(name: "auto_analyze", value: autoAnalyze ? "true" : "false", boundary: boundary)
        for photo in photos {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(photo.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(photo.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = authorizedRequest(path: "/api/ios/import")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await send(request)
    }

    func createProcessingJob(work: LocalWork, imageData: Data) async throws -> ProcessorJobResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "token", value: token, boundary: boundary)
        body.appendMultipartField(name: "work_id", value: work.id, boundary: boundary)
        body.appendMultipartField(name: "work_type", value: work.workType, boundary: boundary)
        body.appendMultipartField(name: "created_around_kind", value: work.creationTimeKind.rawValue, boundary: boundary)
        body.appendMultipartField(name: "created_around_label", value: work.createdAroundLabel, boundary: boundary)
        body.appendMultipartField(name: "created_around_year", value: (work.creationYear ?? work.createdAroundYear).map(String.init) ?? "", boundary: boundary)
        body.appendMultipartField(name: "created_around_month", value: (work.creationMonth ?? work.createdAroundMonth).map(String.init) ?? "", boundary: boundary)
        body.appendMultipartField(name: "created_around_season", value: work.creationSeasonRaw ?? work.createdAroundSeason ?? "", boundary: boundary)
        body.appendMultipartField(name: "created_around_age_months", value: (work.creationAgeStartMonths ?? work.createdAroundAgeMonths).map(String.init) ?? "", boundary: boundary)
        body.appendMultipartField(name: "timeline_placement_state", value: work.timelinePlacementStateRaw, boundary: boundary)
        body.appendMultipartField(name: "review_state", value: work.reviewStateRaw, boundary: boundary)
        body.appendMultipartField(name: "title", value: work.title ?? "", boundary: boundary)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(work.id)-processor.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = authorizedRequest(path: "/api/ios/process/jobs")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await send(request)
    }

    func processingJob(id: String) async throws -> ProcessorJobResponse {
        try await get("/api/ios/process/jobs/\(id)")
    }

    func imageData(from absoluteURL: String) async throws -> Data {
        guard let url = URL(string: absoluteURL) else {
            throw VolioAPIError.server("Invalid image URL.")
        }
        var request = authorizedRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: root.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
        }
        var request = authorizedRequest(url: components.url!)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func request<T: Decodable>(_ path: String, method: String, body: Data?) async throws -> T {
        var request = authorizedRequest(path: path)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder.volio.decode(T.self, from: data)
    }

    private func authorizedRequest(path: String) -> URLRequest {
        authorizedRequest(url: root.appending(path: path))
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "X-Volio-Token")
        return request
    }

    private func validate(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let detail = try? JSONDecoder().decode(ServerError.self, from: data).detail {
                throw VolioAPIError.server(detail)
            }
            throw VolioAPIError.server("Volio Desktop returned \(http.statusCode).")
        }
    }
}

struct EmptyResponse: Decodable {}

struct ServerError: Decodable {
    var detail: String
}

enum VolioAPIError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message): message
        }
    }
}

enum EncodableValue: Encodable {
    case string(String)
    case bool(Bool)
    case int(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}

extension JSONDecoder {
    static var volio: JSONDecoder {
        JSONDecoder()
    }
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}

private extension URL {
    func appending(path: String) -> URL {
        appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
