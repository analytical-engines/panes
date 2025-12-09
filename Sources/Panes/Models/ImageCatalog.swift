import Foundation
import SwiftData

/// 画像カタログのエントリ（UIモデル用）
struct ImageCatalogEntry: Codable, Identifiable {
    let id: String
    let fileKey: String
    let filePath: String
    let fileName: String
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
        FileManager.default.fileExists(atPath: filePath)
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

    init(id: String, fileKey: String, filePath: String, fileName: String,
         lastAccessDate: Date, accessCount: Int, memo: String?,
         imageWidth: Int?, imageHeight: Int?, fileSize: Int64?,
         imageFormat: String?, tags: [String]) {
        self.id = id
        self.fileKey = fileKey
        self.filePath = filePath
        self.fileName = fileName
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
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            modelContext = ModelContext(modelContainer!)
            initializationError = nil
            DebugLogger.log("📦 SwiftData initialized for ImageCatalog", level: .normal)
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
        } catch {
            DebugLogger.log("❌ Failed to load image catalog: \(error)", level: .minimal)
        }
    }

    // MARK: - Record Access

    /// 画像アクセスを記録
    func recordImageAccess(fileKey: String, filePath: String, fileName: String,
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
                catalogData.lastAccessDate = Date()
                catalogData.accessCount += 1
                catalogData.filePath = filePath
                catalogData.fileName = fileName
                // メタデータがあれば更新
                if let w = width { catalogData.imageWidth = w }
                if let h = height { catalogData.imageHeight = h }
                if let s = fileSize { catalogData.fileSize = s }
                if let f = format { catalogData.imageFormat = f }
            } else {
                // 新規エントリを作成
                let newData = ImageCatalogData(fileKey: fileKey, filePath: filePath, fileName: fileName)
                newData.imageWidth = width
                newData.imageHeight = height
                newData.fileSize = fileSize
                newData.imageFormat = format
                context.insert(newData)

                // 上限チェック
                try enforceLimit(context: context)
            }

            try context.save()
            loadCatalog()

            DebugLogger.log("📸 Recorded image: \(fileName)", level: .verbose)
        } catch {
            DebugLogger.log("❌ Failed to record image access: \(error)", level: .minimal)
        }
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
