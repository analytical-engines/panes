import Foundation
import SWCompression
import AppKit

/// 7-Zipアーカイブから画像を読み込むクラス
class SevenZipReader {
    private let archiveURL: URL
    private(set) var imageEntryInfos: [SevenZipEntryInfo] = []
    /// 入れ子の書庫エントリ（ソート済み）
    private(set) var nestedArchiveEntries: [SevenZipEntryInfo] = []
    /// 全エントリ（画像と書庫を混合してソート済み）- 表示順序用
    private(set) var allSortedEntryNames: [String] = []
    private var archiveData: Data

    /// 展開済みデータのキャッシュ（ファイル名 -> Data）
    private var extractedCache: [String: Data] = [:]
    private var cachePopulated = false

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void
    /// エラー報告用のコールバック型
    typealias ErrorCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド（進捗報告付き）
    static func create(url: URL, onPhaseChange: PhaseCallback? = nil, onError: ErrorCallback? = nil) async -> SevenZipReader? {
        print("📦 7z: Starting to open \(url.lastPathComponent)")
        let startTime = CFAbsoluteTimeGetCurrent()

        // フェーズ1: アーカイブを開く
        await onPhaseChange?(L("loading_phase_opening_archive"))

        let openStart = CFAbsoluteTimeGetCurrent()
        let archiveData: Data

        // セキュリティスコープのリソースアクセスを開始
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            print("📦 7z: Reading file... (hasAccess: \(hasAccess))")
            // メモリマップドファイルを使用（大きなファイルでも効率的）
            archiveData = try Data(contentsOf: url, options: .mappedIfSafe)
            print("📦 7z: Mapped \(archiveData.count) bytes from file")
        } catch {
            print("ERROR: Failed to read 7z file data: \(error)")
            await onError?(L("error_cannot_open_file"))
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        print("⏱️ 7z file read time: \(String(format: "%.3f", openTime))s")

        // フェーズ2: 画像リストを作成
        await onPhaseChange?(L("loading_phase_building_image_list"))

        let extractStart = CFAbsoluteTimeGetCurrent()
        let extractResult: ExtractResult
        do {
            extractResult = try extractImageEntries(from: archiveData)
        } catch {
            print("ERROR: Failed to extract 7z entries: \(error)")
            await onError?(L("error_cannot_open_file"))
            return nil
        }
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ 7z Extract & sort time: \(String(format: "%.3f", extractTime))s")

        // 画像も入れ子書庫もない場合のみ失敗
        guard extractResult.imageEntries.count > 0 || extractResult.archiveEntries.count > 0 else {
            print("ERROR: 7z: No images or nested archives found in archive")
            await onError?(L("error_no_images_found"))
            return nil
        }

        // フェーズ3: 展開テスト（圧縮形式がサポートされているか確認）
        await onPhaseChange?(L("loading_phase_extracting_images"))

        let decompressStart = CFAbsoluteTimeGetCurrent()
        let extractedCache: [String: Data]
        do {
            extractedCache = try extractAllEntries(from: archiveData)
            print("📦 7z: Extracted \(extractedCache.count) entries")
        } catch {
            print("ERROR: Failed to decompress 7z file: \(error)")
            print("⚠️ This 7z file uses unsupported compression format")
            await onError?(L("error_7z_unsupported_compression"))
            return nil
        }
        let decompressTime = CFAbsoluteTimeGetCurrent() - decompressStart
        print("⏱️ 7z Decompress time: \(String(format: "%.3f", decompressTime))s")

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ 7z Total init time: \(String(format: "%.3f", totalTime))s")

        return SevenZipReader(url: url, archiveData: archiveData, extractResult: extractResult, extractedCache: extractedCache)
    }

    /// 全エントリを展開
    private static func extractAllEntries(from archiveData: Data) throws -> [String: Data] {
        var cache: [String: Data] = [:]
        let allEntries = try SevenZipContainer.open(container: archiveData)
        for entry in allEntries {
            if let data = entry.data {
                cache[entry.info.name] = data
            }
        }
        return cache
    }

    /// 内部初期化（ファクトリメソッドから呼ばれる）
    private init(url: URL, archiveData: Data, extractResult: ExtractResult, extractedCache: [String: Data]) {
        self.archiveURL = url
        self.archiveData = archiveData
        self.imageEntryInfos = extractResult.imageEntries
        self.nestedArchiveEntries = extractResult.archiveEntries
        self.allSortedEntryNames = extractResult.allSortedNames
        self.extractedCache = extractedCache
        self.cachePopulated = true
    }

