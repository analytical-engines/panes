import Foundation
import ZIPFoundation
import ZipArchive
import AppKit

/// zipアーカイブから画像を読み込むクラス
class ArchiveReader {
    private let archiveURL: URL
    private let archive: Archive?
    private(set) var imageEntries: [Entry] = []

    /// 暗号化されたエントリが存在するか（スキップされたエントリがある場合true）
    private(set) var hasEncryptedEntries: Bool = false

    /// パスワードが必要かどうか（暗号化されていて画像が0の場合）
    private(set) var needsPassword: Bool = false

    /// パスワード付きZIP用のデータ（SSZipArchive使用時）
    private var tempDirectoryURL: URL?
    private var extractedImagePaths: [String] = []

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド（進捗報告付き、パスワード対応）
    static func create(url: URL, password: String? = nil, onPhaseChange: PhaseCallback? = nil) async -> ArchiveReader? {
        let startTime = CFAbsoluteTimeGetCurrent()

        // パスワードが指定されている場合はSwiftMiniZipを使用
        if let password = password {
            return await createWithPassword(url: url, password: password, onPhaseChange: onPhaseChange)
        }

        // フェーズ1: アーカイブを開く
        await onPhaseChange?(L("loading_phase_opening_archive"))

        let openStart = CFAbsoluteTimeGetCurrent()
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        print("⏱️ Archive open time: \(String(format: "%.3f", openTime))s")

        // フェーズ2: 画像リストを作成
        await onPhaseChange?(L("loading_phase_building_image_list"))

        let extractStart = CFAbsoluteTimeGetCurrent()
        let imageEntries = extractImageEntries(from: archive)
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ Extract & sort time: \(String(format: "%.3f", extractTime))s")

        // 暗号化エントリのチェック
        var hasEncryptedEntries = false
        var needsPassword = false
        if let totalEntries = readTotalEntriesFromZip(url: url) {
            let accessibleEntries = archive.reduce(0) { count, _ in count + 1 }
            if totalEntries > accessibleEntries {
                hasEncryptedEntries = true
                print("⚠️ Encrypted entries detected: \(totalEntries) total, \(accessibleEntries) accessible")

                // 画像が0の場合はパスワードが必要
                if imageEntries.isEmpty {
                    needsPassword = true
                    print("🔐 Password required to access encrypted archive")
                }
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Total init time: \(String(format: "%.3f", totalTime))s")

        return ArchiveReader(url: url, archive: archive, imageEntries: imageEntries,
                            hasEncryptedEntries: hasEncryptedEntries, needsPassword: needsPassword)
    }

    /// パスワード付きでアーカイブを開く（SSZipArchive使用）
    private static func createWithPassword(url: URL, password: String, onPhaseChange: PhaseCallback? = nil) async -> ArchiveReader? {
        let startTime = CFAbsoluteTimeGetCurrent()

        await onPhaseChange?(L("loading_phase_opening_archive"))

        // 一時ディレクトリを作成
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("ERROR: Failed to create temp directory: \(error)")
            return nil
        }

        await onPhaseChange?(L("loading_phase_extracting_images"))

        // SSZipArchiveで展開
        do {
            try SSZipArchive.unzipFile(
                atPath: url.path,
                toDestination: tempDir.path,
                overwrite: true,
                password: password
            )
        } catch {
            print("ERROR: Failed to extract password-protected archive: \(error)")
            // 一時ディレクトリを削除
            try? FileManager.default.removeItem(at: tempDir)
            // パスワードが間違っている場合
            return ArchiveReader(url: url, needsPassword: true, wrongPassword: true)
        }

        await onPhaseChange?(L("loading_phase_building_image_list"))

        // 画像ファイルを検索（同期的に実行）
        let imagePaths = findImageFiles(in: tempDir)

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Total init time (with password): \(String(format: "%.3f", totalTime))s, \(imagePaths.count) images")

        if imagePaths.isEmpty {
            // 画像が見つからない場合、一時ディレクトリを削除
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }

        return ArchiveReader(url: url, tempDirectory: tempDir, extractedImagePaths: imagePaths)
    }

    /// ディレクトリ内の画像ファイルを検索（同期メソッド）
    private static func findImageFiles(in directory: URL) -> [String] {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k"])
        var imagePaths: [String] = []

        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        while let fileURL = enumerator.nextObject() as? URL {
            let path = fileURL.path
            let fileName = fileURL.lastPathComponent

            // 隠しファイルやMac固有ファイルをスキップ
            guard !path.contains("__MACOSX"),
                  !fileName.hasPrefix("._"),
                  !fileName.hasPrefix(".") else {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                imagePaths.append(path)
            }
        }

        // ソート
        imagePaths.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return imagePaths
    }

    /// 内部初期化（ファクトリメソッドから呼ばれる）- 通常のZIPFoundation用
    private init(url: URL, archive: Archive, imageEntries: [Entry], hasEncryptedEntries: Bool, needsPassword: Bool = false) {
        self.archiveURL = url
        self.archive = archive
        self.imageEntries = imageEntries
        self.hasEncryptedEntries = hasEncryptedEntries
        self.needsPassword = needsPassword
    }

    /// パスワード付きアーカイブ用の初期化（SSZipArchive使用）
    private init(url: URL, tempDirectory: URL, extractedImagePaths: [String]) {
        self.archiveURL = url
        self.archive = nil
        self.tempDirectoryURL = tempDirectory
        self.extractedImagePaths = extractedImagePaths
        self.hasEncryptedEntries = true
        self.needsPassword = false
    }

    deinit {
        // 一時ディレクトリをクリーンアップ
        if let tempDir = tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDir)
            print("🗑️ Cleaned up temp directory: \(tempDir.path)")
        }
    }

    /// パスワードが必要な場合 or 間違ったパスワードの場合の初期化
    private init(url: URL, needsPassword: Bool, wrongPassword: Bool = false) {
        self.archiveURL = url
        self.archive = nil
        self.needsPassword = needsPassword
        self.hasEncryptedEntries = true
        // wrongPasswordの場合はimageCountが0になるのでエラーとして扱われる
    }

    /// 同期的な初期化（後方互換性のため）
    init?(url: URL) {
        let startTime = CFAbsoluteTimeGetCurrent()
        self.archiveURL = url

        // zipアーカイブを開く
        let openStart = CFAbsoluteTimeGetCurrent()
        let openedArchive: Archive
        do {
            openedArchive = try Archive(url: url, accessMode: .read)
            self.archive = openedArchive
        } catch {
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        print("⏱️ Archive open time: \(String(format: "%.3f", openTime))s")

        // 画像ファイルのみを抽出してソート
        let extractStart = CFAbsoluteTimeGetCurrent()
        self.imageEntries = Self.extractImageEntries(from: openedArchive)
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ Extract & sort time: \(String(format: "%.3f", extractTime))s")

        // 暗号化エントリのチェック
        // ZIPFoundationは暗号化されたエントリをスキップするため、
        // 全エントリ数とアクセス可能なエントリ数を比較
        if let totalEntries = Self.readTotalEntriesFromZip(url: url) {
            let accessibleEntries = openedArchive.reduce(0) { count, _ in count + 1 }
            if totalEntries > accessibleEntries {
                self.hasEncryptedEntries = true
                self.needsPassword = self.imageEntries.isEmpty
                print("⚠️ Encrypted entries detected: \(totalEntries) total, \(accessibleEntries) accessible")
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Total init time: \(String(format: "%.3f", totalTime))s")
    }

    /// ZIPファイルのEnd of Central Directory Recordから全エントリ数を読み取る
    private static func readTotalEntriesFromZip(url: URL) -> Int? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fileHandle.close() }

        // ファイル末尾から検索（EOCDは末尾付近にある）
        let fileSize = fileHandle.seekToEndOfFile()
        let searchSize: UInt64 = min(fileSize, 65557) // EOCD最大サイズ + コメント最大長
        let searchStart = fileSize - searchSize
        fileHandle.seek(toFileOffset: searchStart)

        guard let data = try? fileHandle.readToEnd() else {
            return nil
        }

        // EOCDシグネチャ (0x06054b50) を末尾から検索
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        for i in stride(from: data.count - 22, through: 0, by: -1) {
            if data[i] == signature[0] && data[i+1] == signature[1] &&
               data[i+2] == signature[2] && data[i+3] == signature[3] {
                // オフセット10-11: total number of entries (2 bytes, little endian)
                let totalEntries = Int(data[i + 10]) | (Int(data[i + 11]) << 8)
                return totalEntries
            }
        }

        return nil
    }

    /// アーカイブ内の画像ファイルエントリを抽出してファイル名でソート
    private static func extractImageEntries(from archive: Archive) -> [Entry] {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                   "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"])

        print("=== Extracting image entries from archive ===")

        // 1. エントリ列挙（遅延評価を強制実行）
        let entriesStart = CFAbsoluteTimeGetCurrent()
        let allEntries = Array(archive)
        print("⏱️ ZIP entries() time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - entriesStart))s (count: \(allEntries.count))")

        // 2. フィルタリング
        let filterStart = CFAbsoluteTimeGetCurrent()
        let entries = allEntries.filter { entry in
            guard entry.type == .file else { return false }
            let path = entry.path
            guard !path.contains("__MACOSX"),
                  !path.contains("/._"),
                  !(path as NSString).lastPathComponent.hasPrefix("._") else {
                return false
            }
            let ext = (path as NSString).pathExtension
            return imageExtensions.contains(ext)
        }
        print("⏱️ ZIP filter time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - filterStart))s (filtered: \(entries.count))")

        // 3. ソート
        let sortStart = CFAbsoluteTimeGetCurrent()
        let sorted = entries.sorted { entry1, entry2 in
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }
        print("⏱️ ZIP sort time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - sortStart))s")

        print("=== First 5 entries after sorting ===")
        for (index, entry) in sorted.prefix(5).enumerated() {
            print("[\(index)] \(entry.path)")
        }

        return sorted
    }

    /// 指定されたインデックスの画像を読み込む
    func loadImage(at index: Int) -> NSImage? {
        // パスワード付きアーカイブの場合（展開済みファイルから読み込み）
        if !extractedImagePaths.isEmpty {
            return loadExtractedImage(at: index)
        }

        guard let archive = archive else {
            print("ERROR: Archive not available")
            return nil
        }
        guard index >= 0 && index < imageEntries.count else {
            print("ERROR: Index out of range: \(index) (total: \(imageEntries.count))")
            return nil
        }

        let entry = imageEntries[index]
        var imageData = Data()

        print("Loading image: \(entry.path) (size: \(entry.uncompressedSize) bytes)")

        do {
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }

            print("Extracted \(imageData.count) bytes")

            guard let image = NSImage(data: imageData) else {
                print("ERROR: Failed to create NSImage from data. File: \(entry.path), Data size: \(imageData.count)")
                return nil
            }

            print("Successfully loaded image: \(entry.path)")
            return image
        } catch {
            print("ERROR: Failed to extract image at index \(index), file: \(entry.path), error: \(error)")
            return nil
        }
    }

    /// 展開済みファイルから画像を読み込む（パスワード付きアーカイブ用）
    private func loadExtractedImage(at index: Int) -> NSImage? {
        guard index >= 0 && index < extractedImagePaths.count else {
            print("ERROR: Index out of range: \(index) (total: \(extractedImagePaths.count))")
            return nil
        }

        let path = extractedImagePaths[index]
        print("Loading extracted image: \(path)")

        guard let image = NSImage(contentsOfFile: path) else {
            print("ERROR: Failed to load image from file: \(path)")
            return nil
        }

        print("Successfully loaded extracted image: \(path)")
        return image
    }

    /// 指定されたインデックスの画像データを取得
    func imageData(at index: Int) -> Data? {
        // パスワード付きアーカイブの場合（展開済みファイルから読み込み）
        if !extractedImagePaths.isEmpty {
            guard index >= 0 && index < extractedImagePaths.count else { return nil }
            return try? Data(contentsOf: URL(fileURLWithPath: extractedImagePaths[index]))
        }

        guard let archive = archive else { return nil }
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }

        let entry = imageEntries[index]
        var imageData = Data()

        do {
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }
            return imageData
        } catch {
            return nil
        }
    }

    /// 画像の総数
    var imageCount: Int {
        // パスワード付きアーカイブの場合はextractedImagePathsを使用
        if !extractedImagePaths.isEmpty {
            return extractedImagePaths.count
        }
        return imageEntries.count
    }

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String? {
        // パスワード付きアーカイブの場合
        if !extractedImagePaths.isEmpty {
            guard index >= 0 && index < extractedImagePaths.count else { return nil }
            return (extractedImagePaths[index] as NSString).lastPathComponent
        }

        guard index >= 0 && index < imageEntries.count else {
            return nil
        }
        return (imageEntries[index].path as NSString).lastPathComponent
    }

    /// 指定されたインデックスの画像サイズを取得（画像全体を読み込まずに）
    func imageSize(at index: Int) -> CGSize? {
        // パスワード付きアーカイブの場合（展開済みファイルから読み込み）
        if !extractedImagePaths.isEmpty {
            guard index >= 0 && index < extractedImagePaths.count else { return nil }
            let path = extractedImagePaths[index]
            if let image = NSImage(contentsOfFile: path) {
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
            }
            return nil
        }

        guard let archive = archive else { return nil }
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }

        let entry = imageEntries[index]
        var imageData = Data()

        do {
            // まず画像ヘッダーだけ読み込んでみる
            let headerSize = min(entry.uncompressedSize, 8192) // 8KB
            var readBytes = 0

            _ = try archive.extract(entry) { data in
                if readBytes < headerSize {
                    imageData.append(data)
                    readBytes += data.count
                }
            }

            // NSImageRepを使ってサイズ情報のみ取得
            if let imageRep = NSBitmapImageRep(data: imageData) {
                let width = imageRep.pixelsWide
                let height = imageRep.pixelsHigh
                if width > 0 && height > 0 {
                    return CGSize(width: width, height: height)
                }
            }

            // ヘッダーだけでは取得できなかった場合、画像全体をロード
            imageData.removeAll()
            _ = try archive.extract(entry) { data in
                imageData.append(data)
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
        } catch {
            return nil
        }
    }

    /// 指定されたインデックスの画像ファイルサイズを取得
    func fileSize(at index: Int) -> Int64? {
        // パスワード付きアーカイブの場合（展開済みファイルから取得）
        if !extractedImagePaths.isEmpty {
            guard index >= 0 && index < extractedImagePaths.count else { return nil }
            let path = extractedImagePaths[index]
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: path)
                return attrs[.size] as? Int64
            } catch {
                return nil
            }
        }

        guard index >= 0 && index < imageEntries.count else {
            return nil
        }
        return Int64(imageEntries[index].uncompressedSize)
    }

    /// 指定されたインデックスの画像フォーマットを取得
    func imageFormat(at index: Int) -> String? {
        // パスワード付きアーカイブの場合
        if !extractedImagePaths.isEmpty {
            guard index >= 0 && index < extractedImagePaths.count else { return nil }
            let path = extractedImagePaths[index]
            let ext = (path as NSString).pathExtension.lowercased()
            return formatFromExtension(ext)
        }

        guard index >= 0 && index < imageEntries.count else {
            return nil
        }
        let path = imageEntries[index].path
        let ext = (path as NSString).pathExtension.lowercased()
        return formatFromExtension(ext)
    }

    private func formatFromExtension(_ ext: String) -> String {

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
}
