import Foundation
import AppKit
import ZipArchive

/// サポートする書庫拡張子
let archiveExtensions = Set(["zip", "cbz", "rar", "cbr", "7z", "cb7",
                              "ZIP", "CBZ", "RAR", "CBR", "7Z", "CB7"])

/// swift-zip-archiveを使用したZIPアーカイブリーダー
/// 破損アーカイブやパスワード付きアーカイブにも対応
class SwiftZipReader {
    private let archiveURL: URL
    private var imageEntries: [Zip.FileHeader] = []
    /// 入れ子の書庫エントリ（ソート済み）
    private(set) var nestedArchiveEntries: [Zip.FileHeader] = []
    /// 全エントリ（画像と書庫を混合してソート済み）- 表示順序用
    private(set) var allSortedEntryNames: [String] = []
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

                // 拡張子セット
                let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                           "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"])

                // エントリをフィルタリング（画像と書庫を分離）
                var imageList: [Zip.FileHeader] = []
                var archiveList: [Zip.FileHeader] = []

                for entry in entries {
                    let filename = entry.filename.string
                    // __MACOSXやドットファイルを除外
                    guard !filename.contains("__MACOSX"),
                          !filename.contains("/._"),
                          !(filename as NSString).lastPathComponent.hasPrefix("._"),
                          !(filename as NSString).lastPathComponent.hasPrefix(".") else {
                        continue
                    }
                    let ext = (filename as NSString).pathExtension

                    if imageExtensions.contains(ext) {
                        imageList.append(entry)
                    } else if archiveExtensions.contains(ext) {
                        archiveList.append(entry)
                    }
                }

                // 画像エントリをソート
                reader.imageEntries = imageList.sorted { entry1, entry2 in
                    entry1.filename.string.localizedStandardCompare(entry2.filename.string) == .orderedAscending
                }

                // 書庫エントリをソート
                reader.nestedArchiveEntries = archiveList.sorted { entry1, entry2 in
                    entry1.filename.string.localizedStandardCompare(entry2.filename.string) == .orderedAscending
                }

                // 全エントリ名をソート（表示順序決定用）
                let allNames = imageList.map { $0.filename.string } + archiveList.map { $0.filename.string }
                reader.allSortedEntryNames = allNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

                let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
                DebugLogger.log("⏱️ SwiftZipReader: Extract & sort time: \(String(format: "%.3f", extractTime))s", level: .verbose)
                DebugLogger.log("📦 SwiftZipReader: Found \(reader.imageEntries.count) images, \(reader.nestedArchiveEntries.count) nested archives", level: .normal)

                // 暗号化ファイルがあるかチェック
                let hasEncryptedFiles = entries.contains { $0.flags.contains(.encrypted) }
                if hasEncryptedFiles && password == nil {
                    reader.needsPassword = true
                    DebugLogger.log("🔐 SwiftZipReader: Password required for encrypted archive", level: .minimal)
                }
            }
        } catch {
            let errorString = String(describing: error)
            DebugLogger.log("ERROR: SwiftZipReader failed to open archive: \(error)", level: .minimal)
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

        // 画像も入れ子書庫もない場合のみ失敗
        guard reader.imageEntries.count > 0 || reader.nestedArchiveEntries.count > 0 else {
            DebugLogger.log("ERROR: SwiftZipReader: No images or nested archives found in archive", level: .minimal)
            return nil
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        DebugLogger.log("⏱️ SwiftZipReader: Total init time: \(String(format: "%.3f", totalTime))s", level: .verbose)

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
            DebugLogger.log("ERROR: SwiftZipReader: Index out of range: \(index) (total: \(imageEntries.count))", level: .minimal)
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
                DebugLogger.log("SwiftZipReader: Extracted \(result?.count ?? 0) bytes for \(filename)", level: .verbose)
            }
            return result
        } catch {
            let errorString = String(describing: error)
            // パスワードエラーの判定
            if errorString.contains("encrypted") || errorString.contains("password") {
                needsPassword = true
                DebugLogger.log("ERROR: SwiftZipReader: Password required for \(filename)", level: .minimal)
            } else if errorString.contains("unsupportedCompressionMethod") {
                // Deflate64などの非対応圧縮形式
                DebugLogger.log("ERROR: SwiftZipReader: Unsupported compression method for \(filename) (possibly Deflate64)", level: .minimal)
            } else {
                DebugLogger.log("ERROR: SwiftZipReader: Failed to extract \(filename): \(error)", level: .minimal)
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

    // MARK: - Nested Archive Extraction

    /// 入れ子書庫を一時ファイルに抽出
    /// - Parameter index: nestedArchiveEntries内のインデックス
    /// - Returns: 抽出された一時ファイルのURL（呼び出し側で削除責任あり）
    func extractNestedArchive(at index: Int) -> URL? {
        guard index >= 0 && index < nestedArchiveEntries.count else {
            DebugLogger.log("ERROR: SwiftZipReader: Nested archive index out of range: \(index)", level: .minimal)
            return nil
        }

        let entry = nestedArchiveEntries[index]
        let filename = (entry.filename.string as NSString).lastPathComponent

        // 一時ディレクトリにファイルを作成
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(filename)

        do {
            // 親ディレクトリを作成
            try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            var extractedData: Data?
            try ZipArchiveReader.withFile(archiveURL.path) { reader in
                let bytes = try reader.readFile(entry, password: password)
                extractedData = Data(bytes)
            }

            guard let data = extractedData else {
                DebugLogger.log("ERROR: SwiftZipReader: Failed to read nested archive data for \(filename)", level: .minimal)
                return nil
            }

            try data.write(to: tempURL)
            DebugLogger.log("📦 SwiftZipReader: Extracted nested archive to \(tempURL.path) (\(data.count) bytes)", level: .verbose)
            return tempURL
        } catch {
            DebugLogger.log("ERROR: SwiftZipReader: Failed to extract nested archive \(filename): \(error)", level: .minimal)
            return nil
        }
    }

    /// 入れ子書庫のファイル名を取得
    func nestedArchiveName(at index: Int) -> String? {
        guard index >= 0 && index < nestedArchiveEntries.count else { return nil }
        return nestedArchiveEntries[index].filename.string
    }

    /// 入れ子書庫の数
    var nestedArchiveCount: Int {
        return nestedArchiveEntries.count
    }

    /// 画像エントリ名からインデックスを取得
    func imageIndex(forName name: String) -> Int? {
        for i in 0..<imageEntries.count {
            if imageEntries[i].filename.string == name {
                return i
            }
        }
        return nil
    }

    /// 入れ子書庫エントリ名からインデックスを取得
    func nestedArchiveIndex(forName name: String) -> Int? {
        for i in 0..<nestedArchiveEntries.count {
            if nestedArchiveEntries[i].filename.string == name {
                return i
            }
        }
        return nil
    }
}
