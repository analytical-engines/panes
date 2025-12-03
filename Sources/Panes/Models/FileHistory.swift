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

    // アプリ設定への参照（最大件数を取得するため）
    var appSettings: AppSettings?

    /// 最大履歴件数（AppSettingsから取得、未設定時は50）
    private var maxHistoryCount: Int {
        appSettings?.maxHistoryCount ?? 50
    }

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
        DebugLogger.log("📊 recordAccess called: \(fileName)", level: .normal)

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

    /// 全てのアクセスカウントを1にリセット
    func resetAllAccessCounts() {
        for i in history.indices {
            history[i].accessCount = 1
        }
        saveHistory()
    }

    // MARK: - Export/Import

    private let pageDisplaySettingsKey = "pageDisplaySettings"

    /// 履歴エントリとページ表示設定をセットにした構造
    struct HistoryEntryWithSettings: Codable {
        let entry: FileHistoryEntry
        let pageSettings: PageDisplaySettings?
    }

    /// Export用のデータ構造
    struct HistoryExport: Codable {
        let exportDate: Date
        let entryCount: Int
        let entries: [HistoryEntryWithSettings]
    }

    /// 履歴をExport可能か
    var canExportHistory: Bool {
        return !history.isEmpty
    }

    /// 履歴をJSONデータとしてExport（ページ表示設定含む）
    func exportHistory() -> Data? {
        // 各履歴エントリにページ表示設定を付加
        let entriesWithSettings = history.map { entry -> HistoryEntryWithSettings in
            let pageSettings = loadPageDisplaySettings(for: entry.fileKey)
            return HistoryEntryWithSettings(entry: entry, pageSettings: pageSettings)
        }

        let exportData = HistoryExport(
            exportDate: Date(),
            entryCount: history.count,
            entries: entriesWithSettings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            return try encoder.encode(exportData)
        } catch {
            print("Failed to encode history: \(error)")
            return nil
        }
    }

    /// 指定したfileKeyのページ表示設定を読み込む
    private func loadPageDisplaySettings(for fileKey: String) -> PageDisplaySettings? {
        guard let data = UserDefaults.standard.data(forKey: "\(pageDisplaySettingsKey)-\(fileKey)") else {
            return nil
        }
        return try? JSONDecoder().decode(PageDisplaySettings.self, from: data)
    }

    /// 指定したfileKeyのページ表示設定を保存
    private func savePageDisplaySettings(_ settings: PageDisplaySettings, for fileKey: String) {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "\(pageDisplaySettingsKey)-\(fileKey)")
        }
    }

    /// JSONデータから履歴をImport（ページ表示設定含む）
    func importHistory(from data: Data, merge: Bool) -> (success: Bool, message: String, importedCount: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let importData = try decoder.decode(HistoryExport.self, from: data)

            if merge {
                // マージモード: 既存の履歴と統合
                var merged = history
                for item in importData.entries {
                    if !merged.contains(where: { $0.fileKey == item.entry.fileKey }) {
                        merged.append(item.entry)
                        // ページ表示設定も保存（既存がない場合のみ）
                        if let settings = item.pageSettings,
                           loadPageDisplaySettings(for: item.entry.fileKey) == nil {
                            savePageDisplaySettings(settings, for: item.entry.fileKey)
                        }
                    }
                }
                // 日付順でソート（新しい順）
                merged.sort { $0.lastAccessDate > $1.lastAccessDate }
                // 上限を超えたら削除
                if merged.count > maxHistoryCount {
                    merged = Array(merged.prefix(maxHistoryCount))
                }
                history = merged
            } else {
                // 置換モード: 既存の履歴を置き換え
                history = importData.entries.map { $0.entry }
                // ページ表示設定も全て上書き
                for item in importData.entries {
                    if let settings = item.pageSettings {
                        savePageDisplaySettings(settings, for: item.entry.fileKey)
                    }
                }
            }

            saveHistory()

            return (true, "", importData.entryCount)
        } catch {
            print("Failed to decode history: \(error)")
            return (false, error.localizedDescription, 0)
        }
    }
}
