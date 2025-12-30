import Foundation
import Unrar
import AppKit

/// RARアーカイブから画像を読み込むクラス
class RarReader {
    private let archiveURL: URL
    private let archive: Archive?
    private(set) var imageEntries: [Entry] = []
    /// 入れ子の書庫エントリ（ソート済み）
    private(set) var nestedArchiveEntries: [Entry] = []
    /// 全エントリ（画像と書庫を混合してソート済み）- 表示順序用
    private(set) var allSortedEntryNames: [String] = []
    /// パスワードが必要かどうか
    private(set) var needsPassword: Bool = false

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド（進捗報告付き、パスワード対応）
    static func create(url: URL, password: String? = nil, onPhaseChange: PhaseCallback? = nil) async -> RarReader? {
        let startTime = CFAbsoluteTimeGetCurrent()

        // フェーズ1: アーカイブを開く
        await onPhaseChange?(L("loading_phase_opening_archive"))

        let openStart = CFAbsoluteTimeGetCurrent()
        let archive: Archive
        do {
            archive = try Archive(path: url.path, password: password)
        } catch {
            let errorString = String(describing: error)
            // パスワードが必要な場合のエラー検出
            if errorString.contains("password") || errorString.contains("Password") ||
               errorString.contains("encrypted") || errorString.contains("missingPassword") {
                DebugLogger.log("⚠️ RAR archive requires password: \(url.lastPathComponent)", level: .minimal)
                // パスワードが必要なことを示すためのダミーRarReaderを返す
                return RarReader(url: url, needsPassword: true)
            }
            DebugLogger.log("ERROR: Failed to open RAR archive: \(error)", level: .minimal)
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        DebugLogger.log("⏱️ RAR Archive open time: \(String(format: "%.3f", openTime))s", level: .verbose)

        // フェーズ2: 画像リストを作成
        await onPhaseChange?(L("loading_phase_building_image_list"))

        let extractStart = CFAbsoluteTimeGetCurrent()
        let extractResult: ExtractResult
        do {
            extractResult = try extractImageEntries(from: archive)
        } catch {
            let errorString = String(describing: error)
            // 展開時にパスワードエラーが発生することもある
            if errorString.contains("password") || errorString.contains("Password") ||
               errorString.contains("encrypted") || errorString.contains("CRC") ||
               errorString.contains("missingPassword") {
                DebugLogger.log("⚠️ RAR archive requires password (detected during extraction): \(url.lastPathComponent)", level: .minimal)
                return RarReader(url: url, needsPassword: true)
            }
            DebugLogger.log("ERROR: Failed to extract entries: \(error)", level: .minimal)
            return nil
        }
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        DebugLogger.log("⏱️ RAR Extract & sort time: \(String(format: "%.3f", extractTime))s", level: .verbose)

        // 画像も入れ子書庫もない場合のみ失敗
        guard extractResult.imageEntries.count > 0 || extractResult.archiveEntries.count > 0 else {
            DebugLogger.log("ERROR: RAR: No images or nested archives found in archive", level: .minimal)
            return nil
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        DebugLogger.log("⏱️ RAR Total init time: \(String(format: "%.3f", totalTime))s", level: .verbose)

        return RarReader(url: url, archive: archive, extractResult: extractResult)
    }

    /// 内部初期化（ファクトリメソッドから呼ばれる）
    private init(url: URL, archive: Archive, extractResult: ExtractResult) {
        self.archiveURL = url
        self.archive = archive
        self.imageEntries = extractResult.imageEntries
        self.nestedArchiveEntries = extractResult.archiveEntries
        self.allSortedEntryNames = extractResult.allSortedNames
        self.needsPassword = false
    }

    /// パスワードが必要な場合の初期化
    private init(url: URL, needsPassword: Bool) {
        self.archiveURL = url
        self.archive = nil
        self.imageEntries = []
        self.needsPassword = needsPassword
    }

    /// 同期的な初期化（後方互換性のため、パスワード対応）
    init?(url: URL, password: String? = nil) {
        let startTime = CFAbsoluteTimeGetCurrent()
        self.archiveURL = url

        // RARアーカイブを開く
        let openStart = CFAbsoluteTimeGetCurrent()
        do {
            self.archive = try Archive(path: url.path, password: password)
        } catch {
            let errorString = String(describing: error)
            if errorString.contains("password") || errorString.contains("Password") ||
               errorString.contains("encrypted") || errorString.contains("missingPassword") {
                // パスワードが必要な場合、needsPassword = true で初期化
                self.archive = nil
                self.needsPassword = true
                DebugLogger.log("⚠️ RAR archive requires password: \(url.lastPathComponent)", level: .minimal)
                return
            }
            DebugLogger.log("ERROR: Failed to open RAR archive: \(error)", level: .minimal)
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        DebugLogger.log("⏱️ RAR Archive open time: \(String(format: "%.3f", openTime))s", level: .verbose)

        // 画像ファイルのみを抽出してソート
        let extractStart = CFAbsoluteTimeGetCurrent()
        let extractResult: ExtractResult
        do {
            extractResult = try Self.extractImageEntries(from: archive!)
        } catch {
            let errorString = String(describing: error)
            if errorString.contains("password") || errorString.contains("Password") ||
               errorString.contains("encrypted") || errorString.contains("CRC") ||
               errorString.contains("missingPassword") {
                self.needsPassword = true
                DebugLogger.log("⚠️ RAR archive requires password (detected during extraction): \(url.lastPathComponent)", level: .minimal)
                return
            }
            DebugLogger.log("ERROR: Failed to extract entries: \(error)", level: .minimal)
            return nil
        }

        self.imageEntries = extractResult.imageEntries
        self.nestedArchiveEntries = extractResult.archiveEntries
        self.allSortedEntryNames = extractResult.allSortedNames

        // 画像も入れ子書庫もない場合のみ失敗
        guard imageEntries.count > 0 || nestedArchiveEntries.count > 0 else {
            DebugLogger.log("ERROR: RAR: No images or nested archives found in archive", level: .minimal)
            return nil
        }

        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        DebugLogger.log("⏱️ RAR Extract & sort time: \(String(format: "%.3f", extractTime))s", level: .verbose)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        DebugLogger.log("⏱️ RAR Total init time: \(String(format: "%.3f", totalTime))s", level: .verbose)
    }

    /// 抽出結果の型（画像エントリ、書庫エントリ、全エントリ名）
    struct ExtractResult {
        let imageEntries: [Entry]
        let archiveEntries: [Entry]
        let allSortedNames: [String]
    }

    /// アーカイブ内の画像ファイルエントリを抽出してファイル名でソート
    private static func extractImageEntries(from archive: Archive) throws -> ExtractResult {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                   "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"])

        DebugLogger.log("=== Extracting image entries from RAR archive ===", level: .verbose)

        // 1. エントリ列挙
        let entriesStart = CFAbsoluteTimeGetCurrent()
        let allEntries = try archive.entries()
        DebugLogger.log("⏱️ RAR entries() time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - entriesStart))s (count: \(allEntries.count))", level: .verbose)

        // 2. フィルタリング（画像と書庫を分離）
        let filterStart = CFAbsoluteTimeGetCurrent()
        var imageList: [Entry] = []
        var archiveList: [Entry] = []

        for entry in allEntries {
            let path = entry.fileName
            guard !path.contains("__MACOSX"),
                  !path.contains("/._"),
                  !(path as NSString).lastPathComponent.hasPrefix("._"),
                  !(path as NSString).lastPathComponent.hasPrefix(".") else {
                continue
            }
            let ext = (path as NSString).pathExtension

            if imageExtensions.contains(ext) {
                imageList.append(entry)
            } else if archiveExtensions.contains(ext) {
                archiveList.append(entry)
            }
        }
        DebugLogger.log("⏱️ RAR filter time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - filterStart))s (images: \(imageList.count), archives: \(archiveList.count))", level: .verbose)

        // 3. 画像エントリをソート
        let sortStart = CFAbsoluteTimeGetCurrent()
        let sortedImages = imageList.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }

        // 4. 書庫エントリをソート
        let sortedArchives = archiveList.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }

