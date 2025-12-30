import Foundation
import AppKit
import ZipArchive

/// swift-zip-archiveを使用したZIPアーカイブリーダー
/// 破損アーカイブやパスワード付きアーカイブにも対応
class SwiftZipReader {
    private let archiveURL: URL
    private var imageEntries: [Zip.FileHeader] = []
    private var password: String?

    /// パスワードが必要かどうか
    private(set) var needsPassword: Bool = false

    /// パスワードが間違っているかどうか
    private(set) var wrongPassword: Bool = false

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド
    static func create(url: URL, password: String? = nil, onPhaseChange: PhaseCallback? = nil) async -> SwiftZipReader? {
        let startTime = CFAbsoluteTimeGetCurrent()

        await onPhaseChange?(L("loading_phase_opening_archive"))

        let reader = SwiftZipReader(url: url, password: password)

        await onPhaseChange?(L("loading_phase_building_image_list"))

        do {
            try ZipArchiveReader.withFile(url.path) { zipReader in
                let extractStart = CFAbsoluteTimeGetCurrent()
                let entries = try zipReader.readDirectory()

                // 画像エントリをフィルタリング
                let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                           "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"])

                reader.imageEntries = entries.filter { entry in
                    let filename = entry.filename.string
                    // __MACOSXやドットファイルを除外
                    guard !filename.contains("__MACOSX"),
                          !filename.contains("/._"),
                          !(filename as NSString).lastPathComponent.hasPrefix("._") else {
                        return false
                    }
                    let ext = (filename as NSString).pathExtension
                    return imageExtensions.contains(ext)
                }.sorted { entry1, entry2 in
                    entry1.filename.string.localizedStandardCompare(entry2.filename.string) == .orderedAscending
                }

                let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
                print("⏱️ SwiftZipReader: Extract & sort time: \(String(format: "%.3f", extractTime))s")
                print("📦 SwiftZipReader: Found \(reader.imageEntries.count) images out of \(entries.count) entries")

                // 暗号化ファイルがあるかチェック
                let hasEncryptedFiles = entries.contains { $0.flags.contains(.encrypted) }
                if hasEncryptedFiles && password == nil {
                    reader.needsPassword = true
                    print("🔐 SwiftZipReader: Password required for encrypted archive")
                }
            }
        } catch {
            let errorString = String(describing: error)
            print("ERROR: SwiftZipReader failed to open archive: \(error)")
            // パスワードが必要な場合
            if errorString.contains("encrypted") || errorString.contains("password") {
                reader.needsPassword = true
                return reader
            }
            return nil
        }

        // パスワードが必要だが提供されていない場合
        if reader.needsPassword && password == nil {
            return reader
        }

        guard reader.imageEntries.count > 0 else {
            print("ERROR: SwiftZipReader: No images found in archive")
            return nil
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ SwiftZipReader: Total init time: \(String(format: "%.3f", totalTime))s")

        return reader
    }

    private init(url: URL, password: String? = nil) {
        self.archiveURL = url
        self.password = password
    }

    /// 画像の総数
    var imageCount: Int {
        return imageEntries.count
    }

    /// 指定されたインデックスの画像を読み込む
    func loadImage(at index: Int) -> NSImage? {
        guard let data = imageData(at: index) else { return nil }
        return NSImage(data: data)
    }

    /// 指定されたインデックスの画像データを取得
    func imageData(at index: Int) -> Data? {
        guard index >= 0 && index < imageEntries.count else {
            print("ERROR: SwiftZipReader: Index out of range: \(index) (total: \(imageEntries.count))")
            return nil
        }

        let entry = imageEntries[index]
        let filename = entry.filename.string

        do {
            var result: Data?
            try ZipArchiveReader.withFile(archiveURL.path) { reader in
                // パスワード付きで読み込み
                let bytes = try reader.readFile(entry, password: password)
                result = Data(bytes)
                print("SwiftZipReader: Extracted \(result?.count ?? 0) bytes for \(filename)")
            }
            return result
        } catch {
            let errorString = String(describing: error)
            // パスワードエラーの判定
            if errorString.contains("encrypted") || errorString.contains("password") {
                needsPassword = true
                print("ERROR: SwiftZipReader: Password required for \(filename)")
            } else {
                print("ERROR: SwiftZipReader: Failed to extract \(filename): \(error)")
            }
            return nil
        }
    }

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < imageEntries.count else { return nil }
        return (imageEntries[index].filename.string as NSString).lastPathComponent
    }

    /// 指定されたインデックスの画像サイズを取得
    func imageSize(at index: Int) -> CGSize? {
        // 画像データを読み込んでサイズを取得（ヘッダのみ読み込みは未対応）
        guard let data = imageData(at: index),
              let image = NSImage(data: data) else {
            return nil
        }

        if let rep = image.representations.first {
            let width = rep.pixelsWide
            let height = rep.pixelsHigh
            if width > 0 && height > 0 {
                return CGSize(width: width, height: height)
            }
        }

        if image.size.width > 0 && image.size.height > 0 {
            return image.size
        }

        return nil
    }

    /// 指定されたインデックスのファイルサイズを取得
    func fileSize(at index: Int) -> Int64? {
        guard index >= 0 && index < imageEntries.count else { return nil }
        return imageEntries[index].uncompressedSize
    }

    /// 指定されたインデックスの画像フォーマットを取得
    func imageFormat(at index: Int) -> String? {
        guard index >= 0 && index < imageEntries.count else { return nil }
        let filename = imageEntries[index].filename.string
        let ext = (filename as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg":
            return "JPEG"
        case "png":
            return "PNG"
        case "gif":
            return "GIF"
        case "webp":
            return "WebP"
        case "jp2", "j2k":
            return "JPEG 2000"
        default:
            return ext.uppercased()
        }
    }

    /// 指定されたインデックスのファイル更新日時を取得
    func fileDate(at index: Int) -> Date? {
        guard index >= 0 && index < imageEntries.count else { return nil }
        return imageEntries[index].fileModification
    }
}
