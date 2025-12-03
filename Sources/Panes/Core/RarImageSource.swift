import Foundation
import AppKit

/// RARアーカイブから画像を読み込むImageSource実装
class RarImageSource: ImageSource {
    private let rarReader: RarReader
    private let archiveURL: URL

    init?(url: URL) {
        guard let reader = RarReader(url: url) else {
            return nil
        }
        self.rarReader = reader
        self.archiveURL = url
    }

    var sourceName: String {
        return archiveURL.lastPathComponent
    }

    var imageCount: Int {
        return rarReader.imageCount
    }

    var sourceURL: URL? {
        return archiveURL
    }

    func loadImage(at index: Int) -> NSImage? {
        return rarReader.loadImage(at: index)
    }

    func fileName(at index: Int) -> String? {
        return rarReader.fileName(at: index)
    }

    func imageSize(at index: Int) -> CGSize? {
        return rarReader.imageSize(at: index)
    }

    func fileSize(at index: Int) -> Int64? {
        return rarReader.fileSize(at: index)
    }

    func imageFormat(at index: Int) -> String? {
        return rarReader.imageFormat(at: index)
    }
}
