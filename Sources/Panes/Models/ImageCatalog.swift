import Foundation
import SwiftData

/// 画像カタログのエントリ（UIモデル用）
struct ImageCatalogEntry: Codable, Identifiable {
    let id: String
    let fileKey: String
    let filePath: String      // 個別画像: 絶対パス、書庫内画像: 親（書庫/フォルダ）のパス
    let fileName: String
    let catalogType: ImageCatalogType
    let relativePath: String? // 書庫/フォルダ内画像の場合の相対パス
    var lastAccessDate: Date
    var accessCount: Int
    var memo: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var fileSize: Int64?
    var imageFormat: String?
    var tags: [String]

    /// ファイルがアクセス可能かどうか
    var isAccessible: Bool {
        switch catalogType {
        case .standalone:
            return FileManager.default.fileExists(atPath: filePath)
        case .archiveContent:
            // 親（書庫/フォルダ）が存在すればアクセス可能
            return FileManager.default.fileExists(atPath: filePath)
        }
    }

    /// 書庫/フォルダ内画像かどうか
    var isArchiveContent: Bool {
        catalogType == .archiveContent
    }

    /// 解像度の表示用文字列
    var resolutionString: String? {
        guard let w = imageWidth, let h = imageHeight else { return nil }
        return "\(w) × \(h)"
    }

    /// ファイルサイズの表示用文字列
    var fileSizeString: String? {
        guard let size = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// 親（書庫/フォルダ）の名前
    var parentName: String? {
        guard catalogType == .archiveContent else { return nil }
        return URL(fileURLWithPath: filePath).lastPathComponent
    }

    init(id: String, fileKey: String, filePath: String, fileName: String,
         catalogType: ImageCatalogType = .standalone, relativePath: String? = nil,
         lastAccessDate: Date, accessCount: Int, memo: String?,
         imageWidth: Int?, imageHeight: Int?, fileSize: Int64?,
         imageFormat: String?, tags: [String]) {
        self.id = id
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
        self.catalogType = catalogType
        self.relativePath = relativePath
        self.lastAccessDate = lastAccessDate
        self.accessCount = accessCount
        self.memo = memo
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.fileSize = fileSize
        self.imageFormat = imageFormat
        self.tags = tags
    }
}

/// 画像カタログを管理するクラス
@MainActor
@Observable
class ImageCatalogManager {
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    /// アプリ専用ディレクトリ（FileHistoryManagerと同じ場所）
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

    /// カタログの全エントリ（最終アクセス日時順）
    var catalog: [ImageCatalogEntry] = []

    /// カタログの再読み込みが必要かどうか（パフォーマンス改善用）
    @ObservationIgnored
    private var catalogNeedsReload: Bool = false

    /// 初期化エラー
    private(set) var initializationError: Error?

    /// 初期化済みかどうか
    var isInitialized: Bool {
        initializationError == nil && modelContext != nil
    }

    /// アプリ設定への参照
    var appSettings: AppSettings?

    /// 個別画像の最大カタログ件数
    private var maxStandaloneCount: Int {
        appSettings?.maxStandaloneImageCount ?? 10000
    }

    /// 書庫内画像の最大カタログ件数
    private var maxArchiveContentCount: Int {
        appSettings?.maxArchiveContentImageCount ?? 1000
    }

    /// isAccessibleのキャッシュ
    private var accessibilityCache: [String: Bool] = [:]

    func isAccessible(for entry: ImageCatalogEntry) -> Bool {
        if let cached = accessibilityCache[entry.filePath] {
            return cached
        }
        let accessible = FileManager.default.fileExists(atPath: entry.filePath)
        accessibilityCache[entry.filePath] = accessible
        return accessible
    }

    func clearAccessibilityCache() {
        accessibilityCache.removeAll()
    }

    init() {
        setupSwiftData()
        if isInitialized {
            migrateOldDataIfNeeded()
            loadCatalog()
        }
    }

