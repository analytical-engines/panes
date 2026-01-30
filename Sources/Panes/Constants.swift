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
