import Foundation
import AppKit
import CryptoKit

/// 画像ソースのプロトコル（zipアーカイブ、通常ファイルなど）
protocol ImageSource {
    /// ソース名（ファイル名など）
    var sourceName: String { get }

    /// 画像の総数
    var imageCount: Int { get }

    /// ソースの元となるURL（設定保存用の識別に使用）
    var sourceURL: URL? { get }

    /// 指定されたインデックスの画像を読み込む
    func loadImage(at index: Int) -> NSImage?

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String?
}

extension ImageSource {
    /// ファイル識別用のユニークキーを生成
    /// ファイル名 + サイズ + 先頭32KBのハッシュ値
    func generateFileKey() -> String? {
        guard let url = sourceURL else { return nil }

        let fileName = url.lastPathComponent

        // ファイルサイズを取得
        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            return nil
        }

        // 先頭32KBのハッシュ値を計算
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? fileHandle.close() }

        let chunkSize = 32 * 1024 // 32KB
        guard let data = try? fileHandle.read(upToCount: chunkSize) else {
            return nil
        }

        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        // ファイル名-サイズ-ハッシュ の形式
        return "\(fileName)-\(fileSize)-\(hashString.prefix(16))"
    }
}
