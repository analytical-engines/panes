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

    init(fileKey: String, filePath: String, fileName: String) {
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
    }

    /// ファイルがアクセス可能かどうか
    var isAccessible: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    /// FileHistoryEntry に変換（既存のコードとの互換性のため）
    func toEntry() -> FileHistoryEntry {
        FileHistoryEntry(
            fileKey: fileKey,
            filePath: filePath,
            fileName: fileName,
            lastAccessDate: lastAccessDate,
            accessCount: accessCount
        )
    }
}
