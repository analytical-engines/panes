import Foundation
import SwiftData

/// SwiftData用のファイル履歴モデル
@Model
final class FileHistoryData {
    /// 履歴エントリの一意識別子（ファイル名+fileKeyのハッシュ）
    @Attribute(.unique) var id: String

    /// ファイルの内容識別キー（サイズ+ハッシュ）- 複数エントリで共有可能
    var fileKey: String

    /// ページ設定の参照先ID（nilなら自分がページ設定を持つ）
    var pageSettingsRef: String?

    var filePath: String
    var fileName: String
    var lastAccessDate: Date
    var accessCount: Int

    /// ページ表示設定（JSON形式で保存）
    var pageSettingsData: Data?

    /// ユーザーメモ
    var memo: String?

    // MARK: - 表示状態設定（UserDefaultsから移行）

    /// 表示モード（"single" or "spread"）
    var viewMode: String?

    /// 現在ページ（ソースインデックスとして保存）
    var savedPage: Int?

    /// 読み方向（"rightToLeft" or "leftToRight"）
    var readingDirection: String?

    /// ソート方法（ImageSortMethodのrawValue）
    var sortMethod: String?

    /// ソート逆順
    var sortReversed: Bool?

    /// パスワード保護されているか
    var isPasswordProtected: Bool?

    /// ワークスペースID（""=デフォルト、将来のworkspace機能で使用）
    var workspaceId: String = ""

    init(fileKey: String, filePath: String, fileName: String) {
        self.id = FileHistoryData.generateId(fileName: fileName, fileKey: fileKey)
        self.fileKey = fileKey
        self.pageSettingsRef = nil
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
        self.pageSettingsData = nil
    }

    /// ページ設定の参照先を指定して初期化
    init(fileKey: String, pageSettingsRef: String?, filePath: String, fileName: String) {
        self.id = FileHistoryData.generateId(fileName: fileName, fileKey: fileKey)
        self.fileKey = fileKey
        self.pageSettingsRef = pageSettingsRef
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
        self.pageSettingsData = nil
    }

    /// エントリIDを生成（ファイル名+fileKeyのハッシュ）
    static func generateId(fileName: String, fileKey: String) -> String {
        let combined = "\(fileName)-\(fileKey)"
        let data = combined.data(using: .utf8) ?? Data()
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }

    /// FileHistoryEntry に変換（既存のコードとの互換性のため）
    func toEntry() -> FileHistoryEntry {
        FileHistoryEntry(
            id: id,
            fileKey: fileKey,
            pageSettingsRef: pageSettingsRef,
            filePath: filePath,
            fileName: fileName,
            lastAccessDate: lastAccessDate,
            accessCount: accessCount,
            memo: memo,
            viewMode: viewMode,
            savedPage: savedPage,
            readingDirection: readingDirection,
            sortMethod: sortMethod,
            sortReversed: sortReversed,
            isPasswordProtected: isPasswordProtected
        )
    }

    /// ページ表示設定を取得
    func getPageSettings() -> PageDisplaySettings? {
        guard let data = pageSettingsData else { return nil }
        return try? JSONDecoder().decode(PageDisplaySettings.self, from: data)
    }

    /// ページ表示設定を保存
    func setPageSettings(_ settings: PageDisplaySettings) {
        pageSettingsData = try? JSONEncoder().encode(settings)
    }

    /// 旧形式のIDを新形式に移行
    /// SwiftDataは@Attribute(.unique)でもプロパティの更新は許可される
    func migrateIdToNewFormat(fileName: String, fileKey: String) {
        let newId = FileHistoryData.generateId(fileName: fileName, fileKey: fileKey)
        if id != newId {
            id = newId
            self.fileKey = fileKey  // fileKeyも同時に更新
        }
    }
}
