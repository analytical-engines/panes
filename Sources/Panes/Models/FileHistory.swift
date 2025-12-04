import Foundation
import SwiftData

/// ファイル履歴のエントリ（UIモデル用、Codable対応）
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

    init(fileKey: String, filePath: String, fileName: String, lastAccessDate: Date, accessCount: Int) {
        self.id = fileKey
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = lastAccessDate
        self.accessCount = accessCount
    }

    /// ファイルがアクセス可能かどうか
    var isAccessible: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}

/// ファイル履歴を管理するクラス
@Observable
class FileHistoryManager {
    private let legacyHistoryKey = "fileHistory"
    private let migrationCompletedKey = "historyMigrationToSwiftDataCompleted"

    // SwiftData用
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    // アプリ設定への参照（最大件数を取得するため）
    var appSettings: AppSettings?

    /// 最大履歴件数（AppSettingsから取得、未設定時は50）
    private var maxHistoryCount: Int {
        appSettings?.maxHistoryCount ?? 50
    }

    var history: [FileHistoryEntry] = []

    init() {
        // TODO: 一時的にSwiftDataを無効化してデバッグ
        // setupSwiftData()
        // migrateFromUserDefaultsIfNeeded()
        // loadHistory()
        loadHistoryFromUserDefaultsLegacy()
    }

    /// UserDefaultsから履歴を読み込む（レガシー、デバッグ用）
    private func loadHistoryFromUserDefaultsLegacy() {
        guard let data = UserDefaults.standard.data(forKey: legacyHistoryKey),
              let decoded = try? JSONDecoder().decode([FileHistoryEntry].self, from: data) else {
            return
        }
        history = decoded
    }

    /// SwiftDataのセットアップ
    private func setupSwiftData() {
        do {
            let schema = Schema([FileHistoryData.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
            DebugLogger.log("📦 SwiftData initialized for FileHistory", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to initialize SwiftData: \(error)", level: .minimal)
        }
    }

    /// UserDefaultsからSwiftDataへの移行（初回のみ）
    private func migrateFromUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else {
            return
        }

        guard let context = modelContext else {
            DebugLogger.log("❌ Migration skipped: ModelContext not available", level: .minimal)
            return
        }

        // 既存のUserDefaultsデータを読み込む
        guard let data = UserDefaults.standard.data(forKey: legacyHistoryKey),
              let legacyEntries = try? JSONDecoder().decode([FileHistoryEntry].self, from: data) else {
            // データがない場合も移行完了とマーク
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            DebugLogger.log("📦 No legacy history data to migrate", level: .normal)
            return
        }

        DebugLogger.log("📦 Migrating \(legacyEntries.count) history entries from UserDefaults to SwiftData", level: .minimal)

        // SwiftDataに移行
        for entry in legacyEntries {
            let historyData = FileHistoryData(fileKey: entry.fileKey, filePath: entry.filePath, fileName: entry.fileName)
            historyData.lastAccessDate = entry.lastAccessDate
            historyData.accessCount = entry.accessCount
            context.insert(historyData)
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            // 移行完了後にUserDefaultsから削除
            UserDefaults.standard.removeObject(forKey: legacyHistoryKey)
            DebugLogger.log("✅ Migration completed successfully", level: .minimal)
        } catch {
            DebugLogger.log("❌ Migration failed: \(error)", level: .minimal)
        }
    }

    /// 履歴を読み込む
    private func loadHistory() {
        guard let context = modelContext else {
            DebugLogger.log("❌ loadHistory: ModelContext not available", level: .minimal)
            return
        }

        do {
            let descriptor = FetchDescriptor<FileHistoryData>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .reverse)]
            )
            let historyData = try context.fetch(descriptor)
            history = historyData.map { $0.toEntry() }
            DebugLogger.log("📦 Loaded \(history.count) history entries from SwiftData", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to load history: \(error)", level: .minimal)
        }
    }

    /// ファイルアクセスを記録
    func recordAccess(fileKey: String, filePath: String, fileName: String) {
        DebugLogger.log("📊 recordAccess called: \(fileName)", level: .normal)

        // TODO: 一時的にUserDefaultsを使用（デバッグ用）
        // 既存のエントリを探す
        if let index = history.firstIndex(where: { $0.fileKey == fileKey }) {
            // 既存エントリを更新
            var entry = history[index]
            entry.lastAccessDate = Date()
            entry.accessCount += 1
            history.remove(at: index)
            history.insert(entry, at: 0)
        } else {
            // 新規エントリを追加
            let newEntry = FileHistoryEntry(fileKey: fileKey, filePath: filePath, fileName: fileName)
            history.insert(newEntry, at: 0)
            if history.count > maxHistoryCount {
                history.removeLast()
            }
        }
        saveHistoryToUserDefaultsLegacy()
    }

    /// UserDefaultsに履歴を保存（レガシー、デバッグ用）
    private func saveHistoryToUserDefaultsLegacy() {
        guard let encoded = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(encoded, forKey: legacyHistoryKey)
    }

    /// 最近の履歴を取得（最新n件）
    func getRecentHistory(limit: Int = 10) -> [FileHistoryEntry] {
        return Array(history.prefix(limit))
    }

    /// 指定したエントリを削除
    func removeEntry(withId id: String) {
        removeEntry(withFileKey: id)
    }

    /// 指定したfileKeyのエントリを削除
    func removeEntry(withFileKey fileKey: String) {
        // TODO: 一時的にUserDefaultsを使用（デバッグ用）
        history.removeAll(where: { $0.fileKey == fileKey })
        saveHistoryToUserDefaultsLegacy()
    }

    /// 全ての履歴をクリア
    func clearAllHistory() {
        // TODO: 一時的にUserDefaultsを使用（デバッグ用）
        history.removeAll()
        saveHistoryToUserDefaultsLegacy()
    }

    /// 全てのアクセスカウントを1にリセット
    func resetAllAccessCounts() {
        // TODO: 一時的にUserDefaultsを使用（デバッグ用）
        for i in history.indices {
            history[i].accessCount = 1
        }
        saveHistoryToUserDefaultsLegacy()
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
        // TODO: 一時的にUserDefaultsを使用（デバッグ用）
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

            saveHistoryToUserDefaultsLegacy()

            return (true, "", importData.entryCount)
        } catch {
            print("Failed to decode history: \(error)")
            return (false, error.localizedDescription, 0)
        }
    }
}
