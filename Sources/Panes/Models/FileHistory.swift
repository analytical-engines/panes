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
    var memo: String?

    /// ファイルがアクセス可能かどうか（キャッシュ済み）
    var isAccessible: Bool

    // Codable用のCodingKeys（isAccessibleは永続化しない）
    private enum CodingKeys: String, CodingKey {
        case id, fileKey, filePath, fileName, lastAccessDate, accessCount, memo
    }

    init(fileKey: String, filePath: String, fileName: String) {
        self.id = fileKey
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
        self.memo = nil
        self.isAccessible = true  // 新規アクセス時は必ずアクセス可能
    }

    init(fileKey: String, filePath: String, fileName: String, lastAccessDate: Date, accessCount: Int, memo: String? = nil, isAccessible: Bool? = nil) {
        self.id = fileKey
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = lastAccessDate
        self.accessCount = accessCount
        self.memo = memo
        // isAccessibleが指定されていなければチェックする
        self.isAccessible = isAccessible ?? FileManager.default.fileExists(atPath: filePath)
    }

    // Decodable: デコード時にisAccessibleをチェック
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.fileKey = try container.decode(String.self, forKey: .fileKey)
        self.filePath = try container.decode(String.self, forKey: .filePath)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.lastAccessDate = try container.decode(Date.self, forKey: .lastAccessDate)
        self.accessCount = try container.decode(Int.self, forKey: .accessCount)
        self.memo = try container.decodeIfPresent(String.self, forKey: .memo)
        // デコード時にアクセス可能かチェック
        self.isAccessible = FileManager.default.fileExists(atPath: self.filePath)
    }
}

/// ファイル履歴を管理するクラス
@MainActor
@Observable
class FileHistoryManager {
    private let legacyHistoryKey = "fileHistory"
    private let migrationCompletedKey = "historyMigrationToSwiftDataCompleted"
    private let pageSettingsMigrationCompletedKey = "pageSettingsMigrationToSwiftDataCompleted"

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

    /// SwiftDataが利用可能かどうか
    private var useSwiftData = false

    init() {
        setupSwiftData()
        if useSwiftData {
            migrateFromUserDefaultsIfNeeded()
            migratePageSettingsFromUserDefaultsIfNeeded()
            loadHistory()
        } else {
            // フォールバック: UserDefaultsから読み込む
            loadHistoryFromUserDefaultsLegacy()
        }
    }

    /// UserDefaultsから履歴を読み込む（フォールバック用）
    private func loadHistoryFromUserDefaultsLegacy() {
        guard let data = UserDefaults.standard.data(forKey: legacyHistoryKey),
              let decoded = try? JSONDecoder().decode([FileHistoryEntry].self, from: data) else {
            return
        }
        history = decoded
        DebugLogger.log("📦 Loaded \(history.count) history entries from UserDefaults (fallback)", level: .normal)
    }

