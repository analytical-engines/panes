import Foundation
import Unrar
import AppKit

/// RARアーカイブから画像を読み込むクラス
class RarReader {
    private let archiveURL: URL
    private let archive: Archive
    private(set) var imageEntries: [Entry] = []

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド（進捗報告付き）
    static func create(url: URL, onPhaseChange: PhaseCallback? = nil) async -> RarReader? {
        let startTime = CFAbsoluteTimeGetCurrent()

        // フェーズ1: アーカイブを開く
        await onPhaseChange?(L("loading_phase_opening_archive"))

        let openStart = CFAbsoluteTimeGetCurrent()
        let archive: Archive
        do {
            archive = try Archive(path: url.path)
        } catch {
            print("ERROR: Failed to open RAR archive: \(error)")
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        print("⏱️ RAR Archive open time: \(String(format: "%.3f", openTime))s")

        // フェーズ2: 画像リストを作成
        await onPhaseChange?(L("loading_phase_building_image_list"))

        let extractStart = CFAbsoluteTimeGetCurrent()
        let imageEntries: [Entry]
        do {
            imageEntries = try extractImageEntries(from: archive)
        } catch {
            print("ERROR: Failed to extract entries: \(error)")
            return nil
        }
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ RAR Extract & sort time: \(String(format: "%.3f", extractTime))s")

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ RAR Total init time: \(String(format: "%.3f", totalTime))s")

        return RarReader(url: url, archive: archive, imageEntries: imageEntries)
    }

    /// 内部初期化（ファクトリメソッドから呼ばれる）
    private init(url: URL, archive: Archive, imageEntries: [Entry]) {
        self.archiveURL = url
        self.archive = archive
        self.imageEntries = imageEntries
    }

    /// 同期的な初期化（後方互換性のため）
    init?(url: URL) {
        let startTime = CFAbsoluteTimeGetCurrent()
        self.archiveURL = url

        // RARアーカイブを開く
        let openStart = CFAbsoluteTimeGetCurrent()
        do {
            self.archive = try Archive(path: url.path)
        } catch {
            print("ERROR: Failed to open RAR archive: \(error)")
            return nil
        }
        let openTime = CFAbsoluteTimeGetCurrent() - openStart
        print("⏱️ RAR Archive open time: \(String(format: "%.3f", openTime))s")

        // 画像ファイルのみを抽出してソート
        let extractStart = CFAbsoluteTimeGetCurrent()
        do {
            self.imageEntries = try Self.extractImageEntries(from: archive)
        } catch {
            print("ERROR: Failed to extract entries: \(error)")
            return nil
        }
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ RAR Extract & sort time: \(String(format: "%.3f", extractTime))s")

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ RAR Total init time: \(String(format: "%.3f", totalTime))s")
    }

    /// アーカイブ内の画像ファイルエントリを抽出してファイル名でソート
    private static func extractImageEntries(from archive: Archive) throws -> [Entry] {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                   "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"])

        print("=== Extracting image entries from RAR archive ===")

        // 1. エントリ列挙
        let entriesStart = CFAbsoluteTimeGetCurrent()
        let allEntries = try archive.entries()
        print("⏱️ RAR entries() time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - entriesStart))s (count: \(allEntries.count))")

        // 2. フィルタリング
        let filterStart = CFAbsoluteTimeGetCurrent()
        let entries = allEntries.filter { entry in
            let path = entry.fileName
            guard !path.contains("__MACOSX"),
                  !path.contains("/._"),
                  !(path as NSString).lastPathComponent.hasPrefix("._"),
                  !(path as NSString).lastPathComponent.hasPrefix(".") else {
                return false
            }
            let ext = (path as NSString).pathExtension
            return imageExtensions.contains(ext)
        }
        print("⏱️ RAR filter time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - filterStart))s (filtered: \(entries.count))")

        // 3. ソート
        let sortStart = CFAbsoluteTimeGetCurrent()
        let sorted = entries.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }
        print("⏱️ RAR sort time: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - sortStart))s")

        print("=== First 5 RAR entries after sorting ===")
        for (index, entry) in sorted.prefix(5).enumerated() {
            print("[\(index)] \(entry.fileName)")
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

        print("Loading RAR image: \(entry.fileName) (size: \(entry.uncompressedSize) bytes)")

        do {
            let imageData = try archive.extract(entry)

            print("Extracted \(imageData.count) bytes from RAR")

            guard let image = NSImage(data: imageData) else {
                print("ERROR: Failed to create NSImage from RAR data. File: \(entry.fileName), Data size: \(imageData.count)")
                return nil
            }

            print("Successfully loaded RAR image: \(entry.fileName)")
            return image
        } catch {
            print("ERROR: Failed to extract RAR image at index \(index), file: \(entry.fileName), error: \(error)")
            return nil
        }
    }

    /// 指定されたインデックスの画像データを取得
    func imageData(at index: Int) -> Data? {
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
}