    /// SwiftDataのセットアップ
    private func setupSwiftData() {
        do {
            let schema = Schema([
                FileHistoryData.self,
                ImageCatalogData.self,  // 旧モデル（マイグレーション用）
                StandaloneImageData.self,
                ArchiveContentImageData.self
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, url: Self.storeURL, allowsSave: true)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
            initializationError = nil
            DebugLogger.log("📦 SwiftData initialized for ImageCatalog at \(Self.storeURL.path)", level: .normal)
        } catch {
            initializationError = error
            DebugLogger.log("❌ ImageCatalog SwiftData initialization failed: \(error)", level: .minimal)
        }
    }

    /// 旧データのマイグレーション
    private func migrateOldDataIfNeeded() {
        guard let context = modelContext else { return }

        do {
            let oldDescriptor = FetchDescriptor<ImageCatalogData>()
            let oldData = try context.fetch(oldDescriptor)

            if oldData.isEmpty {
                DebugLogger.log("📦 No old ImageCatalogData to migrate", level: .verbose)
                return
            }

            DebugLogger.log("📦 Migrating \(oldData.count) old ImageCatalogData entries...", level: .normal)

            for old in oldData {
                if old.catalogType == .standalone {
                    // 個別画像として新テーブルに移行
                    let newData = StandaloneImageData(
                        fileKey: old.fileKey,
                        filePath: old.filePath,
                        fileName: old.fileName
                    )
                    newData.lastAccessDate = old.lastAccessDate
                    newData.accessCount = old.accessCount
                    newData.memo = old.memo
                    newData.imageWidth = old.imageWidth
                    newData.imageHeight = old.imageHeight
                    newData.fileSize = old.fileSize
                    newData.imageFormat = old.imageFormat
                    newData.tagsData = old.tagsData
                    context.insert(newData)
                } else if let relativePath = old.relativePath {
                    // 書庫内画像として新テーブルに移行
                    let newData = ArchiveContentImageData(
                        fileKey: old.fileKey,
                        parentPath: old.filePath,
                        relativePath: relativePath,
                        fileName: old.fileName
                    )
                    newData.lastAccessDate = old.lastAccessDate
                    newData.accessCount = old.accessCount
                    newData.memo = old.memo
                    newData.imageWidth = old.imageWidth
                    newData.imageHeight = old.imageHeight
                    newData.fileSize = old.fileSize
                    newData.imageFormat = old.imageFormat
                    newData.tagsData = old.tagsData
                    context.insert(newData)
                }

                // 旧データを削除
                context.delete(old)
            }

            try context.save()
            DebugLogger.log("📦 Migration completed", level: .normal)
        } catch {
            DebugLogger.log("❌ Migration failed: \(error)", level: .minimal)
        }
    }

    /// カタログを読み込む
    private func loadCatalog() {
        guard let context = modelContext else { return }

        do {
            // 個別画像を読み込み
            let standaloneDescriptor = FetchDescriptor<StandaloneImageData>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .reverse)]
            )
            let standaloneData = try context.fetch(standaloneDescriptor)

