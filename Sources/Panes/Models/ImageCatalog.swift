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
        case .individual:
            return FileManager.default.fileExists(atPath: filePath)
        case .archived:
            // 親（書庫/フォルダ）が存在すればアクセス可能
            return FileManager.default.fileExists(atPath: filePath)
        }
    }

    /// 書庫/フォルダ内画像かどうか
    var isArchiveContent: Bool {
        catalogType == .archived
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
        guard catalogType == .archived else { return nil }
        return URL(fileURLWithPath: filePath).lastPathComponent
    }

    init(id: String, fileKey: String, filePath: String, fileName: String,
         catalogType: ImageCatalogType = .individual, relativePath: String? = nil,
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

    /// 現在のワークスペースID（""はデフォルト）
    var workspaceId: String = ""

    /// カタログの全エントリ（最終アクセス日時順）
    /// @ObservationIgnored: 配列の変更で全ウィンドウが再評価されるのを防ぐ
    /// 初期画面はcatalogVersionを監視して再描画する
    @ObservationIgnored
    var catalog: [ImageCatalogEntry] = []

    /// カタログ更新通知用（初期画面がこれを監視する）
    private(set) var catalogVersion: Int = 0

    /// 個別画像の件数
    var standaloneCount: Int {
        catalog.filter { $0.catalogType == .individual }.count
    }

    /// 書庫内画像の件数
    var archiveContentCount: Int {
        catalog.filter { $0.catalogType == .archived }.count
    }

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

    /// バックグラウンドチェックが実行中かどうか
    private(set) var isBackgroundCheckRunning: Bool = false

    /// 起動時のバックグラウンドチェックを実行済みかどうか
    private var hasPerformedInitialCheck: Bool = false

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

    /// 起動時のバックグラウンドチェックを開始（一度だけ実行）
    func startInitialAccessibilityCheck() {
        guard !hasPerformedInitialCheck else { return }
        hasPerformedInitialCheck = true
        startBackgroundAccessibilityCheck()
    }

    /// 全カタログのアクセス可否をバックグラウンドで再チェック開始
    func startBackgroundAccessibilityCheck() {
        // 全パスのコピーを取得（並行アクセス問題を回避）
        let pathsToCheck = catalog.map { $0.filePath }
        DebugLogger.log("🔄 Starting background catalog accessibility check: \(pathsToCheck.count) entries", level: .normal)

        guard !pathsToCheck.isEmpty else { return }
        isBackgroundCheckRunning = true

        Task.detached(priority: .background) { [weak self] in
            await self?.performBackgroundCheck(paths: pathsToCheck)
        }
    }

    /// バックグラウンドでアクセス可否をチェック
    private func performBackgroundCheck(paths: [String]) async {
        var changedCount = 0

        for path in paths {
            let newValue = FileManager.default.fileExists(atPath: path)

            await MainActor.run {
                let oldValue = accessibilityCache[path]
                accessibilityCache[path] = newValue

                if oldValue != newValue {
                    changedCount += 1
                    DebugLogger.log("📁 Catalog accessibility changed: \(path) -> \(newValue)", level: .verbose)
                }
            }

            // 少し間隔を空けて負荷を分散
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        await MainActor.run {
            isBackgroundCheckRunning = false
            DebugLogger.log("🔄 Background catalog check completed: \(changedCount) changes, catalogVersion=\(catalogVersion)", level: .normal)
            // 変更がなくてもUIを更新する（起動時のキャッシュ反映のため）
            notifyCatalogUpdate()
            DebugLogger.log("🔄 After notifyCatalogUpdate: catalogVersion=\(catalogVersion)", level: .normal)
        }
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
                ArchiveContentImageData.self,
                WorkspaceData.self,      // 将来のworkspace機能用
                SessionGroupData.self    // セッショングループ
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
                if old.catalogType == .individual {
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
    func loadCatalog() {
        guard let context = modelContext else { return }

        do {
            let wid = workspaceId

            // 個別画像を読み込み
            let standaloneDescriptor = FetchDescriptor<StandaloneImageData>(
                predicate: #Predicate<StandaloneImageData> { $0.workspaceId == wid },
                sortBy: [SortDescriptor(\.lastAccessDate, order: .reverse)]
            )
            let standaloneData = try context.fetch(standaloneDescriptor)

            // 書庫内画像を読み込み
            let archiveDescriptor = FetchDescriptor<ArchiveContentImageData>(
                predicate: #Predicate<ArchiveContentImageData> { $0.workspaceId == wid },
                sortBy: [SortDescriptor(\.lastAccessDate, order: .reverse)]
            )
            let archiveData = try context.fetch(archiveDescriptor)

            // 統合してソート
            var entries: [ImageCatalogEntry] = []
            entries.append(contentsOf: standaloneData.map { $0.toEntry() })
            entries.append(contentsOf: archiveData.map { $0.toEntry() })
            entries.sort { $0.lastAccessDate > $1.lastAccessDate }

            catalog = entries
            DebugLogger.log("📦 Loaded \(standaloneData.count) standalone + \(archiveData.count) archive = \(catalog.count) total entries", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to load image catalog: \(error)", level: .minimal)
        }
    }

    /// 初期画面の再描画をトリガーする（フォーカス復帰時に呼ぶ）
    /// 配列は updateCatalogArrayDirectly で常に最新なのでDBリロード不要
    func notifyCatalogUpdate() {
        catalogVersion += 1
    }

    /// メモリ上のカタログ配列を直接更新する（DBリロード不要）
    private func updateCatalogArrayDirectly(_ entry: ImageCatalogEntry) {
        // 既存エントリを探して削除
        catalog.removeAll { $0.id == entry.id }

        // 新しいエントリを先頭に追加
        catalog.insert(entry, at: 0)

        // 上限を超えた分を削除（種類ごとに）
        let maxCount = entry.catalogType == .individual ? maxStandaloneCount : maxArchiveContentCount
        let sameTypeEntries = catalog.filter { $0.catalogType == entry.catalogType }
        if sameTypeEntries.count > maxCount {
            // メタデータなしの古いエントリを削除
            let toRemove = sameTypeEntries
                .filter { $0.memo == nil && $0.tags.isEmpty }
                .suffix(sameTypeEntries.count - maxCount)
            for removeEntry in toRemove {
                catalog.removeAll { $0.id == removeEntry.id }
            }
        }

        // アクセシビリティキャッシュを更新
        accessibilityCache[entry.filePath] = true
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
            let wid = workspaceId
            var descriptor = FetchDescriptor<StandaloneImageData>(
                predicate: #Predicate<StandaloneImageData> { $0.fileKey == searchKey && $0.workspaceId == wid }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)

            let now = Date()
            var newAccessCount = 1
            var memo: String? = nil
            var tags: [String] = []
            var imgWidth = width
            var imgHeight = height
            var imgFileSize = fileSize
            var imgFormat = format

            if let imageData = existing.first {
                // 既存エントリを更新
                imageData.lastAccessDate = now
                imageData.accessCount += 1
                imageData.filePath = filePath
                imageData.fileName = fileName
                if let w = width { imageData.imageWidth = w }
                if let h = height { imageData.imageHeight = h }
                if let s = fileSize { imageData.fileSize = s }
                if let f = format { imageData.imageFormat = f }
                newAccessCount = imageData.accessCount
                memo = imageData.memo
                tags = imageData.getTags()
                imgWidth = imageData.imageWidth
                imgHeight = imageData.imageHeight
                imgFileSize = imageData.fileSize
                imgFormat = imageData.imageFormat
            } else {
                // 新規エントリを作成
                let newData = StandaloneImageData(fileKey: fileKey, filePath: filePath, fileName: fileName, workspaceId: workspaceId)
                newData.imageWidth = width
                newData.imageHeight = height
                newData.fileSize = fileSize
                newData.imageFormat = format
                context.insert(newData)

                // 上限チェック（メタデータなしのみ削除）
                try enforceStandaloneLimit(context: context)
            }

            try context.save()

            // メモリ上の配列を直接更新（リロード不要）
            let entry = ImageCatalogEntry(
                id: fileKey,
                fileKey: fileKey,
                filePath: filePath,
                fileName: fileName,
                catalogType: .individual,
                relativePath: nil,
                lastAccessDate: now,
                accessCount: newAccessCount,
                memo: memo,
                imageWidth: imgWidth,
                imageHeight: imgHeight,
                fileSize: imgFileSize,
                imageFormat: imgFormat,
                tags: tags
            )
            updateCatalogArrayDirectly(entry)
            notifyCatalogUpdate()
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
            let wid = workspaceId
            var descriptor = FetchDescriptor<ArchiveContentImageData>(
                predicate: #Predicate<ArchiveContentImageData> { $0.fileKey == searchKey && $0.workspaceId == wid }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)

            let now = Date()
            var newAccessCount = 1
            var memo: String? = nil
            var tags: [String] = []
            var imgWidth = width
            var imgHeight = height
            var imgFileSize = fileSize
            var imgFormat = format

            if let imageData = existing.first {
                // 既存エントリを更新
                imageData.lastAccessDate = now
                imageData.accessCount += 1
                imageData.parentPath = parentPath
                imageData.relativePath = relativePath
                imageData.fileName = fileName
                if let w = width { imageData.imageWidth = w }
                if let h = height { imageData.imageHeight = h }
                if let s = fileSize { imageData.fileSize = s }
                if let f = format { imageData.imageFormat = f }
                newAccessCount = imageData.accessCount
                memo = imageData.memo
                tags = imageData.getTags()
                imgWidth = imageData.imageWidth
                imgHeight = imageData.imageHeight
                imgFileSize = imageData.fileSize
                imgFormat = imageData.imageFormat
            } else {
                // 新規エントリを作成
                let newData = ArchiveContentImageData(
                    fileKey: fileKey,
                    parentPath: parentPath,
                    relativePath: relativePath,
                    fileName: fileName,
                    workspaceId: workspaceId
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

            // メモリ上の配列を直接更新（リロード不要）
            let entry = ImageCatalogEntry(
                id: fileKey,
                fileKey: fileKey,
                filePath: parentPath,
                fileName: fileName,
                catalogType: .archived,
                relativePath: relativePath,
                lastAccessDate: now,
                accessCount: newAccessCount,
                memo: memo,
                imageWidth: imgWidth,
                imageHeight: imgHeight,
                fileSize: imgFileSize,
                imageFormat: imgFormat,
                tags: tags
            )
            updateCatalogArrayDirectly(entry)
            notifyCatalogUpdate()
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
            notifyCatalogUpdate()
        } catch {
            DebugLogger.log("❌ Failed to remove image catalog entry: \(error)", level: .minimal)
        }
    }

    /// 全てのカタログをクリア（現在のワークスペースのみ）
    func clearAllCatalog() {
        guard isInitialized, let context = modelContext else { return }

        do {
            let wid = workspaceId

            // 個別画像を全削除
            let standaloneDescriptor = FetchDescriptor<StandaloneImageData>(
                predicate: #Predicate<StandaloneImageData> { $0.workspaceId == wid }
            )
            let allStandalone = try context.fetch(standaloneDescriptor)
            for item in allStandalone {
                context.delete(item)
            }

            // 書庫内画像を全削除
            let archiveDescriptor = FetchDescriptor<ArchiveContentImageData>(
                predicate: #Predicate<ArchiveContentImageData> { $0.workspaceId == wid }
            )
            let allArchive = try context.fetch(archiveDescriptor)
            for item in allArchive {
                context.delete(item)
            }

            try context.save()
            catalog.removeAll()
            notifyCatalogUpdate()
        } catch {
            DebugLogger.log("❌ Failed to clear image catalog: \(error)", level: .minimal)
        }
    }

    /// 個別画像カタログのみクリア（現在のワークスペースのみ）
    func clearStandaloneCatalog() {
        guard isInitialized, let context = modelContext else { return }

        do {
            let wid = workspaceId
            let descriptor = FetchDescriptor<StandaloneImageData>(
                predicate: #Predicate<StandaloneImageData> { $0.workspaceId == wid }
            )
            let all = try context.fetch(descriptor)
            for item in all {
                context.delete(item)
            }

            try context.save()
            catalog.removeAll { $0.catalogType == .individual }
            notifyCatalogUpdate()
        } catch {
            DebugLogger.log("❌ Failed to clear standalone catalog: \(error)", level: .minimal)
        }
    }

    /// 書庫内画像カタログのみクリア（現在のワークスペースのみ）
    func clearArchiveContentCatalog() {
        guard isInitialized, let context = modelContext else { return }

        do {
            let wid = workspaceId
            let descriptor = FetchDescriptor<ArchiveContentImageData>(
                predicate: #Predicate<ArchiveContentImageData> { $0.workspaceId == wid }
            )
            let all = try context.fetch(descriptor)
            for item in all {
                context.delete(item)
            }

            try context.save()
            catalog.removeAll { $0.catalogType == .archived }
            notifyCatalogUpdate()
        } catch {
            DebugLogger.log("❌ Failed to clear archive content catalog: \(error)", level: .minimal)
        }
    }

    // MARK: - Import

    /// 個別画像をImport
    /// - Parameters:
    ///   - images: インポートする画像エントリ
    ///   - merge: trueならマージ、falseなら置換
    /// - Returns: インポートされた件数
    func importStandaloneImages(_ images: [ImageCatalogEntry], merge: Bool) -> Int {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ importStandaloneImages skipped: not initialized", level: .normal)
            return 0
        }

        // 個別画像のみをフィルタ（念のため）
        let standaloneImages = images.filter { $0.catalogType == .individual }
        guard !standaloneImages.isEmpty else { return 0 }

        var importedCount = 0

        do {
            if !merge {
                // Replace mode: delete existing standalone images in current workspace
                let wid = workspaceId
                let descriptor = FetchDescriptor<StandaloneImageData>(
                    predicate: #Predicate<StandaloneImageData> { $0.workspaceId == wid }
                )
                let all = try context.fetch(descriptor)
                for item in all {
                    context.delete(item)
                }
                catalog.removeAll { $0.catalogType == .individual }
            }

            for entry in standaloneImages {
                let searchKey = entry.fileKey
                let wid = workspaceId
                var descriptor = FetchDescriptor<StandaloneImageData>(
                    predicate: #Predicate<StandaloneImageData> { $0.fileKey == searchKey && $0.workspaceId == wid }
                )
                descriptor.fetchLimit = 1
                let existing = try context.fetch(descriptor)

                if existing.isEmpty {
                    // 新規追加
                    let newData = StandaloneImageData(
                        fileKey: entry.fileKey,
                        filePath: entry.filePath,
                        fileName: entry.fileName,
                        workspaceId: workspaceId
                    )
                    newData.lastAccessDate = entry.lastAccessDate
                    newData.accessCount = entry.accessCount
                    newData.memo = entry.memo
                    newData.imageWidth = entry.imageWidth
                    newData.imageHeight = entry.imageHeight
                    newData.fileSize = entry.fileSize
                    newData.imageFormat = entry.imageFormat
                    newData.setTags(entry.tags)
                    context.insert(newData)
                    importedCount += 1

                    // メモリ上の配列にも追加
                    catalog.insert(entry, at: 0)
                } else if let existingData = existing.first {
                    // 既存エントリのメモとタグを更新（インポートデータにある場合）
                    if let importMemo = entry.memo, !importMemo.isEmpty {
                        existingData.memo = importMemo
                    }
                    if !entry.tags.isEmpty {
                        existingData.setTags(entry.tags)
                    }
                }
            }

            // 上限チェック
            try enforceStandaloneLimit(context: context)

            try context.save()
            loadCatalog()

            DebugLogger.log("📥 Imported \(importedCount) standalone images", level: .normal)
            return importedCount
        } catch {
            DebugLogger.log("❌ Failed to import standalone images: \(error)", level: .minimal)
            return 0
        }
    }
}
