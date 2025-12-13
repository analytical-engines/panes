import Foundation

/// セッショングループの管理クラス
@MainActor
@Observable
class SessionGroupManager {
    private let storageKey = "sessionGroups"
    private let defaults = UserDefaults.standard

    /// 保存されたセッショングループ一覧
    private(set) var sessionGroups: [SessionGroup] = []

    /// 最大保存件数
    var maxSessionGroupCount: Int = 50

    init() {
        loadSessionGroups()
    }

    // MARK: - Persistence

    /// セッショングループを読み込む
    func loadSessionGroups() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SessionGroup].self, from: data) else {
            sessionGroups = []
            return
        }
        sessionGroups = decoded.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        DebugLogger.log("📂 Session groups loaded: \(sessionGroups.count)", level: .normal)
    }

    /// セッショングループを保存する
    private func saveSessionGroups() {
        guard let encoded = try? JSONEncoder().encode(sessionGroups) else {
            DebugLogger.log("❌ Failed to encode session groups", level: .normal)
            return
        }
        defaults.set(encoded, forKey: storageKey)
        DebugLogger.log("💾 Session groups saved: \(sessionGroups.count)", level: .normal)
    }

    // MARK: - CRUD Operations

    /// 新しいセッショングループを作成
    func createSessionGroup(name: String, from windowEntries: [WindowSessionEntry]) -> SessionGroup {
        let group = SessionGroup(name: name, from: windowEntries)
        sessionGroups.insert(group, at: 0)

        // 最大件数を超えた場合、古いものを削除
        if sessionGroups.count > maxSessionGroupCount {
            sessionGroups = Array(sessionGroups.prefix(maxSessionGroupCount))
        }

        saveSessionGroups()
        DebugLogger.log("📝 Session group created: \(name) with \(windowEntries.count) files", level: .normal)
        return group
    }

    /// セッショングループを削除
    func deleteSessionGroup(id: UUID) {
        sessionGroups.removeAll { $0.id == id }
        saveSessionGroups()
        DebugLogger.log("🗑️ Session group deleted: \(id)", level: .normal)
    }

    /// セッショングループの名前を変更
    func renameSessionGroup(id: UUID, newName: String) {
        guard let index = sessionGroups.firstIndex(where: { $0.id == id }) else { return }
        sessionGroups[index].name = newName
        saveSessionGroups()
        DebugLogger.log("✏️ Session group renamed: \(newName)", level: .normal)
    }

    /// セッショングループのアクセス日時を更新
    func updateLastAccessed(id: UUID) {
        guard let index = sessionGroups.firstIndex(where: { $0.id == id }) else { return }
        sessionGroups[index].lastAccessedAt = Date()
        // 再ソート
        sessionGroups.sort { $0.lastAccessedAt > $1.lastAccessedAt }
        saveSessionGroups()
    }

    /// 全てのセッショングループをクリア
    func clearAllSessionGroups() {
        sessionGroups.removeAll()
        defaults.removeObject(forKey: storageKey)
        DebugLogger.log("🗑️ All session groups cleared", level: .normal)
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
}