            // 書庫内画像を読み込み
            let archiveDescriptor = FetchDescriptor<ArchiveContentImageData>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .reverse)]
            )
            let archiveData = try context.fetch(archiveDescriptor)

            // 統合してソート
            var entries: [ImageCatalogEntry] = []
            entries.append(contentsOf: standaloneData.map { $0.toEntry() })
            entries.append(contentsOf: archiveData.map { $0.toEntry() })
            entries.sort { $0.lastAccessDate > $1.lastAccessDate }

            catalog = entries
            catalogNeedsReload = false
            DebugLogger.log("📦 Loaded \(standaloneData.count) standalone + \(archiveData.count) archive = \(catalog.count) total entries", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to load image catalog: \(error)", level: .minimal)
        }
    }

    /// 必要な場合のみカタログを再読み込み（履歴画面表示時に呼ぶ）
    func reloadCatalogIfNeeded() {
        if catalogNeedsReload {
            loadCatalog()
        }
    }

    // MARK: - Record Access

    /// 個別画像ファイルのアクセスを記録
    func recordStandaloneImageAccess(fileKey: String, filePath: String, fileName: String,
                                     width: Int? = nil, height: Int? = nil,
                                     fileSize: Int64? = nil, format: String? = nil) {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ recordStandaloneImageAccess skipped: not initialized", level: .normal)
            return
        }

        do {
            let searchKey = fileKey
            var descriptor = FetchDescriptor<StandaloneImageData>(
                predicate: #Predicate<StandaloneImageData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)

            if let imageData = existing.first {
                // 既存エントリを更新
                imageData.lastAccessDate = Date()
                imageData.accessCount += 1
                imageData.filePath = filePath
                imageData.fileName = fileName
                if let w = width { imageData.imageWidth = w }
                if let h = height { imageData.imageHeight = h }
                if let s = fileSize { imageData.fileSize = s }
                if let f = format { imageData.imageFormat = f }
            } else {
                // 新規エントリを作成
                let newData = StandaloneImageData(fileKey: fileKey, filePath: filePath, fileName: fileName)
                newData.imageWidth = width
                newData.imageHeight = height
                newData.fileSize = fileSize
                newData.imageFormat = format
                context.insert(newData)

                // 上限チェック（メタデータなしのみ削除）
                try enforceStandaloneLimit(context: context)
            }

            try context.save()
            // loadCatalog()は呼ばない（パフォーマンス改善）
            // 履歴画面表示時にreloadCatalogIfNeeded()で再読み込み
            catalogNeedsReload = true
        } catch {
            DebugLogger.log("❌ Failed to record standalone image: \(error)", level: .minimal)
        }
    }

    /// 書庫/フォルダ内画像のアクセスを記録
    func recordArchiveContentAccess(fileKey: String, parentPath: String, relativePath: String, fileName: String,
                                    width: Int? = nil, height: Int? = nil,
                                    fileSize: Int64? = nil, format: String? = nil) {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ recordArchiveContentAccess skipped: not initialized", level: .normal)
            return
        }

        do {
            let searchKey = fileKey
            var descriptor = FetchDescriptor<ArchiveContentImageData>(
                predicate: #Predicate<ArchiveContentImageData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)

            if let imageData = existing.first {
                // 既存エントリを更新
                imageData.lastAccessDate = Date()
                imageData.accessCount += 1
                imageData.parentPath = parentPath
                imageData.relativePath = relativePath
                imageData.fileName = fileName
                if let w = width { imageData.imageWidth = w }
                if let h = height { imageData.imageHeight = h }
                if let s = fileSize { imageData.fileSize = s }
                if let f = format { imageData.imageFormat = f }
            } else {
                // 新規エントリを作成
                let newData = ArchiveContentImageData(
                    fileKey: fileKey,
                    parentPath: parentPath,
                    relativePath: relativePath,
                    fileName: fileName
                )
                newData.imageWidth = width
                newData.imageHeight = height
                newData.fileSize = fileSize
                newData.imageFormat = format
                context.insert(newData)

                // 上限チェック（メタデータなしのみ削除）
                try enforceArchiveContentLimit(context: context)
            }

            try context.save()
            // loadCatalog()は呼ばない（パフォーマンス改善）
            // 履歴画面表示時にreloadCatalogIfNeeded()で再読み込み
            catalogNeedsReload = true
        } catch {
            DebugLogger.log("❌ Failed to record archive content image: \(error)", level: .minimal)
        }
    }

    /// 画像アクセスを記録（後方互換性のため残す）
    func recordImageAccess(fileKey: String, filePath: String, fileName: String,
                           width: Int? = nil, height: Int? = nil,
                           fileSize: Int64? = nil, format: String? = nil) {
        recordStandaloneImageAccess(fileKey: fileKey, filePath: filePath, fileName: fileName,
                                    width: width, height: height, fileSize: fileSize, format: format)
    }

    /// 個別画像の上限をチェックし、超過分を削除（メタデータなしのみ）
    private func enforceStandaloneLimit(context: ModelContext) throws {
        let countDescriptor = FetchDescriptor<StandaloneImageData>()
        let totalCount = try context.fetchCount(countDescriptor)

        if totalCount > maxStandaloneCount {
            // メタデータなしの古いエントリを削除対象にする
            let oldestDescriptor = FetchDescriptor<StandaloneImageData>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .forward)]
            )
            let oldest = try context.fetch(oldestDescriptor)
            let deleteCount = totalCount - maxStandaloneCount

            var deleted = 0
            for item in oldest {
                if deleted >= deleteCount { break }
                // メタデータがあるものは削除しない
                if !item.hasMetadata {
                    context.delete(item)
                    deleted += 1
                }
            }
            DebugLogger.log("📦 Enforced standalone limit: deleted \(deleted) entries", level: .verbose)
        }
    }

    /// 書庫内画像の上限をチェックし、超過分を削除（メタデータなしのみ）
    private func enforceArchiveContentLimit(context: ModelContext) throws {
        let countDescriptor = FetchDescriptor<ArchiveContentImageData>()
        let totalCount = try context.fetchCount(countDescriptor)

        if totalCount > maxArchiveContentCount {
            // メタデータなしの古いエントリを削除対象にする
            let oldestDescriptor = FetchDescriptor<ArchiveContentImageData>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .forward)]
            )
            let oldest = try context.fetch(oldestDescriptor)
            let deleteCount = totalCount - maxArchiveContentCount

            var deleted = 0
            for item in oldest {
                if deleted >= deleteCount { break }
                // メタデータがあるものは削除しない
                if !item.hasMetadata {
                    context.delete(item)
                    deleted += 1
                }
            }
            DebugLogger.log("📦 Enforced archive content limit: deleted \(deleted) entries", level: .verbose)
        }
    }

    // MARK: - Memo

    /// メモを更新
    func updateMemo(for id: String, memo: String?) {
        guard isInitialized, let context = modelContext else { return }

        do {
            let searchId = id

            // まず個別画像から検索
            let standaloneDescriptor = FetchDescriptor<StandaloneImageData>(
                predicate: #Predicate<StandaloneImageData> { $0.id == searchId }
            )
            let standaloneResults = try context.fetch(standaloneDescriptor)

            if let imageData = standaloneResults.first {
                imageData.memo = memo?.isEmpty == true ? nil : memo
                try context.save()
                loadCatalog()
                return
            }

            // 書庫内画像から検索
            let archiveDescriptor = FetchDescriptor<ArchiveContentImageData>(
                predicate: #Predicate<ArchiveContentImageData> { $0.id == searchId }
            )
            let archiveResults = try context.fetch(archiveDescriptor)

            if let imageData = archiveResults.first {
                imageData.memo = memo?.isEmpty == true ? nil : memo
                try context.save()
                loadCatalog()
            }
        } catch {
            DebugLogger.log("❌ Failed to update image memo: \(error)", level: .minimal)
        }
    }

    // MARK: - Delete

    /// エントリを削除
    func removeEntry(withId id: String) {
        guard isInitialized, let context = modelContext else { return }

        do {
            let searchId = id

            // 個別画像から検索・削除
            let standaloneDescriptor = FetchDescriptor<StandaloneImageData>(
                predicate: #Predicate<StandaloneImageData> { $0.id == searchId }
            )
            let standaloneToDelete = try context.fetch(standaloneDescriptor)
            for item in standaloneToDelete {
                context.delete(item)
            }

            // 書庫内画像から検索・削除
            let archiveDescriptor = FetchDescriptor<ArchiveContentImageData>(
                predicate: #Predicate<ArchiveContentImageData> { $0.id == searchId }
            )
            let archiveToDelete = try context.fetch(archiveDescriptor)
            for item in archiveToDelete {
                context.delete(item)
            }

            try context.save()
            loadCatalog()
        } catch {
            DebugLogger.log("❌ Failed to remove image catalog entry: \(error)", level: .minimal)
        }
    }

    /// 全てのカタログをクリア
    func clearAllCatalog() {
        guard isInitialized, let context = modelContext else { return }

        do {
            // 個別画像を全削除
            let standaloneDescriptor = FetchDescriptor<StandaloneImageData>()
            let allStandalone = try context.fetch(standaloneDescriptor)
            for item in allStandalone {
                context.delete(item)
            }

            // 書庫内画像を全削除
            let archiveDescriptor = FetchDescriptor<ArchiveContentImageData>()
            let allArchive = try context.fetch(archiveDescriptor)
            for item in allArchive {
                context.delete(item)
            }

            try context.save()
            catalog.removeAll()
        } catch {
            DebugLogger.log("❌ Failed to clear image catalog: \(error)", level: .minimal)
        }
    }
}
