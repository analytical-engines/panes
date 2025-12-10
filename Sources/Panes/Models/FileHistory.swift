import Foundation
import SwiftData

/// ファイル履歴のエントリ（UIモデル用、Codable対応）
struct FileHistoryEntry: Codable, Identifiable {
    /// エントリの一意識別子（ファイル名+fileKeyのハッシュ）
    let id: String
    /// ファイル内容の識別キー（サイズ+ハッシュ）- 複数エントリで共有可能
    let fileKey: String
    /// ページ設定の参照先ID（nilなら自分がページ設定を持つ）
    let pageSettingsRef: String?
    let filePath: String
    let fileName: String
    var lastAccessDate: Date
    var accessCount: Int
    var memo: String?

    /// ファイルがアクセス可能かどうか（表示時にチェック、LazyVStackにより表示行のみ）
    var isAccessible: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    // Codable用のCodingKeys
    private enum CodingKeys: String, CodingKey {
        case id, fileKey, pageSettingsRef, filePath, fileName, lastAccessDate, accessCount, memo
    }

    init(fileKey: String, filePath: String, fileName: String) {
        self.id = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)
        self.fileKey = fileKey
        self.pageSettingsRef = nil
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = Date()
        self.accessCount = 1
        self.memo = nil
    }

    init(id: String, fileKey: String, pageSettingsRef: String?, filePath: String, fileName: String, lastAccessDate: Date, accessCount: Int, memo: String? = nil) {
        self.id = id
        self.fileKey = fileKey
        self.pageSettingsRef = pageSettingsRef
        self.filePath = filePath
        self.fileName = fileName
        self.lastAccessDate = lastAccessDate
        self.accessCount = accessCount
        self.memo = memo
    }

    // Decodable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.fileKey = try container.decode(String.self, forKey: .fileKey)
        self.pageSettingsRef = try container.decodeIfPresent(String.self, forKey: .pageSettingsRef)
        self.filePath = try container.decode(String.self, forKey: .filePath)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.lastAccessDate = try container.decode(Date.self, forKey: .lastAccessDate)
        self.accessCount = try container.decode(Int.self, forKey: .accessCount)
        self.memo = try container.decodeIfPresent(String.self, forKey: .memo)
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
}

/// ファイル同一性チェックの結果
enum FileIdentityCheckResult {
    /// 完全一致（fileKeyもfileNameも一致）
    case exactMatch
    /// ファイル名が異なる（fileKeyは一致するがfileNameが異なる）
    case differentName(existingEntry: FileHistoryEntry)
    /// 新規ファイル（履歴にない）
    case newFile
}

/// ファイル名が異なる場合のユーザー選択
enum FileIdentityChoice {
    /// 同一ファイルとして扱う（ページ設定を共有、pageSettingsRefで参照）
    case treatAsSame
    /// ページ設定を引き継ぐ（設定をコピー、独立したエントリ）
    case copySettings
    /// 別のファイルとして扱う（新規エントリ、設定なし）
    case treatAsDifferent
}

/// スキーマバージョン不一致エラー
struct SchemaVersionMismatchError: LocalizedError {
    let storedVersion: Int
    let currentVersion: Int

    var errorDescription: String? {
        // このアプリのバージョンは古いため、新しいデータベースにアクセスできません
        L("schema_version_mismatch_error", storedVersion, currentVersion)
    }
}

/// ファイル履歴を管理するクラス
@MainActor
@Observable
class FileHistoryManager {
    private let legacyHistoryKey = "fileHistory"
    private let migrationCompletedKey = "historyMigrationToSwiftDataCompleted"
    private let pageSettingsMigrationCompletedKey = "pageSettingsMigrationToSwiftDataCompleted"
    private let schemaVersionKey = "historySchemaVersion"
    private let storeLocationMigrationKey = "storeLocationMigrationCompleted"

    /// 現在のスキーマバージョン（スキーマ変更時にインクリメント）
    /// v4: ImageCatalogDataにcatalogTypeRaw, relativePathフィールドを追加
    private static let currentSchemaVersion = 4

    /// アプリ専用ディレクトリ
    private static var appSupportDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.panes.imageviewer")

