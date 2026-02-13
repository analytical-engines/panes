import Foundation

/// ウィンドウサイズモード
enum WindowSizeMode: String, CaseIterable {
    case fixed = "fixed"           // 固定サイズ
    case lastUsed = "lastUsed"     // 最後のサイズに追従
}

/// 画像カタログ表示フィルタ
enum ImageCatalogFilter: String, CaseIterable {
    case all = "all"                    // すべて表示
    case standaloneOnly = "standalone"  // 個別画像ファイルのみ
    case archiveOnly = "archive"        // 書庫/フォルダ内画像のみ
}

/// ページめくりトランジションモード
enum PageTransitionMode: String, CaseIterable {
    case always = "always"          // 常にトランジション
    case swipeOnly = "swipeOnly"    // スワイプ時のみ
    case never = "never"            // トランジションなし
}

/// 履歴表示モード
enum HistoryDisplayMode: String, CaseIterable {
    case alwaysShow = "alwaysShow"      // 常に表示
    case alwaysHide = "alwaysHide"      // 常に非表示
    case restoreLast = "restoreLast"    // 終了時の状態を復元
}

/// アプリ全体の設定を管理
@MainActor
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
        static let maxStandaloneImageCount = "maxStandaloneImageCount"
        static let maxArchiveContentImageCount = "maxArchiveContentImageCount"
        static let maxSessionGroupCount = "maxSessionGroupCount"
        static let historyDisplayMode = "historyDisplayMode"
        static let lastHistoryVisible = "lastHistoryVisible"
        static let pageJumpCount = "pageJumpCount"
        static let concurrentLoadingLimit = "concurrentLoadingLimit"
        static let windowSizeMode = "windowSizeMode"
        static let fixedWindowWidth = "fixedWindowWidth"
        static let fixedWindowHeight = "fixedWindowHeight"
        static let lastWindowWidth = "lastWindowWidth"
        static let lastWindowHeight = "lastWindowHeight"
        static let quitOnLastWindowClosed = "quitOnLastWindowClosed"
        static let imageCatalogFilter = "imageCatalogFilter"
        static let defaultHistorySearchType = "defaultHistorySearchType"
        static let initialScreenBackgroundImagePath = "initialScreenBackgroundImagePath"
        static let checkForUpdatesOnLaunch = "checkForUpdatesOnLaunch"
        static let currentWorkspaceId = "currentWorkspaceId"
        static let pageTransitionMode = "pageTransitionMode"
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
        didSet {
            defaults.set(defaultLandscapeThreshold, forKey: Keys.defaultLandscapeThreshold)
            // 閾値が変更されたら通知を発行（自動判定結果をクリアするため）
            NotificationCenter.default.post(name: .landscapeThresholdDidChange, object: nil)
        }
    }

    /// ページジャンプ回数
    var pageJumpCount: Int {
        didSet { defaults.set(pageJumpCount, forKey: Keys.pageJumpCount) }
    }

    /// ページめくりトランジションモード
    var pageTransitionMode: PageTransitionMode {
        didSet { defaults.set(pageTransitionMode.rawValue, forKey: Keys.pageTransitionMode) }
    }

    // MARK: - 履歴設定

    /// 書庫ファイル履歴の最大保存件数
    var maxHistoryCount: Int {
        didSet { defaults.set(maxHistoryCount, forKey: Keys.maxHistoryCount) }
    }

    /// 個別画像カタログの最大保存件数
    var maxStandaloneImageCount: Int {
        didSet { defaults.set(maxStandaloneImageCount, forKey: Keys.maxStandaloneImageCount) }
    }

    /// 書庫/フォルダ内画像カタログの最大保存件数
    var maxArchiveContentImageCount: Int {
        didSet { defaults.set(maxArchiveContentImageCount, forKey: Keys.maxArchiveContentImageCount) }
    }

    /// セッショングループの最大保存件数
    var maxSessionGroupCount: Int {
        didSet { defaults.set(maxSessionGroupCount, forKey: Keys.maxSessionGroupCount) }
    }

    /// 履歴表示モード
    var historyDisplayMode: HistoryDisplayMode {
        didSet { saveHistoryDisplayMode() }
    }

    /// 最後の履歴表示状態（restoreLastモード用）
    var lastHistoryVisible: Bool {
        didSet { defaults.set(lastHistoryVisible, forKey: Keys.lastHistoryVisible) }
    }

    /// 起動時に履歴を表示するかどうかを計算
    var shouldShowHistoryOnLaunch: Bool {
        switch historyDisplayMode {
        case .alwaysShow:
            return true
        case .alwaysHide:
            return false
        case .restoreLast:
            return lastHistoryVisible
        }
    }

    /// 画像カタログ表示フィルタ
    var imageCatalogFilter: ImageCatalogFilter {
        didSet { saveImageCatalogFilter() }
    }

    /// デフォルトの履歴検索タイプ
    var defaultHistorySearchType: SearchTargetType {
        didSet { saveDefaultHistorySearchType() }
    }

    // MARK: - ファイル読み込み設定

    /// 同時読み込み数（複数ファイルを開く際の並列数）
    var concurrentLoadingLimit: Int {
        didSet { defaults.set(concurrentLoadingLimit, forKey: Keys.concurrentLoadingLimit) }
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

    /// 初期画面の背景画像パス（空文字列の場合は背景なし）
    var initialScreenBackgroundImagePath: String {
        didSet { defaults.set(initialScreenBackgroundImagePath, forKey: Keys.initialScreenBackgroundImagePath) }
    }

    /// 起動時にアップデートを確認するか
    var checkForUpdatesOnLaunch: Bool {
        didSet { defaults.set(checkForUpdatesOnLaunch, forKey: Keys.checkForUpdatesOnLaunch) }
    }

    /// 現在のワークスペースID（""はデフォルト）
    var currentWorkspaceId: String {
        didSet { defaults.set(currentWorkspaceId, forKey: Keys.currentWorkspaceId) }
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

        // ページジャンプ回数の読み込み
        if defaults.object(forKey: Keys.pageJumpCount) != nil {
            pageJumpCount = defaults.integer(forKey: Keys.pageJumpCount)
        } else {
            pageJumpCount = 5  // デフォルト: 5回
        }

        // ページめくりトランジションモードの読み込み
        if let modeString = defaults.string(forKey: Keys.pageTransitionMode),
           let mode = PageTransitionMode(rawValue: modeString) {
            pageTransitionMode = mode
        } else {
            pageTransitionMode = .always  // デフォルト: 常にトランジション
        }

        // 書庫ファイル履歴最大件数の読み込み
        if defaults.object(forKey: Keys.maxHistoryCount) != nil {
            maxHistoryCount = defaults.integer(forKey: Keys.maxHistoryCount)
        } else {
            maxHistoryCount = 50  // デフォルト: 50件
        }

        // 個別画像カタログ最大件数の読み込み
        if defaults.object(forKey: Keys.maxStandaloneImageCount) != nil {
            maxStandaloneImageCount = defaults.integer(forKey: Keys.maxStandaloneImageCount)
        } else {
            maxStandaloneImageCount = 10000  // デフォルト: 10000件（実質無制限）
        }

        // 書庫/フォルダ内画像カタログ最大件数の読み込み
        if defaults.object(forKey: Keys.maxArchiveContentImageCount) != nil {
            maxArchiveContentImageCount = defaults.integer(forKey: Keys.maxArchiveContentImageCount)
        } else {
            maxArchiveContentImageCount = 1000  // デフォルト: 1000件
        }

        // セッショングループ最大件数の読み込み
        if defaults.object(forKey: Keys.maxSessionGroupCount) != nil {
            maxSessionGroupCount = defaults.integer(forKey: Keys.maxSessionGroupCount)
        } else {
            maxSessionGroupCount = 50  // デフォルト: 50件
        }

        // 履歴表示モードの読み込み
        if let modeString = defaults.string(forKey: Keys.historyDisplayMode),
           let mode = HistoryDisplayMode(rawValue: modeString) {
            historyDisplayMode = mode
        } else {
            // 旧設定からの移行
            if defaults.object(forKey: "showHistoryOnLaunch") != nil {
                let oldValue = defaults.bool(forKey: "showHistoryOnLaunch")
                historyDisplayMode = oldValue ? .alwaysShow : .alwaysHide
            } else {
                historyDisplayMode = .alwaysHide  // デフォルト: 常に非表示
            }
        }

        // 最後の履歴表示状態の読み込み
        if defaults.object(forKey: Keys.lastHistoryVisible) != nil {
            lastHistoryVisible = defaults.bool(forKey: Keys.lastHistoryVisible)
        } else {
            lastHistoryVisible = false  // デフォルト: 非表示
        }

        // 画像カタログ表示フィルタの読み込み
        if let filterString = defaults.string(forKey: Keys.imageCatalogFilter),
           let filter = ImageCatalogFilter(rawValue: filterString) {
            imageCatalogFilter = filter
        } else {
            imageCatalogFilter = .all  // デフォルト: すべて表示
        }

        // デフォルト履歴検索タイプの読み込み
        if let typeString = defaults.string(forKey: Keys.defaultHistorySearchType),
           let type = SearchTargetType(rawValue: typeString) {
            defaultHistorySearchType = type
        } else {
            defaultHistorySearchType = .archive  // デフォルト: 書庫のみ
        }

        // 同時読み込み数の読み込み
        if defaults.object(forKey: Keys.concurrentLoadingLimit) != nil {
            concurrentLoadingLimit = defaults.integer(forKey: Keys.concurrentLoadingLimit)
        } else {
            concurrentLoadingLimit = 1  // デフォルト: 1
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

        // 初期画面の背景画像パス
        initialScreenBackgroundImagePath = defaults.string(forKey: Keys.initialScreenBackgroundImagePath) ?? ""

        // 起動時のアップデート確認
        if defaults.object(forKey: Keys.checkForUpdatesOnLaunch) != nil {
            checkForUpdatesOnLaunch = defaults.bool(forKey: Keys.checkForUpdatesOnLaunch)
        } else {
            checkForUpdatesOnLaunch = true  // デフォルト: 有効
        }

        // 現在のワークスペースID
        currentWorkspaceId = defaults.string(forKey: Keys.currentWorkspaceId) ?? ""
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

    private func saveImageCatalogFilter() {
        defaults.set(imageCatalogFilter.rawValue, forKey: Keys.imageCatalogFilter)
    }

    private func saveHistoryDisplayMode() {
        defaults.set(historyDisplayMode.rawValue, forKey: Keys.historyDisplayMode)
    }

    private func saveDefaultHistorySearchType() {
        defaults.set(defaultHistorySearchType.rawValue, forKey: Keys.defaultHistorySearchType)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 横長判定の閾値が変更された
    static let landscapeThresholdDidChange = Notification.Name("landscapeThresholdDidChange")

    /// ウィンドウがフォーカスを得た（userInfo["windowNumber"]にウィンドウ番号）
    static let windowDidBecomeKey = Notification.Name("windowDidBecomeKey")
}
