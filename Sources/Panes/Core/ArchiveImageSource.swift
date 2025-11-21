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

    func loadImage(at index: Int) -> NSImage? {
        return archiveReader.loadImage(at: index)
    }

    func fileName(at index: Int) -> String? {
        return archiveReader.fileName(at: index)
    }
}
