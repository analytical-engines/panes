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

    /// 初期化エラー
    private(set) var initializationError: Error?

    /// 初期化済みかどうか
    var isInitialized: Bool {
        initializationError == nil && modelContext != nil
    }

    /// アプリ設定への参照
    var appSettings: AppSettings?

    /// 最大カタログ件数（将来的に設定可能に）
    private var maxCatalogCount: Int {
        appSettings?.maxHistoryCount ?? 500  // デフォルトは500件
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
            loadCatalog()
        }
    }

    /// SwiftDataのセットアップ（FileHistoryDataと同じコンテナを使用）
    private func setupSwiftData() {
        do {
            let schema = Schema([FileHistoryData.self, ImageCatalogData.self])
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

    /// カタログを読み込む
    private func loadCatalog() {
        guard let context = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<ImageCatalogData>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .reverse)]
            )
            let catalogData = try context.fetch(descriptor)
            catalog = catalogData.map { $0.toEntry() }
            DebugLogger.log("📦 Loaded \(catalog.count) image catalog entries", level: .normal)
            if let first = catalog.first {
                DebugLogger.log("📦 First entry: \(first.fileName), date: \(first.lastAccessDate)", level: .verbose)
            }
        } catch {
            DebugLogger.log("❌ Failed to load image catalog: \(error)", level: .minimal)
        }
    }

    // MARK: - Record Access

    /// 個別画像ファイルのアクセスを記録
    func recordStandaloneImageAccess(fileKey: String, filePath: String, fileName: String,
                                     width: Int? = nil, height: Int? = nil,
                                     fileSize: Int64? = nil, format: String? = nil) {
        recordImageAccessInternal(
            fileKey: fileKey,
            filePath: filePath,
            fileName: fileName,
            catalogType: .standalone,
            relativePath: nil,
            width: width, height: height,
            fileSize: fileSize, format: format
        )
    }

    /// 書庫/フォルダ内画像のアクセスを記録
    func recordArchiveContentAccess(fileKey: String, parentPath: String, relativePath: String, fileName: String,
                                    width: Int? = nil, height: Int? = nil,
                                    fileSize: Int64? = nil, format: String? = nil) {
        recordImageAccessInternal(
            fileKey: fileKey,
            filePath: parentPath,
            fileName: fileName,
            catalogType: .archiveContent,
            relativePath: relativePath,
            width: width, height: height,
            fileSize: fileSize, format: format
        )
    }

    /// 画像アクセスを記録（内部実装）
    private func recordImageAccessInternal(fileKey: String, filePath: String, fileName: String,
                                           catalogType: ImageCatalogType, relativePath: String?,
                                           width: Int? = nil, height: Int? = nil,
                                           fileSize: Int64? = nil, format: String? = nil) {
        guard isInitialized, let context = modelContext else {
            DebugLogger.log("⚠️ recordImageAccess skipped: not initialized", level: .normal)
            return
        }

        do {
            let searchKey = fileKey
            var descriptor = FetchDescriptor<ImageCatalogData>(
                predicate: #Predicate<ImageCatalogData> { $0.fileKey == searchKey }
            )
            descriptor.fetchLimit = 1
            let existing = try context.fetch(descriptor)

            if let catalogData = existing.first {
                // 既存エントリを更新
                let newDate = Date()
                DebugLogger.log("📸 Updating existing entry: \(fileName), old date: \(catalogData.lastAccessDate), new date: \(newDate)", level: .verbose)
                catalogData.lastAccessDate = newDate
                catalogData.accessCount += 1
                catalogData.filePath = filePath
                catalogData.fileName = fileName
                catalogData.catalogType = catalogType
                catalogData.relativePath = relativePath
                // メタデータがあれば更新
                if let w = width { catalogData.imageWidth = w }
                if let h = height { catalogData.imageHeight = h }
                if let s = fileSize { catalogData.fileSize = s }
                if let f = format { catalogData.imageFormat = f }
            } else {
                // 新規エントリを作成
                let newData: ImageCatalogData
                if catalogType == .archiveContent, let relPath = relativePath {
                    newData = ImageCatalogData(fileKey: fileKey, parentPath: filePath, relativePath: relPath, fileName: fileName)
                } else {
                    newData = ImageCatalogData(fileKey: fileKey, filePath: filePath, fileName: fileName)
                }
                newData.imageWidth = width
                newData.imageHeight = height
                newData.fileSize = fileSize
                newData.imageFormat = format
                context.insert(newData)

                // 上限チェック
                try enforceLimit(context: context)
            }

            try context.save()
            DebugLogger.log("📸 Recorded image: \(fileName) (\(catalogType)), reloading catalog...", level: .verbose)
            loadCatalog()
            DebugLogger.log("📸 Catalog reloaded, count: \(catalog.count)", level: .verbose)
        } catch {
            DebugLogger.log("❌ Failed to record image access: \(error)", level: .minimal)
        }
    }

    /// 画像アクセスを記録（後方互換性のため残す）
    func recordImageAccess(fileKey: String, filePath: String, fileName: String,
                           width: Int? = nil, height: Int? = nil,
                           fileSize: Int64? = nil, format: String? = nil) {
        recordStandaloneImageAccess(fileKey: fileKey, filePath: filePath, fileName: fileName,
                                    width: width, height: height, fileSize: fileSize, format: format)
    }

    /// カタログの上限をチェックし、超過分を削除
    private func enforceLimit(context: ModelContext) throws {
        let countDescriptor = FetchDescriptor<ImageCatalogData>()
        let totalCount = try context.fetchCount(countDescriptor)
        if totalCount > maxCatalogCount {
            let oldestDescriptor = FetchDescriptor<ImageCatalogData>(
                sortBy: [SortDescriptor(\.lastAccessDate, order: .forward)]
            )
            let oldest = try context.fetch(oldestDescriptor)
            let deleteCount = totalCount - maxCatalogCount
            for i in 0..<deleteCount {
                if i < oldest.count {
                    context.delete(oldest[i])
                }
            }
        }
    }

    // MARK: - Memo

    /// メモを更新
    func updateMemo(for id: String, memo: String?) {
        guard isInitialized, let context = modelContext else { return }

        do {
            let searchId = id
            let descriptor = FetchDescriptor<ImageCatalogData>(
                predicate: #Predicate<ImageCatalogData> { $0.id == searchId }
            )
            let results = try context.fetch(descriptor)

            if let catalogData = results.first {
                catalogData.memo = memo?.isEmpty == true ? nil : memo
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
            let descriptor = FetchDescriptor<ImageCatalogData>(
                predicate: #Predicate<ImageCatalogData> { $0.id == searchId }
            )
            let toDelete = try context.fetch(descriptor)
            for item in toDelete {
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
            let descriptor = FetchDescriptor<ImageCatalogData>()
            let all = try context.fetch(descriptor)
            for item in all {
                context.delete(item)
            }
            try context.save()
            catalog.removeAll()
        } catch {
            DebugLogger.log("❌ Failed to clear image catalog: \(error)", level: .minimal)
        }
    }
}
