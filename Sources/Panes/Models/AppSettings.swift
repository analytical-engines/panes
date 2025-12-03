import Foundation

/// ウィンドウサイズモード
enum WindowSizeMode: String, CaseIterable {
    case fixed = "fixed"           // 固定サイズ
    case lastUsed = "lastUsed"     // 最後のサイズに追従
}

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
        static let showHistoryOnLaunch = "showHistoryOnLaunch"
        static let sessionRestoreEnabled = "sessionRestoreEnabled"
        static let sessionConcurrentLoadingLimit = "sessionConcurrentLoadingLimit"
        static let windowSizeMode = "windowSizeMode"
        static let fixedWindowWidth = "fixedWindowWidth"
        static let fixedWindowHeight = "fixedWindowHeight"
        static let lastWindowWidth = "lastWindowWidth"
        static let lastWindowHeight = "lastWindowHeight"
        static let quitOnLastWindowClosed = "quitOnLastWindowClosed"
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

    /// 起動時に履歴を表示するか
    var showHistoryOnLaunch: Bool {
        didSet { defaults.set(showHistoryOnLaunch, forKey: Keys.showHistoryOnLaunch) }
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

    // MARK: - ウィンドウ設定

    /// ウィンドウサイズモード
    var windowSizeMode: WindowSizeMode {
        didSet { saveWindowSizeMode() }
    }

    /// 固定ウィンドウ幅
    var fixedWindowWidth: Double {
        didSet { defaults.set(fixedWindowWidth, forKey: Keys.fixedWindowWidth) }
    }

    /// 固定ウィンドウ高さ
    var fixedWindowHeight: Double {
        didSet { defaults.set(fixedWindowHeight, forKey: Keys.fixedWindowHeight) }
    }

    /// 最後に使用したウィンドウ幅
    var lastWindowWidth: Double {
        didSet { defaults.set(lastWindowWidth, forKey: Keys.lastWindowWidth) }
    }

    /// 最後に使用したウィンドウ高さ
    var lastWindowHeight: Double {
        didSet { defaults.set(lastWindowHeight, forKey: Keys.lastWindowHeight) }
    }

    // MARK: - アプリ動作設定

    /// 最後のウィンドウを閉じたらアプリを終了するか
    var quitOnLastWindowClosed: Bool {
        didSet { defaults.set(quitOnLastWindowClosed, forKey: Keys.quitOnLastWindowClosed) }
    }

    /// 新規ウィンドウ用のサイズを取得
    var newWindowSize: CGSize {
        switch windowSizeMode {
        case .fixed:
            return CGSize(width: fixedWindowWidth, height: fixedWindowHeight)
        case .lastUsed:
            return CGSize(width: lastWindowWidth, height: lastWindowHeight)
        }
    }

    /// ウィンドウサイズを更新（リサイズ時に呼び出し）
    func updateLastWindowSize(_ size: CGSize) {
        lastWindowWidth = size.width
        lastWindowHeight = size.height
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

        // 起動時の履歴表示の読み込み
        if defaults.object(forKey: Keys.showHistoryOnLaunch) != nil {
            showHistoryOnLaunch = defaults.bool(forKey: Keys.showHistoryOnLaunch)
        } else {
            showHistoryOnLaunch = true  // デフォルト: 表示する
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

        // ウィンドウサイズモードの読み込み
        if let modeString = defaults.string(forKey: Keys.windowSizeMode),
           let mode = WindowSizeMode(rawValue: modeString) {
            windowSizeMode = mode
        } else {
            windowSizeMode = .lastUsed  // デフォルト: 最後のサイズに追従
        }

        // 固定ウィンドウサイズの読み込み
        if defaults.object(forKey: Keys.fixedWindowWidth) != nil {
            fixedWindowWidth = defaults.double(forKey: Keys.fixedWindowWidth)
        } else {
            fixedWindowWidth = 1200  // デフォルト: 1200
        }
        if defaults.object(forKey: Keys.fixedWindowHeight) != nil {
            fixedWindowHeight = defaults.double(forKey: Keys.fixedWindowHeight)
        } else {
            fixedWindowHeight = 800  // デフォルト: 800
        }

        // 最後のウィンドウサイズの読み込み
        if defaults.object(forKey: Keys.lastWindowWidth) != nil {
            lastWindowWidth = defaults.double(forKey: Keys.lastWindowWidth)
        } else {
            lastWindowWidth = 1200  // デフォルト: 1200
        }
        if defaults.object(forKey: Keys.lastWindowHeight) != nil {
            lastWindowHeight = defaults.double(forKey: Keys.lastWindowHeight)
        } else {
            lastWindowHeight = 800  // デフォルト: 800
        }

        // 最後のウィンドウを閉じた時の動作
        if defaults.object(forKey: Keys.quitOnLastWindowClosed) != nil {
            quitOnLastWindowClosed = defaults.bool(forKey: Keys.quitOnLastWindowClosed)
        } else {
            quitOnLastWindowClosed = true  // デフォルト: 終了する
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

    private func saveWindowSizeMode() {
        defaults.set(windowSizeMode.rawValue, forKey: Keys.windowSizeMode)
    }
}
