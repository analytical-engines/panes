import Foundation
import AppKit

/// zipアーカイブから画像を読み込むImageSource実装
class ArchiveImageSource: ImageSource {
    private let archiveReader: ArchiveReader
    private let archiveURL: URL

    init?(url: URL) {
        guard let reader = ArchiveReader(url: url) else {
            return nil
        }
        self.archiveReader = reader
        self.archiveURL = url
    }

    var sourceName: String {
        return archiveURL.lastPathComponent
    }

    var imageCount: Int {
        return archiveReader.imageCount
    }

    /// 暗号化されたエントリが存在するか
    var hasEncryptedEntries: Bool {
        return archiveReader.hasEncryptedEntries
    }

    var sourceURL: URL? {
        return archiveURL
    }

    func loadImage(at index: Int) -> NSImage? {
        return archiveReader.loadImage(at: index)
    }

    func fileName(at index: Int) -> String? {
        return archiveReader.fileName(at: index)
    }

    func imageSize(at index: Int) -> CGSize? {
        return archiveReader.imageSize(at: index)
    }

    func fileSize(at index: Int) -> Int64? {
        return archiveReader.fileSize(at: index)
    }

    func imageFormat(at index: Int) -> String? {
        return archiveReader.imageFormat(at: index)
    }
}