        // ディレクトリが存在しなければ作成
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir
    }

    /// SwiftDataストアファイルのURL
    private static var storeURL: URL {
        appSupportDirectory.appendingPathComponent("default.store")
    }

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

    /// SwiftData初期化エラー（nilなら成功）
    private(set) var initializationError: Error?

    /// isAccessibleのキャッシュ（filePath -> isAccessible）
    private var accessibilityCache: [String: Bool] = [:]

    /// キャッシュ済みのisAccessibleを取得（未キャッシュならチェックしてキャッシュ）
    func isAccessible(for entry: FileHistoryEntry) -> Bool {
        if let cached = accessibilityCache[entry.filePath] {
            return cached
        }
        DebugLogger.log("📁 Checking file exists: \(entry.fileName)", level: .verbose)
        let accessible = FileManager.default.fileExists(atPath: entry.filePath)
        accessibilityCache[entry.filePath] = accessible
        return accessible
    }

    /// アクセシビリティキャッシュをクリア（履歴更新時など）
    func clearAccessibilityCache() {
        accessibilityCache.removeAll()
    }

    /// SwiftDataが正常に初期化されたかどうか
    var isInitialized: Bool {
        initializationError == nil && modelContext != nil
    }

    init() {
        migrateStoreLocationIfNeeded()
        setupSwiftData()
        if isInitialized {
            migrateFromUserDefaultsIfNeeded()
            migratePageSettingsFromUserDefaultsIfNeeded()
            loadHistory()
        }
        // エラー時はフォールバックせず、空の履歴のまま
        // UIでエラーを表示する
    }

    /// ストアファイルを旧ロケーションから新ロケーションに移動
    private func migrateStoreLocationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: storeLocationMigrationKey) else {
            return
        }

        let fileManager = FileManager.default
        let oldAppSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldStoreFiles = [
            oldAppSupport.appendingPathComponent("default.store"),
            oldAppSupport.appendingPathComponent("default.store-shm"),
            oldAppSupport.appendingPathComponent("default.store-wal")
        ]

        // 旧ロケーションにファイルが存在するかチェック
        let oldStoreExists = fileManager.fileExists(atPath: oldStoreFiles[0].path)

        if oldStoreExists {
            DebugLogger.log("📦 Migrating store files to app-specific directory...", level: .normal)

            // 新ディレクトリを確保
            let newDir = Self.appSupportDirectory
            let newStoreFiles = [
                newDir.appendingPathComponent("default.store"),
                newDir.appendingPathComponent("default.store-shm"),
                newDir.appendingPathComponent("default.store-wal")
            ]

            // ファイルを移動
            for (oldFile, newFile) in zip(oldStoreFiles, newStoreFiles) {
                if fileManager.fileExists(atPath: oldFile.path) {
                    do {
                        try fileManager.moveItem(at: oldFile, to: newFile)
                        DebugLogger.log("📦 Moved: \(oldFile.lastPathComponent)", level: .normal)
                    } catch {
                        DebugLogger.log("⚠️ Failed to move \(oldFile.lastPathComponent): \(error)", level: .minimal)
                    }
                }
            }
        }

        // マイグレーション完了をマーク
        UserDefaults.standard.set(true, forKey: storeLocationMigrationKey)
        DebugLogger.log("📦 Store location migration completed", level: .normal)
    }

    /// SwiftDataのセットアップ
    private func setupSwiftData() {
        // スキーマバージョンチェック（古いビルドが新しいDBにアクセスするのを防ぐ）
        let storedVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if storedVersion > Self.currentSchemaVersion {
            // 保存されているバージョンが現在より新しい = 古いアプリで新しいDBにアクセスしようとしている
            initializationError = SchemaVersionMismatchError(
                storedVersion: storedVersion,
                currentVersion: Self.currentSchemaVersion
            )
            DebugLogger.log("❌ Schema version mismatch: stored=\(storedVersion), current=\(Self.currentSchemaVersion)", level: .minimal)
            return
        }

        let needsMigration = storedVersion < Self.currentSchemaVersion && storedVersion > 0

        do {
            let schema = Schema([FileHistoryData.self, ImageCatalogData.self])
            let modelConfiguration = ModelConfiguration(schema: schema, url: Self.storeURL, allowsSave: true)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
            initializationError = nil
            DebugLogger.log("📦 Store location: \(Self.storeURL.path)", level: .verbose)

            // マイグレーション処理
            if needsMigration {
                DebugLogger.log("📦 Migrating schema from v\(storedVersion) to v\(Self.currentSchemaVersion)...", level: .normal)
                performMigration(from: storedVersion)
            }

            // 成功したらスキーマバージョンを更新
            UserDefaults.standard.set(Self.currentSchemaVersion, forKey: schemaVersionKey)
            DebugLogger.log("📦 SwiftData initialized for FileHistory (schema v\(Self.currentSchemaVersion))", level: .normal)
        } catch {
            initializationError = error
            DebugLogger.log("❌ SwiftData initialization failed: \(error)", level: .minimal)
        }
    }

    /// スキーママイグレーションを実行
    private func performMigration(from oldVersion: Int) {
        guard let context = modelContext else { return }

        // v3 -> v4: ImageCatalogDataにcatalogTypeRaw, relativePathフィールド追加
        // SwiftDataの軽量マイグレーションでデフォルト値が自動適用されるが、
        // 明示的に既存データを確認してログ出力
        if oldVersion < 4 {
            do {
                let descriptor = FetchDescriptor<ImageCatalogData>()
                let existingData = try context.fetch(descriptor)
                DebugLogger.log("📦 Migration v3→v4: Found \(existingData.count) existing ImageCatalogData entries (will be treated as standalone)", level: .normal)
                // 既存データはデフォルト値(catalogTypeRaw=0, relativePath=nil)が適用済み
            } catch {
                DebugLogger.log("⚠️ Migration check failed: \(error)", level: .minimal)
            }
        }
    }

    /// データベースをリセット（破損時の復旧用）
    /// ストアファイルを削除して再初期化する
    func resetDatabase() {
        DebugLogger.log("🔄 Resetting database...", level: .minimal)

        // 既存のコンテキストをクリア
        modelContext = nil
        modelContainer = nil

        // ストアファイルを削除（アプリ専用ディレクトリから）
        let fileManager = FileManager.default
        let appDir = Self.appSupportDirectory
        let storeFiles = [
            appDir.appendingPathComponent("default.store"),
            appDir.appendingPathComponent("default.store-shm"),
            appDir.appendingPathComponent("default.store-wal")
        ]

        for file in storeFiles {
            do {
                if fileManager.fileExists(atPath: file.path) {
                    try fileManager.removeItem(at: file)
                    DebugLogger.log("🗑️ Deleted: \(file.lastPathComponent)", level: .normal)
                }
            } catch {
                DebugLogger.log("❌ Failed to delete \(file.lastPathComponent): \(error)", level: .minimal)
            }
        }

        // スキーマバージョンをリセット（再初期化時に正しいバージョンが設定される）
        UserDefaults.standard.removeObject(forKey: schemaVersionKey)

        // 再初期化
        setupSwiftData()

        if isInitialized {
            loadHistory()
            DebugLogger.log("✅ Database reset complete", level: .minimal)
        } else {
            DebugLogger.log("❌ Database reset failed - still has errors", level: .minimal)
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

    // MARK: - File Identity Check

    /// ファイルの同一性をチェックする
    /// - Parameters:
    ///   - fileKey: ファイル内容の識別キー（サイズ-ハッシュ）
    ///   - fileName: ファイル名
    /// - Returns: 同一性チェックの結果
    func checkFileIdentity(fileKey: String, fileName: String) -> FileIdentityCheckResult {
        guard isInitialized else {
            // SwiftData未初期化時は新規ファイルとして扱う
            return .newFile
        }
        return checkFileIdentityWithSwiftData(fileKey: fileKey, fileName: fileName)
    }

    /// SwiftDataでファイル同一性をチェック
    /// 1. まずエントリID（ファイル名+fileKey）で完全一致を検索
    /// 2. 見つからなければcontentKey（サイズ-ハッシュ）で同一内容のファイルを検索
    private func checkFileIdentityWithSwiftData(fileKey: String, fileName: String) -> FileIdentityCheckResult {
        guard let context = modelContext else { return .newFile }

        do {
            // エントリIDを生成して完全一致を検索
            let entryId = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)
            let searchId = entryId
            var idDescriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
            idDescriptor.fetchLimit = 1
            let idResults = try context.fetch(idDescriptor)

            if idResults.first != nil {
                // 同じファイル名・同じ内容 → 完全一致
                return .exactMatch
            }

            // contentKey（サイズ-ハッシュ）で同一内容を検索（旧フォーマットのfileKeyにも対応）
            let contentKeyMatches = try findByContentKey(fileKey, in: context)

            if !contentKeyMatches.isEmpty {
                // 同じcontentKeyを持つエントリが見つかった
                // ファイル名が一致するものがあれば完全一致
                if contentKeyMatches.first(where: { $0.fileName == fileName }) != nil {
                    return .exactMatch
                }
                // ファイル名が異なるものがあれば確認ダイアログ
                if let existing = contentKeyMatches.first {
                    return .differentName(existingEntry: existing.toEntry())
                }
            }

            return .newFile
        } catch {
            DebugLogger.log("❌ Failed to check file identity: \(error)", level: .minimal)
            return .newFile
        }
    }

    // MARK: - Record Access

    /// ファイルアクセスを記録
    func recordAccess(fileKey: String, filePath: String, fileName: String) {
        DebugLogger.log("📊 recordAccess called: \(fileName)", level: .normal)

        guard isInitialized else {
            // SwiftData未初期化時は記録しない
            DebugLogger.log("⚠️ recordAccess skipped: SwiftData not initialized", level: .normal)
            return
        }
        recordAccessWithSwiftData(fileKey: fileKey, filePath: filePath, fileName: fileName)
    }

    /// ユーザーの選択に基づいてファイルアクセスを記録
    /// - Parameters:
    ///   - fileKey: ファイル内容の識別キー
    ///   - filePath: ファイルパス
    ///   - fileName: ファイル名
    ///   - existingEntry: 既存の履歴エントリ（ページ設定の参照元）
    ///   - choice: ユーザーの選択
    func recordAccessWithChoice(
        fileKey: String,
        filePath: String,
        fileName: String,
        existingEntry: FileHistoryEntry,
        choice: FileIdentityChoice
    ) {
        switch choice {
        case .treatAsSame:
            // 同一ファイルとして扱う：新しいエントリを作成し、pageSettingsRefで参照
            // 既存エントリがページ設定を持っていればそのIDを参照、なければ参照先を辿る
            let pageSettingsOwner = existingEntry.pageSettingsRef ?? existingEntry.id
            recordAccessWithPageSettingsRef(fileKey: fileKey, filePath: filePath, fileName: fileName, pageSettingsRef: pageSettingsOwner)

        case .copySettings:
            // ページ設定を引き継ぐ：新しいエントリを作成し、設定をコピー
            let existingSettings = loadPageDisplaySettingsWithRef(for: existingEntry)
            recordAccessAsNewEntry(fileKey: fileKey, filePath: filePath, fileName: fileName)
            if let settings = existingSettings {
                // 新しいエントリに設定を保存
                let newEntryId = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)
                savePageDisplaySettingsById(settings, for: newEntryId)
            }

        case .treatAsDifferent:
            // 別のファイルとして扱う：新しいエントリを作成（設定なし）
            recordAccessAsNewEntry(fileKey: fileKey, filePath: filePath, fileName: fileName)
        }
    }

    /// pageSettingsRefを指定してアクセスを記録
    private func recordAccessWithPageSettingsRef(fileKey: String, filePath: String, fileName: String, pageSettingsRef: String) {
        guard isInitialized else {
            DebugLogger.log("⚠️ recordAccessWithPageSettingsRef skipped: SwiftData not initialized", level: .normal)
            return
        }
        recordAccessWithPageSettingsRefSwiftData(fileKey: fileKey, filePath: filePath, fileName: fileName, pageSettingsRef: pageSettingsRef)
    }

    /// SwiftDataでpageSettingsRefを指定してアクセスを記録
    private func recordAccessWithPageSettingsRefSwiftData(fileKey: String, filePath: String, fileName: String, pageSettingsRef: String) {
        guard let context = modelContext else { return }

        do {
            let entryId = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)

            // 既存エントリを検索
            let searchId = entryId
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)

            if let existing = results.first {
                // 既存エントリを更新
                existing.lastAccessDate = Date()
                existing.accessCount += 1
                existing.filePath = filePath
                existing.pageSettingsRef = pageSettingsRef
            } else {
                // 新規エントリを作成
                let newData = FileHistoryData(fileKey: fileKey, pageSettingsRef: pageSettingsRef, filePath: filePath, fileName: fileName)
                context.insert(newData)

                // 上限チェック
                try enforceHistoryLimit(context: context)
            }

            try context.save()
            loadHistory()
        } catch {
            DebugLogger.log("❌ Failed to record access with pageSettingsRef: \(error)", level: .minimal)
        }
    }

    /// 履歴の上限をチェックし、超過分を削除
    private func enforceHistoryLimit(context: ModelContext) throws {
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

    /// 新規エントリとしてアクセスを記録（既存エントリを更新しない）
    private func recordAccessAsNewEntry(fileKey: String, filePath: String, fileName: String) {
        guard isInitialized else {
            DebugLogger.log("⚠️ recordAccessAsNewEntry skipped: SwiftData not initialized", level: .normal)
            return
        }
        recordAccessAsNewEntryWithSwiftData(fileKey: fileKey, filePath: filePath, fileName: fileName)
    }

    /// SwiftDataで新規エントリとして記録
    private func recordAccessAsNewEntryWithSwiftData(fileKey: String, filePath: String, fileName: String) {
        guard let context = modelContext else { return }

        do {
            let newData = FileHistoryData(fileKey: fileKey, filePath: filePath, fileName: fileName)
            context.insert(newData)

            // 上限チェック
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
        } catch {
            DebugLogger.log("❌ Failed to record access as new entry: \(error)", level: .minimal)
        }
    }

    /// SwiftDataでアクセス記録
    private func recordAccessWithSwiftData(fileKey: String, filePath: String, fileName: String) {
        guard let context = modelContext else { return }

        do {
            // エントリIDで検索（ファイル名+fileKeyのハッシュ）
            let entryId = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)
            let searchId = entryId
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
            descriptor.fetchLimit = 1
            var existing = try context.fetch(descriptor)

            // ID検索で見つからない場合、contentKey + fileNameで検索（旧フォーマット対応）
            if existing.isEmpty {
                let contentKeyMatches = try findByContentKey(fileKey, in: context)
                if let match = contentKeyMatches.first(where: { $0.fileName == fileName }) {
                    existing = [match]
                }
            }

            if let historyData = existing.first {
                // 既存エントリを更新
                historyData.lastAccessDate = Date()
                historyData.accessCount += 1
                historyData.filePath = filePath
                // fileKeyを新フォーマットに更新
                historyData.fileKey = fileKey
            } else {
                // 新規エントリを作成
                let newData = FileHistoryData(fileKey: fileKey, filePath: filePath, fileName: fileName)
                context.insert(newData)

                try enforceHistoryLimit(context: context)
            }

            try context.save()
            loadHistory()
        } catch {
            DebugLogger.log("❌ Failed to record access: \(error)", level: .minimal)
        }
    }

    /// contentKey（サイズ-ハッシュ）で履歴を検索（旧フォーマット対応）
    private func findByContentKey(_ fileKey: String, in context: ModelContext) throws -> [FileHistoryData] {
        let contentKey = extractContentKey(from: fileKey)

        // 全件取得してフィルタリング（旧フォーマット対応のため）
        let descriptor = FetchDescriptor<FileHistoryData>()
        let allEntries = try context.fetch(descriptor)

        return allEntries.filter { entry in
            extractContentKey(from: entry.fileKey) == contentKey
        }
    }

    /// fileKeyからサイズ-ハッシュ部分を抽出（旧フォーマット対応）
    private func extractContentKey(from fileKey: String) -> String {
        let components = fileKey.split(separator: "-")
        guard components.count >= 2 else { return fileKey }

        let lastComponent = String(components.last!)
        guard lastComponent.count == 16,
              lastComponent.allSatisfy({ $0.isHexDigit }) else {
            return fileKey
        }

        let secondLast = String(components[components.count - 2])
        guard secondLast.allSatisfy({ $0.isNumber }) else {
            return fileKey
        }

        return "\(secondLast)-\(lastComponent)"
    }

    /// 最近の履歴を取得（最新n件）
    func getRecentHistory(limit: Int = 10) -> [FileHistoryEntry] {
        return Array(history.prefix(limit))
    }

    /// ファイル名とfileKeyからエントリを検索（contentKey互換性あり）
    /// - Parameters:
    ///   - fileName: ファイル名
    ///   - fileKey: ファイルキー（新/旧フォーマット両対応）
    /// - Returns: 見つかったエントリ、なければnil
    func findEntry(fileName: String, fileKey: String) -> FileHistoryEntry? {
        guard isInitialized, let context = modelContext else {
            return nil
        }
        do {
            // まずIDで検索
            let entryId = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)
            let searchId = entryId
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
            descriptor.fetchLimit = 1
            let idResults = try context.fetch(descriptor)
            if let found = idResults.first {
                return found.toEntry()
            }

            // contentKey + fileNameで検索
            let contentKeyMatches = try findByContentKey(fileKey, in: context)
            if let match = contentKeyMatches.first(where: { $0.fileName == fileName }) {
                return match.toEntry()
            }
            return nil
        } catch {
            return nil
        }
    }

    /// 指定したエントリを削除
    func removeEntry(withId id: String) {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ removeEntry(withId:) skipped: SwiftData not initialized", level: .normal)
            return
        }
        do {
            let searchId = id
            let descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
            let toDelete = try context.fetch(descriptor)
            for item in toDelete {
                context.delete(item)
            }
            try context.save()
            loadHistory()
        } catch {
            DebugLogger.log("❌ Failed to remove entry by id: \(error)", level: .minimal)
        }
    }

    /// 指定したfileKeyのエントリを削除
    func removeEntry(withFileKey fileKey: String) {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ removeEntry(withFileKey:) skipped: SwiftData not initialized", level: .normal)
            return
        }
        do {
            // まず完全一致で検索
            let searchKey = fileKey
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            var toDelete = try context.fetch(descriptor)

            // 見つからない場合、contentKey（サイズ-ハッシュ）で旧フォーマットを検索
            if toDelete.isEmpty {
                toDelete = try findByContentKey(fileKey, in: context)
            }

            for item in toDelete {
                context.delete(item)
            }
            try context.save()
            loadHistory()
        } catch {
            DebugLogger.log("❌ Failed to remove entry: \(error)", level: .minimal)
        }
    }

    /// 全ての履歴をクリア
    func clearAllHistory() {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ clearAllHistory skipped: SwiftData not initialized", level: .normal)
            return
        }
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
    }

    /// 全てのアクセスカウントを1にリセット
    func resetAllAccessCounts() {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ resetAllAccessCounts skipped: SwiftData not initialized", level: .normal)
            return
        }
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
    }

    // MARK: - Memo

    /// 指定したエントリIDのメモを更新
    func updateMemo(for entryId: String, memo: String?) {
        guard isInitialized else {
            DebugLogger.log("⚠️ updateMemo skipped: SwiftData not initialized", level: .normal)
            return
        }
        updateMemoWithSwiftData(for: entryId, memo: memo)
    }

    /// SwiftDataでメモを更新
    private func updateMemoWithSwiftData(for entryId: String, memo: String?) {
        guard let context = modelContext else { return }
        do {
            let searchId = entryId
            let descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
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

    // MARK: - Export/Import

    private let pageDisplaySettingsKey = "pageDisplaySettings"

    /// 履歴エントリとページ表示設定をセットにした構造
    struct HistoryEntryWithSettings: Codable {
        let entry: FileHistoryEntry
        let pageSettings: PageDisplaySettings?
    }

    /// Export用のデータ構造
    /// - version 1: 旧形式（id = fileKey, pageSettingsRefなし）
    /// - version 2: 新形式（id = hash(fileName+fileKey), pageSettingsRefあり）
    struct HistoryExport: Codable {
        let version: Int?  // nilの場合はversion 1として扱う
        let exportDate: Date
        let entryCount: Int
        let entries: [HistoryEntryWithSettings]
    }

    /// 現在のExportフォーマットバージョン
    private static let currentExportVersion = 2

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
            version: FileHistoryManager.currentExportVersion,
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
        guard isInitialized else {
            return nil
        }
        return loadPageDisplaySettingsFromSwiftData(for: fileKey)
    }

    /// ファイル名とfileKeyを指定してページ表示設定を読み込む
    /// エントリIDを計算し、pageSettingsRefがあれば辿って設定を取得
    func loadPageDisplaySettings(forFileName fileName: String, fileKey: String) -> PageDisplaySettings? {
        let entryId = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)
        return loadPageDisplaySettingsById(entryId)
    }

    /// SwiftDataからページ表示設定を読み込む
    /// pageSettingsRefがあれば辿って参照先から設定を取得
    private func loadPageDisplaySettingsFromSwiftData(for fileKey: String) -> PageDisplaySettings? {
        guard let context = modelContext else { return nil }
        do {
            // まず完全一致で検索
            let searchKey = fileKey
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            var results = try context.fetch(descriptor)

            // 見つからない場合、contentKey（サイズ-ハッシュ）で旧フォーマットを検索
            if results.isEmpty {
                results = try findByContentKey(fileKey, in: context)
            }

            guard let entry = results.first else { return nil }

            // pageSettingsRefがあれば参照先から設定を取得
            if let refId = entry.pageSettingsRef {
                return loadPageDisplaySettingsById(refId)
            }

            return entry.getPageSettings()
        } catch {
            DebugLogger.log("❌ Failed to load page settings: \(error)", level: .minimal)
            return nil
        }
    }

    /// エントリIDを指定してページ設定を読み込む
    func loadPageDisplaySettingsById(_ entryId: String) -> PageDisplaySettings? {
        guard isInitialized else {
            return nil
        }
        return loadPageDisplaySettingsByIdFromSwiftData(entryId)
    }

    /// SwiftDataからエントリIDでページ設定を読み込む
    private func loadPageDisplaySettingsByIdFromSwiftData(_ entryId: String) -> PageDisplaySettings? {
        guard let context = modelContext else { return nil }
        do {
            let searchId = entryId
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)

            guard let entry = results.first else { return nil }

            // さらにpageSettingsRefを辿る（循環参照防止のため1回のみ）
            if let refId = entry.pageSettingsRef, refId != entryId {
                let refSearchId = refId
                var refDescriptor = FetchDescriptor<FileHistoryData>(
                    predicate: #Predicate<FileHistoryData> { $0.id == refSearchId }
                )
                refDescriptor.fetchLimit = 1
                let refResults = try context.fetch(refDescriptor)
                if let refEntry = refResults.first {
                    return refEntry.getPageSettings()
                }
            }

            return entry.getPageSettings()
        } catch {
            DebugLogger.log("❌ Failed to load page settings by id: \(error)", level: .minimal)
            return nil
        }
    }

    /// pageSettingsRefを辿ってページ設定を読み込む
    func loadPageDisplaySettingsWithRef(for entry: FileHistoryEntry) -> PageDisplaySettings? {
        if let refId = entry.pageSettingsRef {
            return loadPageDisplaySettingsById(refId)
        }
        // 自身の設定を読み込む
        return loadPageDisplaySettingsById(entry.id)
    }

    /// 指定したfileKeyのページ表示設定を保存
    func savePageDisplaySettings(_ settings: PageDisplaySettings, for fileKey: String) {
        guard isInitialized else {
            DebugLogger.log("⚠️ savePageDisplaySettings skipped: SwiftData not initialized", level: .normal)
            return
        }
        savePageDisplaySettingsToSwiftData(settings, for: fileKey)
    }

    /// ファイル名とfileKeyを指定してページ表示設定を保存
    /// エントリIDを計算し、pageSettingsRefがあれば参照先に保存
    func savePageDisplaySettings(_ settings: PageDisplaySettings, forFileName fileName: String, fileKey: String) {
        let entryId = FileHistoryEntry.generateId(fileName: fileName, fileKey: fileKey)
        savePageDisplaySettingsById(settings, for: entryId)
    }

    /// SwiftDataにページ表示設定を保存
    private func savePageDisplaySettingsToSwiftData(_ settings: PageDisplaySettings, for fileKey: String) {
        guard let context = modelContext else { return }
        do {
            // まず完全一致で検索
            let searchKey = fileKey
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            var results = try context.fetch(descriptor)

            // 見つからない場合、contentKey（サイズ-ハッシュ）で旧フォーマットを検索
            if results.isEmpty {
                results = try findByContentKey(fileKey, in: context)
            }

            if let historyData = results.first {
                historyData.setPageSettings(settings)
                // fileKeyも新フォーマットに更新
                historyData.fileKey = fileKey
                try context.save()
            } else {
                DebugLogger.log("⚠️ No history entry found for fileKey: \(fileKey)", level: .verbose)
            }
        } catch {
            DebugLogger.log("❌ Failed to save page settings: \(error)", level: .minimal)
        }
    }

    /// エントリIDを指定してページ設定を保存
    func savePageDisplaySettingsById(_ settings: PageDisplaySettings, for entryId: String) {
        guard isInitialized else {
            DebugLogger.log("⚠️ savePageDisplaySettingsById skipped: SwiftData not initialized", level: .normal)
            return
        }
        savePageDisplaySettingsByIdToSwiftData(settings, for: entryId)
    }

    /// SwiftDataにエントリIDでページ設定を保存
    private func savePageDisplaySettingsByIdToSwiftData(_ settings: PageDisplaySettings, for entryId: String) {
        guard let context = modelContext else { return }
        do {
            let searchId = entryId
            var descriptor = FetchDescriptor<FileHistoryData>(
                predicate: #Predicate<FileHistoryData> { $0.id == searchId }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)

            if let historyData = results.first {
                // pageSettingsRefがあれば参照先に保存
                if let refId = historyData.pageSettingsRef {
                    let refSearchId = refId
                    var refDescriptor = FetchDescriptor<FileHistoryData>(
                        predicate: #Predicate<FileHistoryData> { $0.id == refSearchId }
                    )
                    refDescriptor.fetchLimit = 1
                    let refResults = try context.fetch(refDescriptor)
                    if let refEntry = refResults.first {
                        refEntry.setPageSettings(settings)
                        try context.save()
                        return
                    }
                }
                // 自身に保存
                historyData.setPageSettings(settings)
                try context.save()
            } else {
                DebugLogger.log("⚠️ No history entry found for id: \(entryId)", level: .verbose)
            }
        } catch {
            DebugLogger.log("❌ Failed to save page settings by id: \(error)", level: .minimal)
        }
    }

    /// JSONデータから履歴をImport（ページ表示設定含む）
    func importHistory(from data: Data, merge: Bool) -> (success: Bool, message: String, importedCount: Int) {
        guard isInitialized else {
            return (false, "Database not initialized", 0)
        }
        return importHistoryWithSwiftData(from: data, merge: merge)
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
            let importVersion = importData.version ?? 1
            DebugLogger.log("📥 Importing history: version \(importVersion), \(importData.entryCount) entries", level: .normal)

            if merge {
                for item in importData.entries {
                    // 新しいid形式で検索
                    let entryId = FileHistoryEntry.generateId(fileName: item.entry.fileName, fileKey: item.entry.fileKey)
                    let searchId = entryId
                    var descriptor = FetchDescriptor<FileHistoryData>(
                        predicate: #Predicate<FileHistoryData> { $0.id == searchId }
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
                        newData.memo = item.entry.memo
                        // ページ設定を直接設定
                        if let settings = item.pageSettings {
                            newData.setPageSettings(settings)
                        }
                        context.insert(newData)
                    } else if let existingData = existing.first {
                        // 既存エントリのメモを更新（インポートデータにメモがある場合）
                        if let importMemo = item.entry.memo, !importMemo.isEmpty {
                            existingData.memo = importMemo
                        }
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
                    newData.memo = item.entry.memo
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
}
