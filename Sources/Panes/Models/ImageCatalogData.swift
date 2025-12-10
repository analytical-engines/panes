import Foundation
import SwiftData

/// 画像カタログエントリの種類
enum ImageCatalogType: Int, Codable {
    case standalone = 0      // 個別画像ファイル
    case archiveContent = 1  // 書庫/フォルダ内の画像
}

/// SwiftData用の画像カタログモデル（個別画像のメタデータ）
@Model
final class ImageCatalogData {
    /// 画像の一意識別子（fileKeyと同じ: サイズ-ハッシュ）
    @Attribute(.unique) var id: String

    /// ファイルの内容識別キー（サイズ-ハッシュ）
    var fileKey: String

    /// ファイルパス（個別画像の場合は絶対パス、書庫内画像の場合は親のパス）
    var filePath: String

    /// ファイル名
    var fileName: String

    /// エントリの種類（0: 個別画像, 1: 書庫/フォルダ内画像）
    var catalogTypeRaw: Int = 0

    /// 書庫/フォルダ内の相対パス（archiveContentの場合のみ使用）
    var relativePath: String? = nil

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

    /// 種類を取得
    var catalogType: ImageCatalogType {
        get { ImageCatalogType(rawValue: catalogTypeRaw) ?? .standalone }
        set { catalogTypeRaw = newValue.rawValue }
    }

    /// 個別画像ファイル用イニシャライザ
    init(fileKey: String, filePath: String, fileName: String) {
        self.id = fileKey  // 画像は内容で一意に識別
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.catalogTypeRaw = ImageCatalogType.standalone.rawValue
        self.relativePath = nil
        self.lastAccessDate = Date()
        self.accessCount = 1
    }

    /// 書庫/フォルダ内画像用イニシャライザ
    init(fileKey: String, parentPath: String, relativePath: String, fileName: String) {
        self.id = fileKey
        self.fileKey = fileKey
        self.filePath = parentPath
        self.fileName = fileName
        self.catalogTypeRaw = ImageCatalogType.archiveContent.rawValue
        self.relativePath = relativePath
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
            catalogType: catalogType,
            relativePath: relativePath,
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
