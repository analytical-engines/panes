import Foundation
import SwiftData

/// セッショングループの管理クラス（SwiftData版）
@MainActor
@Observable
class SessionGroupManager {
    private let legacyStorageKey = "sessionGroups"
    private let migrationCompletedKey = "sessionGroupMigrationToSwiftDataCompleted"

    /// ModelContextへの参照（FileHistoryManagerから共有）
    private var modelContext: ModelContext?

    /// 現在のワークスペースID（""はデフォルト）
    var workspaceId: String = ""

    /// 保存されたセッショングループ一覧
    private(set) var sessionGroups: [SessionGroup] = []

    /// 最大保存件数
    var maxSessionGroupCount: Int = 50

    init() {
        // ModelContextは後からsetModelContextで設定される
    }

    /// ModelContextを設定（FileHistoryManagerから呼ばれる）
    func setModelContext(_ context: ModelContext?) {
        self.modelContext = context
        if context != nil {
            migrateFromUserDefaultsIfNeeded()
            loadSessionGroups()
        }
    }

    // MARK: - Migration

    /// UserDefaultsからSwiftDataへの移行（初回のみ）
    private func migrateFromUserDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else {
            return
        }

        guard let context = modelContext else {
            DebugLogger.log("❌ SessionGroup migration skipped: ModelContext not available", level: .minimal)
            return
        }