    /// SwiftDataのセットアップ
    private func setupSwiftData() {
        do {
            let schema = Schema([FileHistoryData.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
            useSwiftData = true
            DebugLogger.log("📦 SwiftData initialized for FileHistory", level: .normal)
        } catch {
            useSwiftData = false
            DebugLogger.log("❌ Failed to initialize SwiftData: \(error), falling back to UserDefaults", level: .minimal)
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

        var migratedPageSettingsCount = 0

        // SwiftDataに移行
        for entry in legacyEntries {
            let historyData = FileHistoryData(fileKey: entry.fileKey, filePath: entry.filePath, fileName: entry.fileName)
            historyData.lastAccessDate = entry.lastAccessDate
            historyData.accessCount = entry.accessCount

            // ページ表示設定も移行
            if let pageSettingsData = UserDefaults.standard.data(forKey: "\(pageDisplaySettingsKey)-\(entry.fileKey)"),
               let pageSettings = try? JSONDecoder().decode(PageDisplaySettings.self, from: pageSettingsData) {
                historyData.setPageSettings(pageSettings)
                migratedPageSettingsCount += 1
            }

            context.insert(historyData)
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)

            // 移行完了後にUserDefaultsから削除
            UserDefaults.standard.removeObject(forKey: legacyHistoryKey)

            // ページ表示設定もUserDefaultsから削除
            for entry in legacyEntries {
                UserDefaults.standard.removeObject(forKey: "\(pageDisplaySettingsKey)-\(entry.fileKey)")
            }

            DebugLogger.log("✅ Migration completed: \(legacyEntries.count) entries, \(migratedPageSettingsCount) page settings", level: .minimal)
        } catch {
            DebugLogger.log("❌ Migration failed: \(error)", level: .minimal)
        }
    }

    /// ページ表示設定のみをUserDefaultsからSwiftDataへ移行（既存履歴がある場合用）
    private func migratePageSettingsFromUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: pageSettingsMigrationCompletedKey) else {
            return
        }

        guard let context = modelContext else {
            DebugLogger.log("❌ Page settings migration skipped: ModelContext not available", level: .minimal)
            return
        }

        DebugLogger.log("📦 Migrating page settings from UserDefaults to SwiftData", level: .minimal)

        do {
            // 既存のSwiftData履歴を取得
            let descriptor = FetchDescriptor<FileHistoryData>()
            let historyEntries = try context.fetch(descriptor)

            var migratedCount = 0
            var keysToRemove: [String] = []

            for entry in historyEntries {
                // 既にページ設定がある場合はスキップ
                guard entry.pageSettingsData == nil else { continue }

                let key = "\(pageDisplaySettingsKey)-\(entry.fileKey)"
                if let data = UserDefaults.standard.data(forKey: key),
                   let settings = try? JSONDecoder().decode(PageDisplaySettings.self, from: data) {
                    entry.setPageSettings(settings)
                    migratedCount += 1
                    keysToRemove.append(key)
                }
            }

            if migratedCount > 0 {
                try context.save()
            }

            // UserDefaultsから削除
            for key in keysToRemove {
                UserDefaults.standard.removeObject(forKey: key)
            }

            UserDefaults.standard.set(true, forKey: pageSettingsMigrationCompletedKey)
            DebugLogger.log("✅ Page settings migration completed: \(migratedCount) settings migrated", level: .minimal)
        } catch {
            DebugLogger.log("❌ Page settings migration failed: \(error)", level: .minimal)
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

        if useSwiftData {
            recordAccessWithSwiftData(fileKey: fileKey, filePath: filePath, fileName: fileName)
        } else {
            recordAccessWithUserDefaults(fileKey: fileKey, filePath: filePath, fileName: fileName)
        }
    }

    /// SwiftDataでアクセス記録
    private func recordAccessWithSwiftData(fileKey: String, filePath: String, fileName: String) {
        guard let context = modelContext else { return }

        do {
            let searchKey = fileKey
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)

            if let historyData = existing.first {
                historyData.lastAccessDate = Date()
                historyData.accessCount += 1
            } else {
                let newData = FileHistoryData(fileKey: fileKey, filePath: filePath, fileName: fileName)
                context.insert(newData)

                let countDescriptor = FetchDescriptor<FileHistoryData>()
                let totalCount = try context.fetchCount(countDescriptor)
                if totalCount > maxHistoryCount {
                    let oldestDescriptor = FetchDescriptor<FileHistoryData>(
                        sortBy: [SortDescriptor(\.lastAccessDate, order: .forward)]
                    )
                    let oldest = try context.fetch(oldestDescriptor)
                    let deleteCount = totalCount - maxHistoryCount
                    for i in 0..<deleteCount {
                        if i < oldest.count {
                            context.delete(oldest[i])
                        }
                    }
                }
            }

            try context.save()
            loadHistory()
        } catch {
            DebugLogger.log("❌ Failed to record access: \(error)", level: .minimal)
        }
    }

    /// UserDefaultsでアクセス記録
    private func recordAccessWithUserDefaults(fileKey: String, filePath: String, fileName: String) {
        if let index = history.firstIndex(where: { $0.fileKey == fileKey }) {
            var entry = history[index]
            entry.lastAccessDate = Date()
            entry.accessCount += 1
            history.remove(at: index)
            history.insert(entry, at: 0)
        } else {
            let newEntry = FileHistoryEntry(fileKey: fileKey, filePath: filePath, fileName: fileName)
            history.insert(newEntry, at: 0)
            if history.count > maxHistoryCount {
                history.removeLast()
            }
        }
        saveHistoryToUserDefaults()
    }

    /// UserDefaultsに履歴を保存
    private func saveHistoryToUserDefaults() {
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
        if useSwiftData {
            guard let context = modelContext else { return }
            do {
                let searchKey = fileKey
                var descriptor = FetchDescriptor<FileHistoryData>(
                    predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
                )
                descriptor.fetchLimit = 1
                let toDelete = try context.fetch(descriptor)
                for item in toDelete {
                    context.delete(item)
                }
                try context.save()
                loadHistory()
            } catch {
                DebugLogger.log("❌ Failed to remove entry: \(error)", level: .minimal)
            }
        } else {
            history.removeAll(where: { $0.fileKey == fileKey })
            saveHistoryToUserDefaults()
        }
    }

