import Foundation
import SwiftData

/// SwiftData用のファイル履歴モデル
@Model
final class FileHistoryData {
    @Attribute(.unique) var fileKey: String
    var filePath: String
    var fileName: String
    var lastAccessDate: Date
    var accessCount: Int

    /// ページ表示設定（JSON形式で保存）
    var pageSettingsData: Data?

    /// ユーザーメモ
    var memo: String?

    init(fileKey: String, filePath: String, fileName: String) {
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
        self.pageSettingsData = nil
    }

    /// FileHistoryEntry に変換（既存のコードとの互換性のため）
    /// isAccessibleはこの時点でチェックしてキャッシュする
    func toEntry() -> FileHistoryEntry {
        FileHistoryEntry(
            fileKey: fileKey,
            filePath: filePath,
            fileName: fileName,
            lastAccessDate: lastAccessDate,
            accessCount: accessCount,
            memo: memo,
            isAccessible: FileManager.default.fileExists(atPath: filePath)
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
}
