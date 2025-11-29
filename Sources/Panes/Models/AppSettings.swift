import Foundation

/// アプリ全体の設定を管理
@Observable
class AppSettings {
    private let defaults = UserDefaults.standard

    // UserDefaultsキー
    private enum Keys {
        static let defaultViewMode = "defaultViewMode"
        static let defaultReadingDirection = "defaultReadingDirection"
        static let defaultShowStatusBar = "defaultShowStatusBar"
        static let defaultLandscapeThreshold = "defaultLandscapeThreshold"
        static let maxHistoryCount = "maxHistoryCount"
        static let sessionRestoreEnabled = "sessionRestoreEnabled"
        static let sessionConcurrentLoadingLimit = "sessionConcurrentLoadingLimit"
    }

    // MARK: - 表示設定

    /// デフォルト表示モード
    var defaultViewMode: ViewMode {
        didSet { saveViewMode() }
    }

    /// デフォルト読み方向
    var defaultReadingDirection: ReadingDirection {
        didSet { saveReadingDirection() }
    }

    /// デフォルトでステータスバーを表示するか
    var defaultShowStatusBar: Bool {
        didSet { defaults.set(defaultShowStatusBar, forKey: Keys.defaultShowStatusBar) }
    }

    /// 横長判定のデフォルト閾値
    var defaultLandscapeThreshold: Double {
        didSet { defaults.set(defaultLandscapeThreshold, forKey: Keys.defaultLandscapeThreshold) }
    }

    // MARK: - 履歴設定

    /// 履歴の最大保存件数
    var maxHistoryCount: Int {
        didSet { defaults.set(maxHistoryCount, forKey: Keys.maxHistoryCount) }
    }

    // MARK: - セッション設定

    /// セッション復元を有効にするか
    var sessionRestoreEnabled: Bool {
        didSet { defaults.set(sessionRestoreEnabled, forKey: Keys.sessionRestoreEnabled) }
    }

    /// セッション復元時の同時読み込み数
    var sessionConcurrentLoadingLimit: Int {
        didSet { defaults.set(sessionConcurrentLoadingLimit, forKey: Keys.sessionConcurrentLoadingLimit) }
    }

    // MARK: - 初期化

    init() {
        // 表示モードの読み込み
        if let modeString = defaults.string(forKey: Keys.defaultViewMode) {
            defaultViewMode = modeString == "spread" ? .spread : .single
        } else {
            defaultViewMode = .spread  // デフォルト: 見開き
        }

        // 読み方向の読み込み
        if let directionString = defaults.string(forKey: Keys.defaultReadingDirection) {
            defaultReadingDirection = directionString == "leftToRight" ? .leftToRight : .rightToLeft
        } else {
            defaultReadingDirection = .rightToLeft  // デフォルト: 右→左
        }

        // ステータスバー表示の読み込み
        if defaults.object(forKey: Keys.defaultShowStatusBar) != nil {
            defaultShowStatusBar = defaults.bool(forKey: Keys.defaultShowStatusBar)
        } else {
            defaultShowStatusBar = false  // デフォルト: 非表示（オーバーレイで表示）
        }

        // 横長判定閾値の読み込み
        if defaults.object(forKey: Keys.defaultLandscapeThreshold) != nil {
            defaultLandscapeThreshold = defaults.double(forKey: Keys.defaultLandscapeThreshold)
        } else {
            defaultLandscapeThreshold = 1.2  // デフォルト: 1.2
        }

        // 履歴最大件数の読み込み
        if defaults.object(forKey: Keys.maxHistoryCount) != nil {
            maxHistoryCount = defaults.integer(forKey: Keys.maxHistoryCount)
        } else {
            maxHistoryCount = 50  // デフォルト: 50件
        }

        // セッション復元の読み込み
        if defaults.object(forKey: Keys.sessionRestoreEnabled) != nil {
            sessionRestoreEnabled = defaults.bool(forKey: Keys.sessionRestoreEnabled)
        } else {
            sessionRestoreEnabled = false  // デフォルト: 無効
        }

        // 同時読み込み数の読み込み
        if defaults.object(forKey: Keys.sessionConcurrentLoadingLimit) != nil {
            sessionConcurrentLoadingLimit = defaults.integer(forKey: Keys.sessionConcurrentLoadingLimit)
        } else {
            sessionConcurrentLoadingLimit = 1  // デフォルト: 1
        }
    }

    // MARK: - 保存メソッド

    private func saveViewMode() {
        let modeString = defaultViewMode == .spread ? "spread" : "single"
        defaults.set(modeString, forKey: Keys.defaultViewMode)
    }

    private func saveReadingDirection() {
        let directionString = defaultReadingDirection == .leftToRight ? "leftToRight" : "rightToLeft"
        defaults.set(directionString, forKey: Keys.defaultReadingDirection)
    }
}
