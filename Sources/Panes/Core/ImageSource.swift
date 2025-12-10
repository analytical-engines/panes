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

    /// 個別画像ソースかどうか（true: 単一の画像ファイル、false: 書庫/フォルダ）
    var isStandaloneImageSource: Bool { get }

    /// 指定されたインデックスの画像を読み込む
    func loadImage(at index: Int) -> NSImage?

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String?

    /// 指定されたインデックスの画像サイズを取得（画像全体を読み込まずに）
    func imageSize(at index: Int) -> CGSize?

    /// 指定されたインデックスの画像ファイルサイズを取得
    func fileSize(at index: Int) -> Int64?

    /// 指定されたインデックスの画像フォーマットを取得
    func imageFormat(at index: Int) -> String?

    /// ファイル識別用のユニークキーを生成
    func generateFileKey() -> String?

    /// 指定されたインデックスの画像用fileKeyを生成（画像カタログ用）
    func generateImageFileKey(at index: Int) -> String?

    /// 指定されたインデックスの画像の相対パス（書庫/フォルダ内でのパス）
    func imageRelativePath(at index: Int) -> String?
}

extension ImageSource {
    /// ファイル識別用のユニークキーを生成
    /// サイズ + 先頭32KBのハッシュ値（ファイル名は含めない）
    func generateFileKey() -> String? {
        guard let url = sourceURL else { return nil }

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

        // サイズ-ハッシュ の形式（ファイル名を含めないことでリネームしても同一ファイルと認識）
        return "\(fileSize)-\(hashString.prefix(16))"
    }

    /// fileKeyからサイズ-ハッシュ部分を抽出（旧フォーマット対応）
    /// 旧: "ファイル名-12345-abcdef1234567890"
    /// 新: "12345-abcdef1234567890"
    static func extractContentKey(from fileKey: String) -> String {
        // ハッシュは16文字固定、その前にハイフン、さらにその前にサイズ（数字のみ）
        // 末尾から: ハッシュ16文字 + ハイフン1文字 + サイズ部分
        let components = fileKey.split(separator: "-")
        guard components.count >= 2 else { return fileKey }

        // 最後の要素がハッシュ（16文字の16進数）
        let lastComponent = String(components.last!)
        guard lastComponent.count == 16,
              lastComponent.allSatisfy({ $0.isHexDigit }) else {
            return fileKey
        }

        // 最後から2番目がサイズ（数字のみ）
        let secondLast = String(components[components.count - 2])
        guard secondLast.allSatisfy({ $0.isNumber }) else {
            return fileKey
        }

        // サイズ-ハッシュ の形式で返す
        return "\(secondLast)-\(lastComponent)"
    }
}
