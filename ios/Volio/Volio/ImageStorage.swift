import UIKit

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
        guard let image = UIImage(data: data) else { return data }
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    static func processingDerivative(from data: Data, maxDimension: CGFloat = 1600) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.jpegData(withCompressionQuality: 0.88) { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
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
