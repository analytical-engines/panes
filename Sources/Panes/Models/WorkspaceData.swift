import Foundation
import SwiftData

/// SwiftData用のワークスペースモデル
/// 履歴情報を用途別に分離するための将来機能用
@Model
final class WorkspaceData {
    /// ワークスペースの一意識別子（""はデフォルトworkspace用に予約）
    @Attribute(.unique) var id: String

    /// 表示名
    var name: String

    /// 作成日時
    var createdAt: Date

    /// パスワードのハッシュ（nilならパスワードなし）
    /// カジュアルな保護用（画面を覗かれた時に見えない程度）
    var passwordHash: String?

    /// 一覧から非表示
    var isHidden: Bool = false

    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.passwordHash = nil
        self.isHidden = false
    }
}