    /// 全ての履歴をクリア
    func clearAllHistory() {
        if useSwiftData {
            guard let context = modelContext else { return }
            do {
                let descriptor = FetchDescriptor<FileHistoryData>()
                let all = try context.fetch(descriptor)
                for item in all {
                    context.delete(item)
                }
                try context.save()
                history.removeAll()
            } catch {
                DebugLogger.log("❌ Failed to clear history: \(error)", level: .minimal)
            }
        } else {
            history.removeAll()
            saveHistoryToUserDefaults()
        }
    }

    /// 全てのアクセスカウントを1にリセット
    func resetAllAccessCounts() {
        if useSwiftData {
            guard let context = modelContext else { return }
            do {
                let descriptor = FetchDescriptor<FileHistoryData>()
                let all = try context.fetch(descriptor)
                for item in all {
                    item.accessCount = 1
                }
                try context.save()
                loadHistory()
            } catch {
                DebugLogger.log("❌ Failed to reset access counts: \(error)", level: .minimal)
            }
        } else {
            for i in history.indices {
                history[i].accessCount = 1
            }
            saveHistoryToUserDefaults()
        }
    }

    // MARK: - Memo

    /// 指定したfileKeyのメモを更新
    func updateMemo(for fileKey: String, memo: String?) {
        if useSwiftData {
            updateMemoWithSwiftData(for: fileKey, memo: memo)
        } else {
            updateMemoWithUserDefaults(for: fileKey, memo: memo)
        }
    }

    /// SwiftDataでメモを更新
    private func updateMemoWithSwiftData(for fileKey: String, memo: String?) {
        guard let context = modelContext else { return }
        do {
            let searchKey = fileKey
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            if let historyData = results.first {
                // 空文字列はnilとして保存
                historyData.memo = memo?.isEmpty == true ? nil : memo
                try context.save()
                loadHistory()
            }
        } catch {
            DebugLogger.log("❌ Failed to update memo: \(error)", level: .minimal)
        }
    }

    /// UserDefaultsでメモを更新
    private func updateMemoWithUserDefaults(for fileKey: String, memo: String?) {
        if let index = history.firstIndex(where: { $0.fileKey == fileKey }) {
            history[index].memo = memo?.isEmpty == true ? nil : memo
            saveHistoryToUserDefaults()
        }
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
    func loadPageDisplaySettings(for fileKey: String) -> PageDisplaySettings? {
        if useSwiftData {
            return loadPageDisplaySettingsFromSwiftData(for: fileKey)
        } else {
            return loadPageDisplaySettingsFromUserDefaults(for: fileKey)
        }
    }

    /// SwiftDataからページ表示設定を読み込む
    private func loadPageDisplaySettingsFromSwiftData(for fileKey: String) -> PageDisplaySettings? {
        guard let context = modelContext else { return nil }
        do {
            let searchKey = fileKey
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            return results.first?.getPageSettings()
        } catch {
            DebugLogger.log("❌ Failed to load page settings: \(error)", level: .minimal)
            return nil
        }
    }

    /// UserDefaultsからページ表示設定を読み込む（フォールバック）
    private func loadPageDisplaySettingsFromUserDefaults(for fileKey: String) -> PageDisplaySettings? {
        guard let data = UserDefaults.standard.data(forKey: "\(pageDisplaySettingsKey)-\(fileKey)") else {
            return nil
        }
        return try? JSONDecoder().decode(PageDisplaySettings.self, from: data)
    }

    /// 指定したfileKeyのページ表示設定を保存
    func savePageDisplaySettings(_ settings: PageDisplaySettings, for fileKey: String) {
        if useSwiftData {
            savePageDisplaySettingsToSwiftData(settings, for: fileKey)
        } else {
            savePageDisplaySettingsToUserDefaults(settings, for: fileKey)
        }
    }

    /// SwiftDataにページ表示設定を保存
    private func savePageDisplaySettingsToSwiftData(_ settings: PageDisplaySettings, for fileKey: String) {
        guard let context = modelContext else { return }
        do {
            let searchKey = fileKey
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)

            if let historyData = results.first {
                historyData.setPageSettings(settings)
                try context.save()
            } else {
                DebugLogger.log("⚠️ No history entry found for fileKey: \(fileKey)", level: .verbose)
            }
        } catch {
            DebugLogger.log("❌ Failed to save page settings: \(error)", level: .minimal)
        }
    }

