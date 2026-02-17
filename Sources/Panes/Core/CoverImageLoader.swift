import AppKit
import Foundation

/// カバー画像の非同期読み込み + インメモリキャッシュ
@MainActor
final class CoverImageLoader {
    static let shared = CoverImageLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var imageCountCache: [String: Int] = [:]
    private var loadingIds: Set<String> = []

    private init() {
        cache.countLimit = 200
    }

    /// キャッシュ確認（同期）
    func coverImage(for id: String) -> NSImage? {
        cache.object(forKey: id as NSString)
    }

    /// 書庫の画像数を取得（カバー画像読み込み後に利用可能）
    func imageCount(for id: String) -> Int? {
        imageCountCache[id]
    }

    /// 書庫のカバー画像を読み込み（coverIndex: ページ設定を考慮した表示上の1ページ目）
    func loadArchiveCover(id: String, filePath: String, password: String?, coverIndex: Int = 0) async -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard loadingIds.insert(id).inserted else { return nil }
        defer { loadingIds.remove(id) }

        let result = await Self.extractAndResize(
            filePath: filePath, password: password, mode: .cover(index: coverIndex)
        )
        if let count = result.imageCount {
            imageCountCache[id] = count
        }
        guard let resized = result.image else { return nil }
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
        ).image else { return nil }
        cache.setObject(resized, forKey: id as NSString)
        return resized
    }

    // MARK: - Private

    private enum ExtractMode: Sendable {
        case cover(index: Int)
        case specific(String)
    }

    nonisolated private static func extractAndResize(
        filePath: String, password: String?, mode: ExtractMode
    ) async -> (image: NSImage?, imageCount: Int?) {
        let url = URL(fileURLWithPath: filePath)
        let ext = url.pathExtension.lowercased()

        var raw: NSImage?
        var imageCount: Int?
        switch ext {
        case "zip", "cbz":
            if let reader = await SwiftZipReader.create(url: url, password: password) {
                imageCount = reader.imageCount
                switch mode {
                case .cover(let index):
                    raw = reader.loadImage(at: index)
                case .specific(let path):
                    if let i = reader.imageIndex(forName: path) {
                        raw = reader.loadImage(at: i)
                    }
                }
            }
        case "rar", "cbr":
            if let reader = RarReader(url: url, password: password) {
                imageCount = reader.imageCount
                switch mode {
                case .cover(let index):
                    raw = reader.loadImage(at: index)
                case .specific(let path):
                    if let i = reader.imageIndex(forName: path) {
                        raw = reader.loadImage(at: i)
                    }
                }
            }
        case "7z", "cb7":
            if let reader = SevenZipReader(url: url) {
                imageCount = reader.imageCount
                switch mode {
                case .cover(let index):
                    raw = reader.loadImage(at: index)
                case .specific(let path):
                    if let i = reader.imageIndex(forName: path) {
                        raw = reader.loadImage(at: i)
                    }
                }
            }
        default:
            // フォルダの場合
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory),
               isDirectory.boolValue,
               let source = FileImageSource(urls: [url]) {
                imageCount = source.imageCount
                if case .cover(let index) = mode {
                    raw = source.loadImage(at: index)
                }
            }
        }

        guard let raw else { return (nil, imageCount) }
        return (resize(raw, maxHeight: 192), imageCount)
    }

    nonisolated private static func loadAndResize(filePath: String) async -> NSImage? {
        guard let raw = NSImage(contentsOfFile: filePath) else { return nil }
        return resize(raw, maxHeight: 192)
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
