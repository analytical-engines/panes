import Foundation
import SwiftData

/// SwiftData用の画像カタログモデル（個別画像のメタデータ）
@Model
final class ImageCatalogData {
    /// 画像の一意識別子（fileKeyと同じ: サイズ-ハッシュ）
    @Attribute(.unique) var id: String

    /// ファイルの内容識別キー（サイズ-ハッシュ）
    var fileKey: String

    /// ファイルパス
    var filePath: String

    /// ファイル名
    var fileName: String

    /// 最終アクセス日時
    var lastAccessDate: Date

    /// アクセス回数
    var accessCount: Int

    /// ユーザーメモ
    var memo: String?

    /// 画像の幅（ピクセル）
    var imageWidth: Int?

    /// 画像の高さ（ピクセル）
    var imageHeight: Int?

    /// ファイルサイズ（バイト）
    var fileSize: Int64?

    /// 画像フォーマット（jpg, png, gif, webp, etc.）
    var imageFormat: String?

    /// タグ（将来拡張用、JSON配列で保存）
    var tagsData: Data?

    init(fileKey: String, filePath: String, fileName: String) {
        self.id = fileKey  // 画像は内容で一意に識別
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
    }

    /// ImageCatalogEntry に変換
    func toEntry() -> ImageCatalogEntry {
        ImageCatalogEntry(
            id: id,
            fileKey: fileKey,
            filePath: filePath,
            fileName: fileName,
            lastAccessDate: lastAccessDate,
            accessCount: accessCount,
            memo: memo,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            fileSize: fileSize,
            imageFormat: imageFormat,
            tags: getTags()
        )
    }

    /// タグを取得
    func getTags() -> [String] {
        guard let data = tagsData else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// タグを設定
    func setTags(_ tags: [String]) {
        tagsData = try? JSONEncoder().encode(tags)
    }
}