    /// 同期的な初期化（後方互換性のため）
    init?(url: URL) {
        let startTime = CFAbsoluteTimeGetCurrent()
        self.archiveURL = url

        // 7zファイルを読み込む（メモリマップド）
        let openStart = CFAbsoluteTimeGetCurrent()
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            print("ERROR: Failed to read 7z file data")
            return nil
        }
        self.archiveData = data
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        print("⏱️ 7z file read time: \(String(format: "%.3f", openTime))s")

        // 画像ファイルのみを抽出してソート
        let extractStart = CFAbsoluteTimeGetCurrent()
        let extractResult: ExtractResult
        do {
            extractResult = try Self.extractImageEntries(from: archiveData)
        } catch {
            print("ERROR: Failed to extract 7z entries: \(error)")
            return nil
        }

        self.imageEntryInfos = extractResult.imageEntries
        self.nestedArchiveEntries = extractResult.archiveEntries
        self.allSortedEntryNames = extractResult.allSortedNames

        // 画像も入れ子書庫もない場合のみ失敗
        guard imageEntryInfos.count > 0 || nestedArchiveEntries.count > 0 else {
            print("ERROR: 7z: No images or nested archives found in archive")
            return nil
        }

        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ 7z Extract & sort time: \(String(format: "%.3f", extractTime))s")

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ 7z Total init time: \(String(format: "%.3f", totalTime))s")
    }

    /// 抽出結果の型（画像エントリ、書庫エントリ、全エントリ名）
    struct ExtractResult {
        let imageEntries: [SevenZipEntryInfo]
        let archiveEntries: [SevenZipEntryInfo]
        let allSortedNames: [String]
    }

    /// アーカイブ内の画像ファイルエントリを抽出してファイル名でソート
    private static func extractImageEntries(from archiveData: Data) throws -> ExtractResult {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                   "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"])

        print("=== Extracting image entries from 7z archive ===")

        // 1. エントリ情報を取得
        let entriesStart = CFAbsoluteTimeGetCurrent()
        let allEntryInfos = try SevenZipContainer.info(container: archiveData)
        print("⏱️ 7z info() time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - entriesStart))s (count: \(allEntryInfos.count))")

        // 2. フィルタリング（画像と書庫を分離）
        let filterStart = CFAbsoluteTimeGetCurrent()
        var imageList: [SevenZipEntryInfo] = []
        var archiveList: [SevenZipEntryInfo] = []

        for entryInfo in allEntryInfos {
            // ディレクトリは除外（名前が/で終わるか、サイズが0でパス拡張子がない場合）
            let path = entryInfo.name
            if path.hasSuffix("/") { continue }

            guard !path.contains("__MACOSX"),
                  !path.contains("/._"),
                  !(path as NSString).lastPathComponent.hasPrefix("._"),
                  !(path as NSString).lastPathComponent.hasPrefix(".") else {
                continue
            }
            let ext = (path as NSString).pathExtension

            if imageExtensions.contains(ext) {
                imageList.append(entryInfo)
            } else if archiveExtensions.contains(ext) {
                archiveList.append(entryInfo)
            }
        }
        print("⏱️ 7z filter time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - filterStart))s (images: \(imageList.count), archives: \(archiveList.count))")

        // 3. 画像エントリをソート
        let sortStart = CFAbsoluteTimeGetCurrent()
        let sortedImages = imageList.sorted { entry1, entry2 in
            entry1.name.localizedStandardCompare(entry2.name) == .orderedAscending
        }

        // 4. 書庫エントリをソート
        let sortedArchives = archiveList.sorted { entry1, entry2 in
            entry1.name.localizedStandardCompare(entry2.name) == .orderedAscending
        }

        // 5. 全エントリ名をソート（表示順序決定用）
        let allNames = imageList.map { $0.name } + archiveList.map { $0.name }
        let allSortedNames = allNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        print("⏱️ 7z sort time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - sortStart))s")

        print("=== First 5 7z entries after sorting ===")
        for (index, entryInfo) in sortedImages.prefix(5).enumerated() {
            print("[\(index)] \(entryInfo.name)")
        }

        print("📦 7z: Found \(sortedImages.count) images, \(sortedArchives.count) nested archives")

        return ExtractResult(imageEntries: sortedImages, archiveEntries: sortedArchives, allSortedNames: allSortedNames)
    }

    /// 指定されたインデックスの画像を読み込む
    func loadImage(at index: Int) -> NSImage? {
        guard let data = imageData(at: index) else {
            return nil
        }

        guard let image = NSImage(data: data) else {
            let entryInfo = imageEntryInfos[index]
            print("ERROR: Failed to create NSImage from 7z data. File: \(entryInfo.name), Data size: \(data.count)")
            return nil
        }

        return image
    }

    /// 指定されたインデックスの画像データを取得
    func imageData(at index: Int) -> Data? {
        guard index >= 0 && index < imageEntryInfos.count else {
            print("ERROR: Index out of range: \(index) (total: \(imageEntryInfos.count))")
            return nil
        }

        let entryInfo = imageEntryInfos[index]
        let fileName = entryInfo.name

        // キャッシュにあればそれを返す
        if let cachedData = extractedCache[fileName] {
            return cachedData
        }

        // キャッシュがまだなければ全体を展開してキャッシュに保存
        if !cachePopulated {
            populateCache()
        }

        return extractedCache[fileName]
    }

    /// 全エントリを展開してキャッシュに保存
    private func populateCache() {
        guard !cachePopulated else { return }

        // 失敗しても再試行しないようにフラグを先に立てる
        cachePopulated = true

        print("📦 7z: Extracting all entries to cache...")
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let allEntries = try SevenZipContainer.open(container: archiveData)

            for entry in allEntries {
                if let data = entry.data {
                    extractedCache[entry.info.name] = data
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("📦 7z: Cached \(extractedCache.count) entries in \(String(format: "%.3f", elapsed))s")
        } catch {
            print("ERROR: Failed to extract 7z entries: \(error)")
            print("⚠️ This 7z file may use unsupported compression (e.g., LZMA2 with specific settings)")
        }
    }

    /// 画像の総数
    var imageCount: Int {
        return imageEntryInfos.count
    }

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < imageEntryInfos.count else {
            return nil
        }
        let name = imageEntryInfos[index].name
        return (name as NSString).lastPathComponent
    }

    /// 指定されたインデックスの画像サイズを取得
    func imageSize(at index: Int) -> CGSize? {
        guard let imageData = imageData(at: index) else {
            return nil
        }

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
    }

    /// 指定されたインデックスの画像ファイルサイズを取得
    func fileSize(at index: Int) -> Int64? {
        guard index >= 0 && index < imageEntryInfos.count else {
            return nil
        }
        return Int64(imageEntryInfos[index].size ?? 0)
    }

    /// 指定されたインデックスの画像フォーマットを取得
    func imageFormat(at index: Int) -> String? {
        guard index >= 0 && index < imageEntryInfos.count else {
            return nil
        }
        let fileName = imageEntryInfos[index].name
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
        guard index >= 0 && index < nestedArchiveEntries.count else {
            print("ERROR: SevenZipReader: Nested archive index out of range: \(index)")
            return nil
        }

        let entryInfo = nestedArchiveEntries[index]
        let filename = (entryInfo.name as NSString).lastPathComponent

        // キャッシュから取得を試みる
        var extractedData: Data?
        if let cachedData = extractedCache[entryInfo.name] {
            extractedData = cachedData
        } else if !cachePopulated {
            // キャッシュを作成
            populateCache()
            extractedData = extractedCache[entryInfo.name]
        }

        guard let data = extractedData else {
            print("ERROR: SevenZipReader: Failed to get data for nested archive \(filename)")
            return nil
        }

        // 一時ディレクトリにファイルを作成
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(filename)

        do {
            // 親ディレクトリを作成
            try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            try data.write(to: tempURL)
            print("📦 SevenZipReader: Extracted nested archive to \(tempURL.path) (\(data.count) bytes)")
            return tempURL
        } catch {
            print("ERROR: SevenZipReader: Failed to extract nested archive \(filename): \(error)")
            return nil
        }
    }

    /// 入れ子書庫のファイル名を取得
    func nestedArchiveName(at index: Int) -> String? {
        guard index >= 0 && index < nestedArchiveEntries.count else { return nil }
        return nestedArchiveEntries[index].name
    }

    /// 入れ子書庫の数
    var nestedArchiveCount: Int {
        return nestedArchiveEntries.count
    }

    /// 画像エントリ名からインデックスを取得
    func imageIndex(forName name: String) -> Int? {
        for i in 0..<imageEntryInfos.count {
            if imageEntryInfos[i].name == name {
                return i
            }
        }
        return nil
    }

    /// 入れ子書庫エントリ名からインデックスを取得
    func nestedArchiveIndex(forName name: String) -> Int? {
        for i in 0..<nestedArchiveEntries.count {
            if nestedArchiveEntries[i].name == name {
                return i
            }
        }
        return nil
    }
}
