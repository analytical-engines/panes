import Foundation
import SwiftData

/// 画像カタログエントリの種類
enum ImageCatalogType: Int, Codable {
    case individual = 0  // 個別画像ファイル
    case archived = 1    // 書庫/フォルダ内の画像
}

// MARK: - 個別画像用モデル

/// SwiftData用の個別画像カタログモデル
@Model
final class StandaloneImageData {
    /// 画像の一意識別子（fileKeyと同じ: サイズ-ハッシュ）
    @Attribute(.unique) var id: String

    /// ファイルの内容識別キー（サイズ-ハッシュ）
    var fileKey: String

    /// ファイルの絶対パス
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

    /// ワークスペースID（""=デフォルト、将来のworkspace機能で使用）
    var workspaceId: String = ""

    init(fileKey: String, filePath: String, fileName: String) {
        self.id = fileKey
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
            catalogType: .individual,
            relativePath: nil,
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

    /// メタデータがあるかどうか（メモまたはタグ）
    var hasMetadata: Bool {
        (memo != nil && !memo!.isEmpty) || (tagsData != nil && !getTags().isEmpty)
    }
}

// MARK: - 書庫/フォルダ内画像用モデル

/// SwiftData用の書庫/フォルダ内画像カタログモデル
@Model
final class ArchiveContentImageData {
    /// 画像の一意識別子（fileKeyと同じ: サイズ-ハッシュ）
    @Attribute(.unique) var id: String

    /// ファイルの内容識別キー（サイズ-ハッシュ）
    var fileKey: String

    /// 親（書庫/フォルダ）のパス
    var parentPath: String

    /// 書庫/フォルダ内の相対パス
    var relativePath: String

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

    /// ワークスペースID（""=デフォルト、将来のworkspace機能で使用）
    var workspaceId: String = ""

    init(fileKey: String, parentPath: String, relativePath: String, fileName: String) {
        self.id = fileKey
        self.fileKey = fileKey
        self.parentPath = parentPath
        self.relativePath = relativePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
    }

    /// ImageCatalogEntry に変換
    func toEntry() -> ImageCatalogEntry {
        ImageCatalogEntry(
            id: id,
            fileKey: fileKey,
            filePath: parentPath,
            fileName: fileName,
            catalogType: .archived,
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

    /// メタデータがあるかどうか（メモまたはタグ）
    var hasMetadata: Bool {
        (memo != nil && !memo!.isEmpty) || (tagsData != nil && !getTags().isEmpty)
    }
}

// MARK: - 旧モデル（マイグレーション用に残す）

/// SwiftData用の画像カタログモデル（後方互換性のため残す）
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
        get { ImageCatalogType(rawValue: catalogTypeRaw) ?? .individual }
        set { catalogTypeRaw = newValue.rawValue }
    }

    /// 個別画像ファイル用イニシャライザ
    init(fileKey: String, filePath: String, fileName: String) {
        self.id = fileKey  // 画像は内容で一意に識別
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.catalogTypeRaw = ImageCatalogType.individual.rawValue
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
        self.catalogTypeRaw = ImageCatalogType.archived.rawValue
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
