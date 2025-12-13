import Foundation
import ZIPFoundation
import AppKit

/// zipアーカイブから画像を読み込むクラス
class ArchiveReader {
    private let archiveURL: URL
    private let archive: Archive
    private(set) var imageEntries: [Entry] = []

    /// 暗号化されたエントリが存在するか（スキップされたエントリがある場合true）
    private(set) var hasEncryptedEntries: Bool = false

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド（進捗報告付き）
    static func create(url: URL, onPhaseChange: PhaseCallback? = nil) async -> ArchiveReader? {
        let startTime = CFAbsoluteTimeGetCurrent()

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
        if let totalEntries = readTotalEntriesFromZip(url: url) {
            let accessibleEntries = archive.reduce(0) { count, _ in count + 1 }
            if totalEntries > accessibleEntries {
                hasEncryptedEntries = true
                print("⚠️ Encrypted entries detected: \(totalEntries) total, \(accessibleEntries) accessible")
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Total init time: \(String(format: "%.3f", totalTime))s")

        return ArchiveReader(url: url, archive: archive, imageEntries: imageEntries, hasEncryptedEntries: hasEncryptedEntries)
    }

    /// 内部初期化（ファクトリメソッドから呼ばれる）
    private init(url: URL, archive: Archive, imageEntries: [Entry], hasEncryptedEntries: Bool) {
        self.archiveURL = url
        self.archive = archive
        self.imageEntries = imageEntries
        self.hasEncryptedEntries = hasEncryptedEntries
    }

    /// 同期的な初期化（後方互換性のため）
    init?(url: URL) {
        let startTime = CFAbsoluteTimeGetCurrent()
        self.archiveURL = url

        // zipアーカイブを開く
        let openStart = CFAbsoluteTimeGetCurrent()
        do {
            self.archive = try Archive(url: url, accessMode: .read)
        } catch {
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        print("⏱️ Archive open time: \(String(format: "%.3f", openTime))s")

        // 画像ファイルのみを抽出してソート
        let extractStart = CFAbsoluteTimeGetCurrent()
        self.imageEntries = Self.extractImageEntries(from: archive)
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ Extract & sort time: \(String(format: "%.3f", extractTime))s")

        // 暗号化エントリのチェック
        // ZIPFoundationは暗号化されたエントリをスキップするため、
        // 全エントリ数とアクセス可能なエントリ数を比較
        if let totalEntries = Self.readTotalEntriesFromZip(url: url) {
            let accessibleEntries = archive.reduce(0) { count, _ in count + 1 }
            if totalEntries > accessibleEntries {
                self.hasEncryptedEntries = true
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

    /// 指定されたインデックスの画像データを取得
    func imageData(at index: Int) -> Data? {
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
        return imageEntries.count
    }

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < imageEntries.count else {
            return nil
        }
        return (imageEntries[index].path as NSString).lastPathComponent
    }

    /// 指定されたインデックスの画像サイズを取得（画像全体を読み込まずに）
    func imageSize(at index: Int) -> CGSize? {
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
        let path = imageEntries[index].path
        let ext = (path as NSString).pathExtension.lowercased()

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
