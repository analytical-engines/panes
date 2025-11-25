import Foundation
import ZIPFoundation
import AppKit

/// zipアーカイブから画像を読み込むクラス
class ArchiveReader {
    private let archiveURL: URL
    private let archive: Archive
    private(set) var imageEntries: [Entry] = []

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
        self.imageEntries = extractImageEntries()
        let extractTime = CFAbsoluteTimeGetCurrent() - extractStart
        print("⏱️ Extract & sort time: \(String(format: "%.3f", extractTime))s")

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ Total init time: \(String(format: "%.3f", totalTime))s")
    }

    /// アーカイブ内の画像ファイルエントリを抽出してファイル名でソート
    private func extractImageEntries() -> [Entry] {
        let imageExtensions = Set(["jpg", "jpeg", "png", "JPG", "JPEG", "PNG"])

        print("=== Extracting image entries from archive ===")

        // 直接フィルタリング（配列コピー不要）
        let entries = archive.filter { entry in
            // 早期リターンで不要なチェックをスキップ
            guard entry.type == .file else { return false }

            let path = entry.path
            // __MACOSXフォルダや隠しファイルを除外
            guard !path.contains("__MACOSX"),
                  !path.contains("/._"),
                  !(path as NSString).lastPathComponent.hasPrefix("._") else {
                return false
            }

            // 拡張子チェック（Setで高速化）
            let ext = (path as NSString).pathExtension
            return imageExtensions.contains(ext)
        }

        print("Filtered image entries: \(entries.count)")

        // ファイル名でソート（自然順ソート）
        let sorted = entries.sorted { entry1, entry2 in
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }

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
                return CGSize(width: imageRep.pixelsWide, height: imageRep.pixelsHigh)
            }

            // ヘッダーだけでは取得できなかった場合、画像全体をロード
            imageData.removeAll()
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }

            guard let imageRep = NSBitmapImageRep(data: imageData) else {
                return nil
            }

            return CGSize(width: imageRep.pixelsWide, height: imageRep.pixelsHigh)
        } catch {
            return nil
        }
    }
}
