import Foundation
import Unrar
import AppKit

/// RARアーカイブから画像を読み込むクラス
class RarReader {
    private let archiveURL: URL
    private let archive: Archive
    private(set) var imageEntries: [Entry] = []

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
            self.imageEntries = try extractImageEntries()
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
    private func extractImageEntries() throws -> [Entry] {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                   "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"])

        print("=== Extracting image entries from RAR archive ===")

        let allEntries = try archive.entries()

        // 画像ファイルのみフィルタリング
        let entries = allEntries.filter { entry in
            let path = entry.fileName
            // 隠しファイルを除外
            guard !path.contains("__MACOSX"),
                  !path.contains("/._"),
                  !(path as NSString).lastPathComponent.hasPrefix("._"),
                  !(path as NSString).lastPathComponent.hasPrefix(".") else {
                return false
            }

            // 拡張子チェック
            let ext = (path as NSString).pathExtension
            return imageExtensions.contains(ext)
        }

        print("Filtered RAR image entries: \(entries.count)")

        // ファイル名でソート（自然順ソート）
        let sorted = entries.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }

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
}
