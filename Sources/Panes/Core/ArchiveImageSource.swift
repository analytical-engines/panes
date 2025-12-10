import Foundation
import AppKit
import CryptoKit

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

    var isStandaloneImageSource: Bool {
        return false  // 書庫は常にfalse
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

    /// 指定されたインデックスの画像の相対パス（書庫内でのパス）
    func imageRelativePath(at index: Int) -> String? {
        return archiveReader.fileName(at: index)
    }

    /// 指定されたインデックスの画像用fileKeyを生成
    /// 書庫内画像は画像データのハッシュを使用
    func generateImageFileKey(at index: Int) -> String? {
        guard let imageData = archiveReader.imageData(at: index) else { return nil }

        let dataSize = Int64(imageData.count)
        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(dataSize)-\(hashString.prefix(16))"
    }
}
