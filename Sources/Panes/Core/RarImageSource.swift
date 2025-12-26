import Foundation
import AppKit
import CryptoKit

/// RARアーカイブから画像を読み込むImageSource実装
class RarImageSource: ImageSource {
    private let rarReader: RarReader
    private let archiveURL: URL

    /// パスワードが必要かどうか
    var needsPassword: Bool {
        return rarReader.needsPassword
    }

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド（進捗報告付き、パスワード対応）
    static func create(url: URL, password: String? = nil, onPhaseChange: PhaseCallback? = nil) async -> RarImageSource? {
        guard let reader = await RarReader.create(url: url, password: password, onPhaseChange: onPhaseChange) else {
            return nil
        }
        return RarImageSource(reader: reader, url: url)
    }

    /// 内部初期化（ファクトリメソッドから呼ばれる）
    private init(reader: RarReader, url: URL) {
        self.rarReader = reader
        self.archiveURL = url
    }

    /// 同期的な初期化（後方互換性のため、パスワード対応）
    init?(url: URL, password: String? = nil) {
        guard let reader = RarReader(url: url, password: password) else {
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

    func fileDate(at index: Int) -> Date? {
        // TODO: RARエントリの更新日時を取得（将来実装）
        return nil
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
