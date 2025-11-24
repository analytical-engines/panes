import Foundation

/// デバッグレベル
enum DebugLevel: Int {
    case off = 0      // デバッグ出力なし
    case minimal = 1  // 最小限（エラーのみ）
    case normal = 2   // 通常（主要な処理）
    case verbose = 3  // 詳細（すべて）
}

/// デバッグログ出力のユーティリティ
struct DebugLogger {
    // デバッグレベル（環境変数 DEBUG_LEVEL で設定可能、デフォルトは off）
    static let debugLevel: DebugLevel = {
        if let levelStr = ProcessInfo.processInfo.environment["DEBUG_LEVEL"],
           let levelInt = Int(levelStr),
           let level = DebugLevel(rawValue: levelInt) {
            return level
        }
        return .off
    }()

    /// デバッグログを出力
    /// - Parameters:
    ///   - message: ログメッセージ
    ///   - level: 必要なデバッグレベル
    static func log(_ message: String, level: DebugLevel = .normal) {
        if debugLevel.rawValue >= level.rawValue {
            print(message)
        }
    }
}