        // 5. 全エントリ名をソート（表示順序決定用）
        let allNames = imageList.map { $0.fileName } + archiveList.map { $0.fileName }
        let allSortedNames = allNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        DebugLogger.log("⏱️ RAR sort time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - sortStart))s", level: .verbose)
        DebugLogger.log("📦 RAR: Found \(sortedImages.count) images, \(sortedArchives.count) nested archives", level: .normal)

        return ExtractResult(imageEntries: sortedImages, archiveEntries: sortedArchives, allSortedNames: allSortedNames)
    }

    /// 指定されたインデックスの画像を読み込む
    func loadImage(at index: Int) -> NSImage? {
        guard let archive = archive else {
            DebugLogger.log("ERROR: Archive not available (password required?)", level: .minimal)
            return nil
        }
        guard index >= 0 && index < imageEntries.count else {
            DebugLogger.log("ERROR: Index out of range: \(index) (total: \(imageEntries.count))", level: .minimal)
            return nil
        }

        let entry = imageEntries[index]

        DebugLogger.log("Loading RAR image: \(entry.fileName) (size: \(entry.uncompressedSize) bytes)", level: .verbose)

        do {
            let imageData = try archive.extract(entry)

            DebugLogger.log("Extracted \(imageData.count) bytes from RAR", level: .verbose)

            guard let image = NSImage(data: imageData) else {
                DebugLogger.log("ERROR: Failed to create NSImage from RAR data. File: \(entry.fileName), Data size: \(imageData.count)", level: .minimal)
                return nil
            }

            return image
        } catch {
            DebugLogger.log("ERROR: Failed to extract RAR image at index \(index), file: \(entry.fileName), error: \(error)", level: .minimal)
            return nil
        }
    }

    /// 指定されたインデックスの画像データを取得
    func imageData(at index: Int) -> Data? {
        guard let archive = archive else { return nil }
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }

        let entry = imageEntries[index]

        do {
            return try archive.extract(entry)
        } catch {
            return nil
        }
    }

    /// 画像の総数
    var imageCount: Int {
        return imageEntries.count
    }

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }
        return (imageEntries[index].fileName as NSString).lastPathComponent
    }

    /// 指定されたインデックスの画像サイズを取得
    func imageSize(at index: Int) -> CGSize? {
        guard let archive = archive else { return nil }
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }

        let entry = imageEntries[index]

        do {
            let imageData = try archive.extract(entry)

            // まずNSBitmapImageRepを試す
            if let imageRep = NSBitmapImageRep(data: imageData) {
                let width = imageRep.pixelsWide
                let height = imageRep.pixelsHigh
                if width > 0 && height > 0 {
                    return CGSize(width: width, height: height)
                }
            }

            // NSBitmapImageRepで取得できなかった場合はNSImageを使う
            if let image = NSImage(data: imageData) {
                // representationsからピクセルサイズを取得
                if let rep = image.representations.first {
                    let width = rep.pixelsWide
                    let height = rep.pixelsHigh
                    if width > 0 && height > 0 {
                        return CGSize(width: width, height: height)
                    }
                }
                // フォールバック: imageのサイズを使用
                if image.size.width > 0 && image.size.height > 0 {
                    return image.size
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    /// 指定されたインデックスの画像ファイルサイズを取得
    func fileSize(at index: Int) -> Int64? {
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }
        return Int64(imageEntries[index].uncompressedSize)
    }

    /// 指定されたインデックスの画像フォーマットを取得
    func imageFormat(at index: Int) -> String? {
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }
        let fileName = imageEntries[index].fileName
        let ext = (fileName as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg":
            return "JPEG"
        case "png":
            return "PNG"
        case "gif":
            return "GIF"
        case "webp":
            return "WebP"
        case "bmp":
            return "BMP"
        case "tiff", "tif":
            return "TIFF"
        case "heic", "heif":
            return "HEIC"
        default:
            return ext.uppercased()
        }
    }

    // MARK: - Nested Archive Extraction

    /// 入れ子書庫を一時ファイルに抽出
    /// - Parameter index: nestedArchiveEntries内のインデックス
    /// - Returns: 抽出された一時ファイルのURL（呼び出し側で削除責任あり）
    func extractNestedArchive(at index: Int) -> URL? {
        guard let archive = archive else {
            DebugLogger.log("ERROR: RarReader: Archive not available for nested extraction", level: .minimal)
            return nil
        }
        guard index >= 0 && index < nestedArchiveEntries.count else {
            DebugLogger.log("ERROR: RarReader: Nested archive index out of range: \(index)", level: .minimal)
            return nil
        }

        let entry = nestedArchiveEntries[index]
        let filename = (entry.fileName as NSString).lastPathComponent

        // 一時ディレクトリにファイルを作成
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(filename)

        do {
            // 親ディレクトリを作成
            try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let extractedData = try archive.extract(entry)
            try extractedData.write(to: tempURL)

            DebugLogger.log("📦 RarReader: Extracted nested archive to \(tempURL.path) (\(extractedData.count) bytes)", level: .verbose)
            return tempURL
        } catch {
            DebugLogger.log("ERROR: RarReader: Failed to extract nested archive \(filename): \(error)", level: .minimal)
            return nil
        }
    }

    /// 入れ子書庫のファイル名を取得
    func nestedArchiveName(at index: Int) -> String? {
        guard index >= 0 && index < nestedArchiveEntries.count else { return nil }
        return nestedArchiveEntries[index].fileName
    }

    /// 入れ子書庫の数
    var nestedArchiveCount: Int {
        return nestedArchiveEntries.count
    }

    /// 画像エントリ名からインデックスを取得
    func imageIndex(forName name: String) -> Int? {
        for i in 0..<imageEntries.count {
            if imageEntries[i].fileName == name {
                return i
            }
        }
        return nil
    }

    /// 入れ子書庫エントリ名からインデックスを取得
    func nestedArchiveIndex(forName name: String) -> Int? {
        for i in 0..<nestedArchiveEntries.count {
            if nestedArchiveEntries[i].fileName == name {
                return i
            }
        }
        return nil
    }
}
