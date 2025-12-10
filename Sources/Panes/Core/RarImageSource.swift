import Foundation
import AppKit
import CryptoKit

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

    var isStandaloneImageSource: Bool {
        return false  // 書庫は常にfalse
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

    /// 指定されたインデックスの画像の相対パス（書庫内でのパス）
    func imageRelativePath(at index: Int) -> String? {
        return rarReader.fileName(at: index)
    }

    /// 指定されたインデックスの画像用fileKeyを生成
    /// 書庫内画像は画像データのハッシュを使用
    func generateImageFileKey(at index: Int) -> String? {
        guard let imageData = rarReader.imageData(at: index) else { return nil }

        let dataSize = Int64(imageData.count)
        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(dataSize)-\(hashString.prefix(16))"
    }
}
