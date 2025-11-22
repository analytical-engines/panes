import Foundation

/// ファイル履歴のエントリ
struct FileHistoryEntry: Codable, Identifiable {
    let id: String // fileKeyと同じ
    let fileKey: String
    let filePath: String
    let fileName: String
    var lastAccessDate: Date
    var accessCount: Int

    init(fileKey: String, filePath: String, fileName: String) {
        self.id = fileKey
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
}

/// ファイル履歴を管理するクラス
@Observable
class FileHistoryManager {
    private let historyKey = "fileHistory"
    private let maxHistoryCount = 50

    var history: [FileHistoryEntry] = []

    init() {
        loadHistory()
    }

    /// 履歴を読み込む
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([FileHistoryEntry].self, from: data) else {
            return
        }
        history = decoded
    }

    /// 履歴を保存
    private func saveHistory() {
        guard let encoded = try? JSONEncoder().encode(history) else {
            return
        }
        UserDefaults.standard.set(encoded, forKey: historyKey)
    }

    /// ファイルアクセスを記録
    func recordAccess(fileKey: String, filePath: String, fileName: String) {
        // 既存のエントリを探す
        if let index = history.firstIndex(where: { $0.fileKey == fileKey }) {
            // 既存エントリを更新
            var entry = history[index]
            entry.lastAccessDate = Date()
            entry.accessCount += 1

            // 先頭に移動
            history.remove(at: index)
            history.insert(entry, at: 0)
        } else {
            // 新規エントリを追加
            let newEntry = FileHistoryEntry(fileKey: fileKey, filePath: filePath, fileName: fileName)
            history.insert(newEntry, at: 0)

            // 上限を超えたら古いものを削除
            if history.count > maxHistoryCount {
                history.removeLast()
            }
        }

        saveHistory()
    }

    /// 最近の履歴を取得（最新n件）
    func getRecentHistory(limit: Int = 10) -> [FileHistoryEntry] {
        return Array(history.prefix(limit))
    }

    /// 指定したエントリを削除
    func removeEntry(withId id: String) {
        history.removeAll(where: { $0.id == id })
        saveHistory()
    }

    /// 指定したfileKeyのエントリを削除
    func removeEntry(withFileKey fileKey: String) {
        history.removeAll(where: { $0.fileKey == fileKey })
        saveHistory()
    }

    /// 全ての履歴をクリア
    func clearAllHistory() {
        history.removeAll()
        saveHistory()
    }
}
