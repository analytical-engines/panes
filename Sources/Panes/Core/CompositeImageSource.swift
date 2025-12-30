import Foundation
import AppKit
import CryptoKit

/// 複数のImageSourceを連結して1つのソースとして扱うクラス
/// 入れ子書庫を展開してフラットに表示するために使用
class CompositeImageSource: ImageSource {

    /// セグメント: 画像の連続した範囲を表す
    struct Segment {
        /// このセグメントのソース
        let source: ImageSource
        /// このセグメントがComposite内で始まるグローバルインデックス
        let globalStartIndex: Int
        /// セグメント内の画像数
        var count: Int { source.imageCount }
        /// セグメント名（デバッグ用）
        let name: String
        /// 一時ファイルのURL（クリーンアップ用、nilなら一時ファイルなし）
        let tempFileURL: URL?
    }

    /// 元となるアーカイブのURL
    private let archiveURL: URL

    /// セグメントのリスト（表示順）
    private var segments: [Segment] = []

    /// 総画像数（キャッシュ）
    private var cachedImageCount: Int = 0

    /// パスワードが必要かどうか（子書庫のいずれかが必要な場合true）
    private(set) var needsPassword: Bool = false

    /// パスワードが必要な子書庫のパス
    private(set) var passwordRequiredArchives: [String] = []

    init(archiveURL: URL) {
        self.archiveURL = archiveURL
    }

    deinit {
        cleanup()
    }

    /// セグメントを追加
    func addSegment(source: ImageSource, name: String, tempFileURL: URL? = nil) {
        let segment = Segment(
            source: source,
            globalStartIndex: cachedImageCount,
            name: name,
            tempFileURL: tempFileURL
        )
        segments.append(segment)
        cachedImageCount += source.imageCount
    }

    /// パスワードが必要な書庫を記録
    func markPasswordRequired(archivePath: String) {
        needsPassword = true
        passwordRequiredArchives.append(archivePath)
    }

    // MARK: - ImageSource Protocol

    var sourceName: String {
        return archiveURL.lastPathComponent
    }

    var imageCount: Int {
        return cachedImageCount
    }

    var sourceURL: URL? {
        return archiveURL
    }

    var isStandaloneImageSource: Bool {
        return false
    }

    func loadImage(at index: Int) -> NSImage? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }
        return source.loadImage(at: localIndex)
    }

    func fileName(at index: Int) -> String? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }
        guard let baseName = source.fileName(at: localIndex) else { return nil }

        // セグメント名がある場合（入れ子書庫の場合）、プレフィックスとして付加
        // これによりソート時に書庫ごとにグループ化される
        if let segment = findSegment(for: index), !segment.name.isEmpty {
            return "\(segment.name)/\(baseName)"
        }
        return baseName
    }

    func imageSize(at index: Int) -> CGSize? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }
        return source.imageSize(at: localIndex)
    }

    func fileSize(at index: Int) -> Int64? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }
        return source.fileSize(at: localIndex)
    }

    func imageFormat(at index: Int) -> String? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }
        return source.imageFormat(at: localIndex)
    }

    func fileDate(at index: Int) -> Date? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }
        return source.fileDate(at: localIndex)
    }

    func imageRelativePath(at index: Int) -> String? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }

        // 入れ子書庫の場合、親書庫内のパスを含める
        if let segment = findSegment(for: index), !segment.name.isEmpty {
            if let relativePath = source.imageRelativePath(at: localIndex) {
                return "\(segment.name)/\(relativePath)"
            }
            return segment.name
        }

        return source.imageRelativePath(at: localIndex)
    }

    func generateImageFileKey(at index: Int) -> String? {
        guard let (source, localIndex) = mapIndex(index) else { return nil }
        return source.generateImageFileKey(at: localIndex)
    }

    // MARK: - Index Mapping

    /// グローバルインデックスをソースとローカルインデックスにマッピング
    private func mapIndex(_ globalIndex: Int) -> (ImageSource, Int)? {
        guard globalIndex >= 0 && globalIndex < cachedImageCount else {
            DebugLogger.log("⚠️ CompositeImageSource: globalIndex \(globalIndex) out of range (0..<\(cachedImageCount))", level: .minimal)
            return nil
        }

        for segment in segments {
            let localIndex = globalIndex - segment.globalStartIndex
            if localIndex >= 0 && localIndex < segment.count {
                return (segment.source, localIndex)
            }
        }

        DebugLogger.log("⚠️ CompositeImageSource: Failed to map globalIndex \(globalIndex)", level: .minimal)
        return nil
    }

    /// グローバルインデックスに対応するセグメントを取得
    private func findSegment(for globalIndex: Int) -> Segment? {
        for segment in segments {
            let localIndex = globalIndex - segment.globalStartIndex
            if localIndex >= 0 && localIndex < segment.count {
                return segment
            }
        }
        return nil
    }

    // MARK: - Debug

    /// セグメント構造をデバッグ出力
    func debugPrintSegments() {
        for (i, segment) in segments.enumerated() {
            let name = segment.name.isEmpty ? "(parent)" : segment.name
            let endIndex = segment.globalStartIndex + segment.count - 1
            DebugLogger.log("  [\(i)] '\(name)': globalIndex \(segment.globalStartIndex)...\(endIndex) (\(segment.count) images)", level: .verbose)
        }
    }

    // MARK: - Cleanup

    /// 一時ファイルのクリーンアップ
    func cleanup() {
        for segment in segments {
            if let tempURL = segment.tempFileURL {
                try? FileManager.default.removeItem(at: tempURL)
                DebugLogger.log("🗑️ Cleaned up temp file: \(tempURL.lastPathComponent)", level: .verbose)
            }
        }
    }
}
