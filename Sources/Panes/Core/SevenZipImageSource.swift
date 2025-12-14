import Foundation
import AppKit
import CryptoKit
import SWCompression

/// 7-Zipアーカイブから画像を読み込むImageSource実装
class SevenZipImageSource: ImageSource {
    private let sevenZipReader: SevenZipReader
    private let archiveURL: URL

    /// 進捗報告用のコールバック型
    typealias PhaseCallback = @Sendable (String) async -> Void
    /// エラー報告用のコールバック型
    typealias ErrorCallback = @Sendable (String) async -> Void

    /// 非同期ファクトリメソッド（進捗報告付き）
    static func create(url: URL, onPhaseChange: PhaseCallback? = nil, onError: ErrorCallback? = nil) async -> SevenZipImageSource? {
        print("📦 SevenZipImageSource.create: \(url.lastPathComponent)")
        guard let reader = await SevenZipReader.create(url: url, onPhaseChange: onPhaseChange, onError: onError) else {
            print("📦 SevenZipImageSource.create: Failed to create reader")
            return nil
        }
        print("📦 SevenZipImageSource.create: Success, \(reader.imageCount) images")
        return SevenZipImageSource(reader: reader, url: url)
    }

    /// 内部初期化（ファクトリメソッドから呼ばれる）
    private init(reader: SevenZipReader, url: URL) {
        self.sevenZipReader = reader
        self.archiveURL = url
    }

    /// 同期的な初期化（後方互換性のため）
    init?(url: URL) {
        guard let reader = SevenZipReader(url: url) else {
            return nil
        }
        self.sevenZipReader = reader
        self.archiveURL = url
    }

    var sourceName: String {
        return archiveURL.lastPathComponent
    }

    var imageCount: Int {
        return sevenZipReader.imageCount
    }

    var sourceURL: URL? {
        return archiveURL
    }

    var isStandaloneImageSource: Bool {
        return false  // 書庫は常にfalse
    }

    func loadImage(at index: Int) -> NSImage? {
        return sevenZipReader.loadImage(at: index)
    }

    func fileName(at index: Int) -> String? {
        return sevenZipReader.fileName(at: index)
    }

    func imageSize(at index: Int) -> CGSize? {
        return sevenZipReader.imageSize(at: index)
    }

    func fileSize(at index: Int) -> Int64? {
        return sevenZipReader.fileSize(at: index)
    }

    func imageFormat(at index: Int) -> String? {
        return sevenZipReader.imageFormat(at: index)
    }

    func fileDate(at index: Int) -> Date? {
        // TODO: 7zエントリの更新日時を取得（将来実装）
        return nil
    }

    /// 指定されたインデックスの画像の相対パス（書庫内でのパス）
    func imageRelativePath(at index: Int) -> String? {
        guard index >= 0 && index < sevenZipReader.imageEntryInfos.count else {
            return nil
        }
        return sevenZipReader.imageEntryInfos[index].name
    }

    /// 指定されたインデックスの画像用fileKeyを生成
    /// 書庫内画像は画像データのハッシュを使用
    func generateImageFileKey(at index: Int) -> String? {
        guard let imageData = sevenZipReader.imageData(at: index) else { return nil }

        let dataSize = Int64(imageData.count)
        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(dataSize)-\(hashString.prefix(16))"
    }
}
