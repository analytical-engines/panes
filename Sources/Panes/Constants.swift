import Foundation

enum AppInfo {
    static let name = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Panes"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    /// ビルドタイムスタンプ（ISO8601形式で保存、ローカルタイムで表示）
    static var buildTimestamp: String? {
        guard let timestampStr = Bundle.main.infoDictionary?["BuildTimestamp"] as? String,
              let date = ISO8601DateFormatter().date(from: timestampStr) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// バージョン表示文字列（開発版とリリース版で異なる）
    static var versionString: String {
        #if DEBUG
        // 開発版: バージョン + ビルド番号 + タイムスタンプ
        if let timestamp = buildTimestamp {
            return "\(version) (build \(build)) - \(timestamp)"
        } else {
            return "\(version) (build \(build))"
        }
        #else
        // リリース版: バージョン + タイムスタンプ
        if let timestamp = buildTimestamp {
            return "\(version) - \(timestamp)"
        } else {
            return version
        }
        #endif
    }
}

/// アプリの使用期限管理（ベータ版配布用）
enum AppExpiration {
    /// 使用期限（nil = 期限なし＝正式リリース）
    /// ベータ配布時はここに期限日を設定する
    static let expirationDate: Date? = {
        // 正式リリース時は nil に変更
        // テスト用: 2026-01-31 (本番は 2026-04-01)
        ISO8601DateFormatter().date(from: "2026-01-31T00:00:00Z")
    }()

    /// 期限切れかどうか
    static var isExpired: Bool {
        guard let expiration = expirationDate else { return false }
        return Date() > expiration
    }

    /// 期限までの残り日数（期限なしの場合はnil）
    static var daysRemaining: Int? {
        guard let expiration = expirationDate else { return nil }
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
        return remaining
    }

    /// 期限の表示用文字列（ローカルタイムで日時を表示）
    static var expirationDateString: String? {
        guard let expiration = expirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short  // 時刻も表示（ローカルタイムゾーン）
        return formatter.string(from: expiration)
    }
}
