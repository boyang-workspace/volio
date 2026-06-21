import ImageIO
import OSLog
import SwiftUI
import UIKit

enum VolioPerformance {
    static let log = OSLog(subsystem: "com.volio.app", category: "performance")

    static func begin(_ name: StaticString, _ message: StaticString = "") {
        os_signpost(.begin, log: log, name: name, message)
    }

    static func end(_ name: StaticString, _ message: StaticString = "") {
        os_signpost(.end, log: log, name: name, message)
    }

    static func event(_ name: StaticString, _ message: StaticString = "") {
        os_signpost(.event, log: log, name: name, message)
    }
}

struct IngestedImage {
    var workID: String
    var originalPath: String
    var thumbnailPath: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var checksum: String
}

actor ImageIngestService {
    static let shared = ImageIngestService()

    func ingest(data: Data, workID: String = UUID().uuidString, previewData: Data? = nil) async -> IngestedImage {
        VolioPerformance.begin("capture_ingest")
        let originalPath = ImageStorage.saveOriginal(id: workID, data: data)
        let metadata = ImageStorage.imageMetadata(from: data)
        let checksum = ImageStorage.stableDataChecksum(data)

        var thumbnailPath: String?
        let thumbData = ImageStorage.generateThumbnail(from: data, maxDimension: 900)
        if !thumbData.isEmpty {
            thumbnailPath = ImageStorage.saveThumbnail(id: workID, data: thumbData)
        }
        VolioPerformance.end("capture_ingest")
        return IngestedImage(
            workID: workID,
            originalPath: originalPath,
            thumbnailPath: thumbnailPath,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            checksum: checksum
        )
    }

    func data(at path: String) async -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }
}

struct ArtworkImageMetadata: Hashable {
    var pixelWidth: Int?
    var pixelHeight: Int?

    var aspectRatio: CGFloat? {
        guard let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 else { return nil }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }
}

struct ArtworkImageResult {
    var image: UIImage
    var metadata: ArtworkImageMetadata
}

final class ArtworkImagePipeline: NSObject {
    static let shared = ArtworkImagePipeline()
    private let cache = NSCache<NSString, UIImage>()
    private let metadataCache = NSCache<NSString, ArtworkImageMetadataBox>()

    private override init() {
        super.init()
        cache.countLimit = 260
        cache.totalCostLimit = 64 * 1024 * 1024
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func cachedImage(
        workID: String?,
        thumbnailPath: String?,
        originalPath: String?,
        targetPixelSize: CGSize
    ) async -> ArtworkImageResult? {
        let candidate = imageCandidate(
            workID: workID,
            thumbnailPath: thumbnailPath,
            originalPath: originalPath,
            targetPixelSize: targetPixelSize
        )
        guard let path = candidate.path else { return nil }
        let key = cacheKey(path: path, workID: workID, targetPixelSize: targetPixelSize)
        if let image = cache.object(forKey: key as NSString) {
            VolioPerformance.event("thumbnail_cache_hit")
            let metadata = metadataCache.object(forKey: key as NSString)?.metadata ?? ArtworkImageMetadata(pixelWidth: Int(image.size.width), pixelHeight: Int(image.size.height))
            return ArtworkImageResult(image: image, metadata: metadata)
        }

        VolioPerformance.begin("thumbnail_decode")
        let result = await Task.detached(priority: .utility) {
            Self.downsample(path: path, targetPixelSize: targetPixelSize)
        }.value
        VolioPerformance.end("thumbnail_decode")
        guard let result else { return nil }
        let cost = Int(result.image.size.width * result.image.size.height * max(result.image.scale, 1) * 4)
        cache.setObject(result.image, forKey: key as NSString, cost: cost)
        metadataCache.setObject(ArtworkImageMetadataBox(result.metadata), forKey: key as NSString)
        return result
    }

    @objc private func clearCache() {
        cache.removeAllObjects()
        metadataCache.removeAllObjects()
    }

    private func imageCandidate(
        workID: String?,
        thumbnailPath: String?,
        originalPath: String?,
        targetPixelSize: CGSize
    ) -> (path: String?, role: String) {
        let thumbnailCandidates = [
            (workID.map(ImageStorage.thumbnailPath(for:)), "thumbnail"),
            (thumbnailPath, "thumbnail")
        ]
        let originalCandidates = [
            (workID.map(ImageStorage.originalPath(for:)), "original"),
            (originalPath, "original")
        ]
        let candidates = max(targetPixelSize.width, targetPixelSize.height) > 520
            ? originalCandidates + thumbnailCandidates
            : thumbnailCandidates + originalCandidates
        for candidate in candidates {
            if let path = candidate.0, FileManager.default.fileExists(atPath: path) {
                return (path, candidate.1)
            }
        }
        return (nil, "")
    }

    private func cacheKey(path: String, workID: String?, targetPixelSize: CGSize) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        return [
            workID ?? "no-work",
            path,
            "\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))",
            "\(Int(modified))",
            "\(size)"
        ].joined(separator: "|")
    }

