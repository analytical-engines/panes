import Foundation
import AppKit

/// 通常の画像ファイルから読み込むImageSource実装
class FileImageSource: ImageSource {
    private let imageURLs: [URL]
    private let baseName: String

    init?(urls: [URL]) {
        // URLリストから画像ファイルを収集（フォルダの場合は中身を探索）
        var collectedURLs: [URL] = []
        let imageExtensions = ["jpg", "jpeg", "png", "JPG", "JPEG", "PNG"]
        let fileManager = FileManager.default

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                // ディレクトリの場合：中の画像ファイルを再帰的に探索
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
        // 複数ファイルの場合は最初のファイルの親ディレクトリを返す
        return imageURLs.first?.deletingLastPathComponent()
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
}
