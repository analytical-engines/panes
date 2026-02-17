import AppKit
import Foundation

/// カバー画像の非同期読み込み + インメモリキャッシュ
@MainActor
final class CoverImageLoader {
    static let shared = CoverImageLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var loadingIds: Set<String> = []

    private init() {
        cache.countLimit = 200
    }

    /// キャッシュ確認（同期）
    func coverImage(for id: String) -> NSImage? {
        cache.object(forKey: id as NSString)
    }

    /// 書庫の先頭画像を読み込み
    func loadArchiveCover(id: String, filePath: String, password: String?) async -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard loadingIds.insert(id).inserted else { return nil }
        defer { loadingIds.remove(id) }

        guard let resized = await Self.extractAndResize(
            filePath: filePath, password: password, mode: .cover
        ) else { return nil }
        cache.setObject(resized, forKey: id as NSString)
        return resized
    }

    /// 個別画像のサムネイル読み込み
    func loadImageThumbnail(id: String, filePath: String) async -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard loadingIds.insert(id).inserted else { return nil }
        defer { loadingIds.remove(id) }

        guard let resized = await Self.loadAndResize(filePath: filePath) else { return nil }
        cache.setObject(resized, forKey: id as NSString)
        return resized
    }

    /// 書庫内画像のサムネイル読み込み
    func loadArchivedImageThumbnail(
        id: String, archivePath: String, relativePath: String, password: String?
    ) async -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard loadingIds.insert(id).inserted else { return nil }
        defer { loadingIds.remove(id) }

        guard let resized = await Self.extractAndResize(
            filePath: archivePath, password: password, mode: .specific(relativePath)
        ) else { return nil }
        cache.setObject(resized, forKey: id as NSString)
        return resized
    }

    // MARK: - Private

    private enum ExtractMode: Sendable {
        case cover
        case specific(String)
    }

    nonisolated private static func extractAndResize(
        filePath: String, password: String?, mode: ExtractMode
    ) async -> NSImage? {
        let url = URL(fileURLWithPath: filePath)
        let ext = url.pathExtension.lowercased()

        var raw: NSImage?
        switch ext {
        case "zip", "cbz":
            if let reader = await SwiftZipReader.create(url: url, password: password) {
                switch mode {
                case .cover:
                    raw = reader.loadImage(at: 0)
                case .specific(let path):
                    if let i = reader.imageIndex(forName: path) {
                        raw = reader.loadImage(at: i)
                    }
                }
            }
        case "rar", "cbr":
            if let reader = RarReader(url: url, password: password) {
                switch mode {
                case .cover:
                    raw = reader.loadImage(at: 0)
                case .specific(let path):
                    if let i = reader.imageIndex(forName: path) {
                        raw = reader.loadImage(at: i)
                    }
                }
            }
        case "7z", "cb7":
            if let reader = SevenZipReader(url: url) {
                switch mode {
                case .cover:
                    raw = reader.loadImage(at: 0)
                case .specific(let path):
                    if let i = reader.imageIndex(forName: path) {
                        raw = reader.loadImage(at: i)
                    }
                }
            }
        default:
            break
        }

        guard let raw else { return nil }
        return resize(raw, maxHeight: 80)
    }

    nonisolated private static func loadAndResize(filePath: String) async -> NSImage? {
        guard let raw = NSImage(contentsOfFile: filePath) else { return nil }
        return resize(raw, maxHeight: 80)
    }

    nonisolated private static func resize(_ image: NSImage, maxHeight: CGFloat) -> NSImage? {
        let size = image.size
        guard size.height > 0 else { return nil }

        let scale = min(maxHeight / size.height, 1.0)
        if scale >= 1.0 { return image }

        let newW = Int(round(size.width * scale))
        let newH = Int(round(size.height * scale))
        guard newW > 0, newH > 0 else { return nil }

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: newW,
            pixelsHigh: newH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        bitmapRep.size = NSSize(width: newW, height: newH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: newW, height: newH),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: NSSize(width: newW, height: newH))
        result.addRepresentation(bitmapRep)
        return result
    }
}