    private static func downsample(path: String, targetPixelSize: CGSize) -> ArtworkImageResult? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        let maxDimension = max(80, max(targetPixelSize.width, targetPixelSize.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return ArtworkImageResult(
            image: UIImage(cgImage: cgImage),
            metadata: ArtworkImageMetadata(pixelWidth: width ?? cgImage.width, pixelHeight: height ?? cgImage.height)
        )
    }
}

private final class ArtworkImageMetadataBox {
    let metadata: ArtworkImageMetadata
    init(_ metadata: ArtworkImageMetadata) {
        self.metadata = metadata
    }
}

struct CachedArtworkImage: View {
    var workID: String?
    var thumbnailPath: String?
    var originalPath: String?
    var targetSize: CGSize
    var contentMode: ContentMode = .fill
    var aspectRatio: CGFloat = 1
    var onMetadata: (ArtworkImageMetadata) -> Void = { _ in }

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var displayedKey = ""
    @State private var loadKey = ""

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.06))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(VolioTheme.mutedInk.opacity(0.34))
                }
                .opacity(image == nil || displayedKey != key ? 1 : 0)

            if let image, displayedKey == key {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: displayedKey)
        .task(id: key) {
            await load()
        }
    }

    private var key: String {
        [
            workID ?? "",
            thumbnailPath ?? "",
            originalPath ?? "",
            "\(Int(targetSize.width * displayScale))x\(Int(targetSize.height * displayScale))"
        ].joined(separator: "|")
    }

    @MainActor
    private func load() async {
        let requestedKey = key
        guard loadKey != requestedKey || displayedKey != requestedKey else { return }
        loadKey = requestedKey
        let pixelSize = CGSize(
            width: max(80, targetSize.width * displayScale),
            height: max(80, targetSize.height * displayScale)
        )
        guard let result = await ArtworkImagePipeline.shared.cachedImage(
            workID: workID,
            thumbnailPath: thumbnailPath,
            originalPath: originalPath,
            targetPixelSize: pixelSize
        ) else { return }
        guard loadKey == requestedKey, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            image = result.image
            displayedKey = requestedKey
        }
        onMetadata(result.metadata)
    }
}

enum ImageStorage {
    private static let fm = FileManager.default

    private static var libraryDir: URL {
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VolioLibrary", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func workDir(_ id: String) -> URL {
        let dir = libraryDir.appendingPathComponent(id, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func saveOriginal(id: String, data: Data) -> String {
        let url = originalFileURL(for: id)
        try? data.write(to: url)
        return url.path
    }

    @discardableResult
    static func saveThumbnail(id: String, data: Data) -> String {
        let url = thumbnailFileURL(for: id)
        try? data.write(to: url)
        return url.path
    }

    static func originalPath(for id: String) -> String {
        originalFileURL(for: id).path
    }

    static func thumbnailPath(for id: String) -> String {
        thumbnailFileURL(for: id).path
    }

    static func originalURL(for id: String) -> URL? {
        let url = originalFileURL(for: id)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    static func thumbnailURL(for id: String) -> URL? {
        let url = thumbnailFileURL(for: id)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    static func hasOriginal(id: String) -> Bool {
        fm.fileExists(atPath: originalFileURL(for: id).path)
    }

    static func hasThumbnail(id: String) -> Bool {
        fm.fileExists(atPath: thumbnailFileURL(for: id).path)
    }

    static func generateThumbnail(from data: Data, maxDimension: CGFloat = 600) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let uiImage = UIImage(cgImage: cgImage) as UIImage?,
              let jpeg = uiImage.jpegData(compressionQuality: 0.8)
        else {
            return data
        }
        return jpeg
    }

    static func processingDerivative(from data: Data, maxDimension: CGFloat = 1600) -> Data {
        generateThumbnail(from: data, maxDimension: maxDimension)
    }

    static func imageMetadata(from data: Data) -> ArtworkImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ArtworkImageMetadata(pixelWidth: nil, pixelHeight: nil)
        }
        return ArtworkImageMetadata(
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int
        )
    }

    static func stableDataChecksum(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    static func deleteWork(_ id: String) {
        try? fm.removeItem(at: workDir(id))
    }

    private static func originalFileURL(for id: String) -> URL {
        workDir(id).appendingPathComponent("original.jpg")
    }

    private static func thumbnailFileURL(for id: String) -> URL {
        workDir(id).appendingPathComponent("thumbnail.jpg")
    }
}
