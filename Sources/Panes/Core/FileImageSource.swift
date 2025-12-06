import Foundation
import AppKit

/// 通常の画像ファイルから読み込むImageSource実装
class FileImageSource: ImageSource {
    private let imageURLs: [URL]
    private let baseName: String
    private let folderURL: URL?  // フォルダが指定された場合はそのURL

    init?(urls: [URL]) {
        // URLリストから画像ファイルを収集（フォルダの場合は中身を探索）
        var collectedURLs: [URL] = []
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "jp2", "j2k",
                                "JPG", "JPEG", "PNG", "GIF", "WEBP", "JP2", "J2K"]
        let fileManager = FileManager.default
        var detectedFolderURL: URL? = nil

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                // ディレクトリの場合：中の画像ファイルを再帰的に探索
                // 単一フォルダの場合はそのURLを記録
                if urls.count == 1 {
                    detectedFolderURL = url
                }
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if imageExtensions.contains(fileURL.pathExtension) {
                            collectedURLs.append(fileURL)
                        }
                    }
                }
            } else {
                // ファイルの場合：画像なら追加
                if imageExtensions.contains(url.pathExtension) {
                    collectedURLs.append(url)
                }
            }
        }

        guard !collectedURLs.isEmpty else {
            return nil
        }

        // ファイル名でソート
        self.imageURLs = collectedURLs.sorted { url1, url2 in
            url1.path.localizedStandardCompare(url2.path) == .orderedAscending
        }

        // フォルダURLを保持
        self.folderURL = detectedFolderURL

        // ソース名を決定
        if urls.count == 1 {
            self.baseName = urls[0].lastPathComponent
        } else {
            // 複数の場合は最初のアイテムの親ディレクトリ名
            let parentPath = collectedURLs[0].deletingLastPathComponent()
            self.baseName = parentPath.lastPathComponent
        }
    }

    var sourceName: String {
        return baseName
    }

    var imageCount: Int {
        return imageURLs.count
    }

    var sourceURL: URL? {
        // フォルダが指定された場合はそのURL、それ以外は最初のファイルの親ディレクトリ
        return folderURL ?? imageURLs.first?.deletingLastPathComponent()
    }

    /// フォルダ用のファイルキー生成（inodeベース）
    /// フォルダの中身が変わっても同じフォルダとして識別する
    func generateFileKey() -> String? {
        guard let url = sourceURL else {
            DebugLogger.log("⚠️ generateFileKey: sourceURL is nil", level: .minimal)
            return nil
        }

        DebugLogger.log("📁 generateFileKey: url = \(url.path)", level: .verbose)

        // inodeを取得
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = attrs[.systemFileNumber] as? UInt64 else {
            DebugLogger.log("⚠️ generateFileKey: failed to get inode for \(url.path)", level: .minimal)
            return nil
        }

        // ボリューム識別子を取得（別ボリュームで同じinodeの可能性があるため）
        guard let resourceValues = try? url.resourceValues(forKeys: [.volumeIdentifierKey]),
              let volumeID = resourceValues.volumeIdentifier else {
            // ボリュームIDが取得できない場合はinodeのみ使用
            let key = "folder-\(inode)"
            DebugLogger.log("📁 generateFileKey: key = \(key)", level: .verbose)
            return key
        }

        // ボリュームIDはNSCopyingに準拠したオブジェクトなのでdescriptionを使用
        let key = "folder-\(volumeID.description)-\(inode)"
        DebugLogger.log("📁 generateFileKey: key = \(key)", level: .verbose)
        return key
    }

    func loadImage(at index: Int) -> NSImage? {
        guard index >= 0 && index < imageURLs.count else {
            return nil
        }

        let url = imageURLs[index]
        return NSImage(contentsOf: url)
    }

    func fileName(at index: Int) -> String? {
        guard index >= 0 && index < imageURLs.count else {
            return nil
        }
        return imageURLs[index].lastPathComponent
    }

    func imageSize(at index: Int) -> CGSize? {
        guard index >= 0 && index < imageURLs.count else {
            return nil
        }

        let url = imageURLs[index]

        // NSImageRepを使ってサイズ情報のみ取得
        guard let imageRep = NSImageRep(contentsOf: url) else {
            return nil
        }

        return CGSize(width: imageRep.pixelsWide, height: imageRep.pixelsHigh)
    }

    func fileSize(at index: Int) -> Int64? {
        guard index >= 0 && index < imageURLs.count else {
            return nil
        }
        let url = imageURLs[index]
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }

    func imageFormat(at index: Int) -> String? {
        guard index >= 0 && index < imageURLs.count else {
            return nil
        }
        let ext = imageURLs[index].pathExtension.lowercased()

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