    /// UserDefaultsにページ表示設定を保存（フォールバック）
    private func savePageDisplaySettingsToUserDefaults(_ settings: PageDisplaySettings, for fileKey: String) {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: "\(pageDisplaySettingsKey)-\(fileKey)")
        }
    }

    /// JSONデータから履歴をImport（ページ表示設定含む）
    func importHistory(from data: Data, merge: Bool) -> (success: Bool, message: String, importedCount: Int) {
        if useSwiftData {
            return importHistoryWithSwiftData(from: data, merge: merge)
        } else {
            return importHistoryWithUserDefaults(from: data, merge: merge)
        }
    }

    /// SwiftDataで履歴をImport
    private func importHistoryWithSwiftData(from data: Data, merge: Bool) -> (success: Bool, message: String, importedCount: Int) {
        guard let context = modelContext else {
            return (false, "Database not available", 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let importData = try decoder.decode(HistoryExport.self, from: data)

            if merge {
                for item in importData.entries {
                    let key = item.entry.fileKey
                    var descriptor = FetchDescriptor<FileHistoryData>(
                        predicate: #Predicate<FileHistoryData> { $0.fileKey == key }
                    )
                    descriptor.fetchLimit = 1
                    let existing = try context.fetch(descriptor)

                    if existing.isEmpty {
                        let newData = FileHistoryData(
                            fileKey: item.entry.fileKey,
                            filePath: item.entry.filePath,
                            fileName: item.entry.fileName
                        )
                        newData.lastAccessDate = item.entry.lastAccessDate
                        newData.accessCount = item.entry.accessCount
                        // ページ設定を直接設定
                        if let settings = item.pageSettings {
                            newData.setPageSettings(settings)
                        }
                        context.insert(newData)
                    }
                }
            } else {
                let allDescriptor = FetchDescriptor<FileHistoryData>()
                let all = try context.fetch(allDescriptor)
                for item in all {
                    context.delete(item)
                }

                for item in importData.entries {
                    let newData = FileHistoryData(
                        fileKey: item.entry.fileKey,
                        filePath: item.entry.filePath,
                        fileName: item.entry.fileName
                    )
                    newData.lastAccessDate = item.entry.lastAccessDate
                    newData.accessCount = item.entry.accessCount
                    // ページ設定を直接設定
                    if let settings = item.pageSettings {
                        newData.setPageSettings(settings)
                    }
                    context.insert(newData)
                }
            }

            // 上限を超えたら古いものを削除
            let countDescriptor = FetchDescriptor<FileHistoryData>()
            let totalCount = try context.fetchCount(countDescriptor)
            if totalCount > maxHistoryCount {
                let oldestDescriptor = FetchDescriptor<FileHistoryData>(
                    sortBy: [SortDescriptor(\.lastAccessDate, order: .forward)]
                )
                let oldest = try context.fetch(oldestDescriptor)
                let deleteCount = totalCount - maxHistoryCount
                for i in 0..<deleteCount {
                    if i < oldest.count {
                        context.delete(oldest[i])
                    }
                }
            }

            try context.save()
            loadHistory()

            return (true, "", importData.entryCount)
        } catch {
            DebugLogger.log("❌ Failed to import history: \(error)", level: .minimal)
            return (false, error.localizedDescription, 0)
        }
    }

    /// UserDefaultsで履歴をImport
    private func importHistoryWithUserDefaults(from data: Data, merge: Bool) -> (success: Bool, message: String, importedCount: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let importData = try decoder.decode(HistoryExport.self, from: data)

            if merge {
                var merged = history
                for item in importData.entries {
                    if !merged.contains(where: { $0.fileKey == item.entry.fileKey }) {
                        merged.append(item.entry)
                        if let settings = item.pageSettings,
                           loadPageDisplaySettings(for: item.entry.fileKey) == nil {
                            savePageDisplaySettings(settings, for: item.entry.fileKey)
                        }
                    }
                }
                merged.sort { $0.lastAccessDate > $1.lastAccessDate }
                if merged.count > maxHistoryCount {
                    merged = Array(merged.prefix(maxHistoryCount))
                }
                history = merged
            } else {
                history = importData.entries.map { $0.entry }
                for item in importData.entries {
                    if let settings = item.pageSettings {
                        savePageDisplaySettings(settings, for: item.entry.fileKey)
                    }
                }
            }

            saveHistoryToUserDefaults()

            return (true, "", importData.entryCount)
        } catch {
            print("Failed to decode history: \(error)")
            return (false, error.localizedDescription, 0)
        }
    }
}
