import Foundation
import SwiftData

/// SwiftData用のセッショングループモデル
@Model
final class SessionGroupData {
    /// セッショングループの一意識別子
    @Attribute(.unique) var id: String

    /// グループ名
    var name: String

    /// 作成日時
    var createdAt: Date

    /// 最終アクセス日時
    var lastAccessedAt: Date

    /// エントリ情報（JSON形式で保存）
    var entriesData: Data?

    /// ワークスペースID（""=デフォルト、将来のworkspace機能で使用）
    var workspaceId: String = ""

    init(id: String = UUID().uuidString, name: String, entries: [SessionGroupEntry] = []) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.entriesData = try? JSONEncoder().encode(entries)
    }

    /// SessionGroupから作成（マイグレーション用）
    convenience init(from group: SessionGroup) {
        self.init(id: group.id.uuidString, name: group.name, entries: group.entries)
        self.createdAt = group.createdAt
        self.lastAccessedAt = group.lastAccessedAt
        self.workspaceId = group.workspaceId
    }

    /// エントリを取得
    func getEntries() -> [SessionGroupEntry] {
        guard let data = entriesData else { return [] }
        return (try? JSONDecoder().decode([SessionGroupEntry].self, from: data)) ?? []
    }

    /// エントリを設定
    func setEntries(_ entries: [SessionGroupEntry]) {
        entriesData = try? JSONEncoder().encode(entries)
    }

    /// SessionGroupに変換（既存コードとの互換性のため）
    func toSessionGroup() -> SessionGroup {
        SessionGroup(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            entries: getEntries(),
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt,
            workspaceId: workspaceId
        )
    }
}