        // 既存のUserDefaultsデータを読み込む
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey),
              let legacyGroups = try? JSONDecoder().decode([SessionGroup].self, from: data) else {
            // データがない場合も移行完了とマーク
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            DebugLogger.log("📦 No legacy session groups to migrate", level: .normal)
            return
        }

        DebugLogger.log("📦 Migrating \(legacyGroups.count) session groups from UserDefaults to SwiftData", level: .minimal)

        // SwiftDataに移行
        for group in legacyGroups {
            let groupData = SessionGroupData(from: group)
            context.insert(groupData)
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)

            // 移行完了後にUserDefaultsから削除
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)

            DebugLogger.log("✅ Session group migration completed: \(legacyGroups.count) groups", level: .minimal)
        } catch {
            DebugLogger.log("❌ Session group migration failed: \(error)", level: .minimal)
        }
    }

    // MARK: - Persistence

    /// セッショングループを読み込む
    func loadSessionGroups() {
        guard let context = modelContext else {
            sessionGroups = []
            return
        }

        do {
            let wid = workspaceId
            let descriptor = FetchDescriptor<SessionGroupData>(
                predicate: #Predicate<SessionGroupData> { $0.workspaceId == wid },
                sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
            )
            let groupsData = try context.fetch(descriptor)
            sessionGroups = groupsData.map { $0.toSessionGroup() }
            DebugLogger.log("📂 Session groups loaded: \(sessionGroups.count) (workspace: '\(wid)')", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to load session groups: \(error)", level: .minimal)
            sessionGroups = []
        }
    }

    // MARK: - CRUD Operations

    /// 新しいセッショングループを作成
    func createSessionGroup(name: String, from windowEntries: [WindowSessionEntry]) -> SessionGroup {
        let group = SessionGroup(name: name, from: windowEntries)

        guard let context = modelContext else {
            // ModelContextがない場合はメモリ上のみで管理
            sessionGroups.insert(group, at: 0)
            if sessionGroups.count > maxSessionGroupCount {
                sessionGroups = Array(sessionGroups.prefix(maxSessionGroupCount))
            }
            DebugLogger.log("📝 Session group created (memory only): \(name) with \(windowEntries.count) files", level: .normal)
            return group
        }

        let groupData = SessionGroupData(from: group)
        groupData.workspaceId = workspaceId
        context.insert(groupData)

        do {
            // 最大件数を超えた場合、古いものを削除
            let countDescriptor = FetchDescriptor<SessionGroupData>()
            let totalCount = try context.fetchCount(countDescriptor)
            if totalCount > maxSessionGroupCount {
                let oldestDescriptor = FetchDescriptor<SessionGroupData>(
                    sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
                )
                let oldest = try context.fetch(oldestDescriptor)
                let deleteCount = totalCount - maxSessionGroupCount
                for i in 0..<deleteCount {
                    if i < oldest.count {
                        context.delete(oldest[i])
                    }
                }
            }

            try context.save()
            loadSessionGroups()
            DebugLogger.log("📝 Session group created: \(name) with \(windowEntries.count) files", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to create session group: \(error)", level: .minimal)
        }

        return group
    }

    /// セッショングループを削除
    func deleteSessionGroup(id: UUID) {
        guard let context = modelContext else {
            sessionGroups.removeAll { $0.id == id }
            DebugLogger.log("🗑️ Session group deleted (memory only): \(id)", level: .normal)
            return
        }

        do {
            let idString = id.uuidString
            let descriptor = FetchDescriptor<SessionGroupData>(
                predicate: #Predicate<SessionGroupData> { $0.id == idString }
            )
            let toDelete = try context.fetch(descriptor)
            for item in toDelete {
                context.delete(item)
            }
            try context.save()
            loadSessionGroups()
            DebugLogger.log("🗑️ Session group deleted: \(id)", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to delete session group: \(error)", level: .minimal)
        }
    }

    /// セッショングループの名前を変更
    func renameSessionGroup(id: UUID, newName: String) {
        guard let context = modelContext else {
            if let index = sessionGroups.firstIndex(where: { $0.id == id }) {
                sessionGroups[index].name = newName
            }
            DebugLogger.log("✏️ Session group renamed (memory only): \(newName)", level: .normal)
            return
        }

        do {
            let idString = id.uuidString
            var descriptor = FetchDescriptor<SessionGroupData>(
                predicate: #Predicate<SessionGroupData> { $0.id == idString }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            if let groupData = results.first {
                groupData.name = newName
                try context.save()
                loadSessionGroups()
                DebugLogger.log("✏️ Session group renamed: \(newName)", level: .normal)
            }
        } catch {
            DebugLogger.log("❌ Failed to rename session group: \(error)", level: .minimal)
        }
    }

    /// セッショングループのアクセス日時を更新
    func updateLastAccessed(id: UUID) {
        guard let context = modelContext else {
            if let index = sessionGroups.firstIndex(where: { $0.id == id }) {
                sessionGroups[index].lastAccessedAt = Date()
                sessionGroups.sort { $0.lastAccessedAt > $1.lastAccessedAt }
            }
            return
        }

        do {
            let idString = id.uuidString
            var descriptor = FetchDescriptor<SessionGroupData>(
                predicate: #Predicate<SessionGroupData> { $0.id == idString }
            )
            descriptor.fetchLimit = 1
            let results = try context.fetch(descriptor)
            if let groupData = results.first {
                groupData.lastAccessedAt = Date()
                try context.save()
                loadSessionGroups()
            }
        } catch {
            DebugLogger.log("❌ Failed to update last accessed: \(error)", level: .minimal)
        }
    }

    /// 全てのセッショングループをクリア（現在のワークスペースのみ）
    func clearAllSessionGroups() {
        guard let context = modelContext else {
            sessionGroups.removeAll()
            DebugLogger.log("🗑️ All session groups cleared (memory only)", level: .normal)
            return
        }

        do {
            let wid = workspaceId
            let descriptor = FetchDescriptor<SessionGroupData>(
                predicate: #Predicate<SessionGroupData> { $0.workspaceId == wid }
            )
            let all = try context.fetch(descriptor)
            for item in all {
                context.delete(item)
            }
            try context.save()
            sessionGroups.removeAll()
            DebugLogger.log("🗑️ All session groups cleared", level: .normal)
        } catch {
            DebugLogger.log("❌ Failed to clear session groups: \(error)", level: .minimal)
        }
    }

    // MARK: - Query

    /// IDでセッショングループを取得
    func sessionGroup(for id: UUID) -> SessionGroup? {
        return sessionGroups.first { $0.id == id }
    }

    /// セッショングループ数
    var count: Int {
        sessionGroups.count
    }

    /// フィルタリング
    func filteredSessionGroups(matching query: String) -> [SessionGroup] {
        if query.isEmpty {
            return sessionGroups
        }
        let lowercased = query.lowercased()
        return sessionGroups.filter { group in
            // 名前で検索
            if group.name.lowercased().contains(lowercased) {
                return true
            }
            // ファイル名で検索
            return group.entries.contains { entry in
                entry.fileName.lowercased().contains(lowercased)
            }
        }
    }

    // MARK: - Import

    /// セッションをImport
    /// - Parameters:
    ///   - sessions: インポートするセッション
    ///   - merge: trueならマージ（同名は別名追加）、falseなら置換
    /// - Returns: インポートされた件数
    func importSessions(_ sessions: [SessionGroup], merge: Bool) -> Int {
        guard let context = modelContext else {
            DebugLogger.log("⚠️ importSessions skipped: ModelContext not available", level: .normal)
            return 0
        }

        guard !sessions.isEmpty else { return 0 }

        var importedCount = 0

        do {
            if !merge {
                // Replace mode: delete existing sessions in current workspace
                let wid = workspaceId
                let descriptor = FetchDescriptor<SessionGroupData>(
                    predicate: #Predicate<SessionGroupData> { $0.workspaceId == wid }
                )
                let all = try context.fetch(descriptor)
                for item in all {
                    context.delete(item)
                }
                sessionGroups.removeAll()
            }

            for session in sessions {
                // 同名セッションがあるかチェック
                let uniqueName = generateUniqueName(baseName: session.name)

                // 新しいセッションを作成（現在のワークスペースIDを設定）
                let newSession = SessionGroup(
                    id: UUID(),
                    name: uniqueName,
                    entries: session.entries,
                    createdAt: session.createdAt,
                    lastAccessedAt: session.lastAccessedAt,
                    workspaceId: workspaceId
                )

                let groupData = SessionGroupData(from: newSession)
                context.insert(groupData)
                importedCount += 1
            }

            // 上限チェック
            enforceLimit(context: context)

            try context.save()
            loadSessionGroups()

            DebugLogger.log("📥 Imported \(importedCount) sessions", level: .normal)
            return importedCount
        } catch {
            DebugLogger.log("❌ Failed to import sessions: \(error)", level: .minimal)
            return 0
        }
    }

    /// 重複しない名前を生成
    private func generateUniqueName(baseName: String) -> String {
        let existingNames = Set(sessionGroups.map { $0.name })

        if !existingNames.contains(baseName) {
            return baseName
        }

        // "名前 (2)", "名前 (3)" ... の形式で探す
        var counter = 2
        while true {
            let candidateName = "\(baseName) (\(counter))"
            if !existingNames.contains(candidateName) {
                return candidateName
            }
            counter += 1
        }
    }

    /// 上限を超えた古いセッションを削除
    private func enforceLimit(context: ModelContext) {
        do {
            let countDescriptor = FetchDescriptor<SessionGroupData>()
            let totalCount = try context.fetchCount(countDescriptor)

            if totalCount > maxSessionGroupCount {
                let oldestDescriptor = FetchDescriptor<SessionGroupData>(
                    sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
                )
                let oldest = try context.fetch(oldestDescriptor)
                let deleteCount = totalCount - maxSessionGroupCount
                for i in 0..<deleteCount {
                    if i < oldest.count {
                        context.delete(oldest[i])
                    }
                }
            }
        } catch {
            DebugLogger.log("❌ Failed to enforce session limit: \(error)", level: .minimal)
        }
    }
}
