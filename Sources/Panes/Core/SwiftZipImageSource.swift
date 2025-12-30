import Foundation
import AppKit
import CryptoKit

/// swift-zip-archiveを使用したZIPアーカイブのImageSource実装
/// 破損アーカイブやパスワード付きアーカイブにも対応
class SwiftZipImageSource: ImageSource {
    private let zipReader: SwiftZipReader
    private let archiveURL: URL

    /// パスワードが必要かどうか
    var needsPassword: Bool {
        return zipReader.needsPassword
    }

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド
    static func create(url: URL, password: String? = nil, onPhaseChange: PhaseCallback? = nil) async -> SwiftZipImageSource? {
        guard let reader = await SwiftZipReader.create(url: url, password: password, onPhaseChange: onPhaseChange) else {
            return nil
        }
        return SwiftZipImageSource(reader: reader, url: url)
    }

    private init(reader: SwiftZipReader, url: URL) {
        self.zipReader = reader
        self.archiveURL = url
    }

    var sourceName: String {
        return archiveURL.lastPathComponent
    }

    var imageCount: Int {
        return zipReader.imageCount
    }

    var sourceURL: URL? {
        return archiveURL
    }

    var isStandaloneImageSource: Bool {
        return false  // 書庫は常にfalse
    }

    func loadImage(at index: Int) -> NSImage? {
        return zipReader.loadImage(at: index)
    }

    func fileName(at index: Int) -> String? {
        return zipReader.fileName(at: index)
    }

    func imageSize(at index: Int) -> CGSize? {
        return zipReader.imageSize(at: index)
    }

    func fileSize(at index: Int) -> Int64? {
        return zipReader.fileSize(at: index)
    }

    func imageFormat(at index: Int) -> String? {
        return zipReader.imageFormat(at: index)
    }

    func fileDate(at index: Int) -> Date? {
        return zipReader.fileDate(at: index)
    }

    /// 指定されたインデックスの画像の相対パス（書庫内でのパス）
    func imageRelativePath(at index: Int) -> String? {
        return zipReader.fileName(at: index)
    }

    /// 指定されたインデックスの画像用fileKeyを生成
    /// 書庫内画像は画像データのハッシュを使用
    func generateImageFileKey(at index: Int) -> String? {
        guard let imageData = zipReader.imageData(at: index) else { return nil }

        let dataSize = Int64(imageData.count)
        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(dataSize)-\(hashString.prefix(16))"
    }
}
