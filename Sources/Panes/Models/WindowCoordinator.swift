import Foundation
import AppKit

/// ウィンドウ番号とBookViewModelの対応を管理するクラス
/// SwiftUIの@FocusedValueの代替として、NSApp.keyWindowから直接ViewModelを取得できるようにする
/// これによりフォーカス変更時の全ウィンドウbody再評価を回避する
@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()

    /// ウィンドウ番号からViewModelへのマッピング
    private var windowViewModels: [Int: BookViewModel] = [:]

    /// ウィンドウ番号からshowHistoryのgetter/setterへのマッピング
    private var showHistoryGetters: [Int: () -> Bool] = [:]
    private var showHistorySetters: [Int: (Bool) -> Void] = [:]

    /// ウィンドウ番号から検索フォーカスのgetter/setterへのマッピング
    private var searchFocusGetters: [Int: () -> Bool] = [:]
    private var searchFocusSetters: [Int: (Bool) -> Void] = [:]

    /// ウィンドウ番号から履歴選択クリアのコールバック
    private var clearSelectionCallbacks: [Int: () -> Void] = [:]

    /// ウィンドウ番号からメインビューフォーカスのコールバック
    private var focusMainViewCallbacks: [Int: () -> Void] = [:]

    /// 現在アクティブなウィンドウ番号（markAsActiveで明示的に設定）
    private var activeWindowNumber: Int?

    /// フォーカス通知のデバウンス用（ウィンドウ番号 -> 最終通知時刻）
    private var lastFocusNotificationTime: [Int: Date] = [:]
    /// デバウンス間隔（秒）- 外部アプリからの復帰時の連続イベントをフィルタ
    private let focusDebounceInterval: TimeInterval = 0.5

    private init() {}

    // MARK: - Registration

    /// ViewModelを登録する
    func register(windowNumber: Int, viewModel: BookViewModel) {
        windowViewModels[windowNumber] = viewModel
        // 登録時にアクティブウィンドウとして記録
        activeWindowNumber = windowNumber
        DebugLogger.log("📋 WindowCoordinator: registered viewModel for window \(windowNumber)", level: .verbose)
    }

    /// ウィンドウをアクティブとしてマークする（D&D、フォーカス取得時に呼び出す）
    func markAsActive(windowNumber: Int) {
        if windowViewModels[windowNumber] != nil {
            activeWindowNumber = windowNumber
            DebugLogger.log("📋 WindowCoordinator: marked window \(windowNumber) as active", level: .verbose)
        }
    }

    /// showHistoryのgetter/setterを登録する
    func registerShowHistory(windowNumber: Int, getter: @escaping () -> Bool, setter: @escaping (Bool) -> Void) {
        showHistoryGetters[windowNumber] = getter
        showHistorySetters[windowNumber] = setter
        DebugLogger.log("📋 WindowCoordinator: registered showHistory for window \(windowNumber)", level: .verbose)
    }

    /// 検索フォーカスのgetter/setterを登録する
    func registerSearchFocus(windowNumber: Int, getter: @escaping () -> Bool, setter: @escaping (Bool) -> Void) {
        searchFocusGetters[windowNumber] = getter
        searchFocusSetters[windowNumber] = setter
        DebugLogger.log("📋 WindowCoordinator: registered searchFocus for window \(windowNumber)", level: .verbose)
    }

    /// 履歴選択クリアのコールバックを登録する
    func registerClearSelection(windowNumber: Int, callback: @escaping () -> Void) {
        clearSelectionCallbacks[windowNumber] = callback
        DebugLogger.log("📋 WindowCoordinator: registered clearSelection for window \(windowNumber)", level: .verbose)
    }

    /// メインビューフォーカスのコールバックを登録する
    func registerFocusMainView(windowNumber: Int, callback: @escaping () -> Void) {
        focusMainViewCallbacks[windowNumber] = callback
        DebugLogger.log("📋 WindowCoordinator: registered focusMainView for window \(windowNumber)", level: .verbose)
    }

    /// 登録を解除する
    func unregister(windowNumber: Int) {
        windowViewModels.removeValue(forKey: windowNumber)
        showHistoryGetters.removeValue(forKey: windowNumber)
        showHistorySetters.removeValue(forKey: windowNumber)
        searchFocusGetters.removeValue(forKey: windowNumber)
        searchFocusSetters.removeValue(forKey: windowNumber)
        clearSelectionCallbacks.removeValue(forKey: windowNumber)
        focusMainViewCallbacks.removeValue(forKey: windowNumber)
        DebugLogger.log("📋 WindowCoordinator: unregistered window \(windowNumber)", level: .verbose)
    }

    // MARK: - Access

    /// 現在アクティブなウィンドウのViewModelを取得する
    var keyWindowViewModel: BookViewModel? {
        // markAsActive で明示的に設定されたウィンドウを優先使用
        if let active = activeWindowNumber,
           let viewModel = windowViewModels[active] {
            DebugLogger.log("📋 keyWindowViewModel: active=\(active), hasOpenFile=\(viewModel.hasOpenFile)", level: .verbose)
            return viewModel
        }

        // フォールバック: NSApp.keyWindow を試す
        if let keyWindow = NSApp.keyWindow {
            let windowNumber = keyWindow.windowNumber
            if let viewModel = windowViewModels[windowNumber] {
                activeWindowNumber = windowNumber
                DebugLogger.log("📋 keyWindowViewModel: fallback keyWindow=\(windowNumber), hasOpenFile=\(viewModel.hasOpenFile)", level: .verbose)
                return viewModel
            }
        }

        // ウィンドウが1つだけ登録されている場合はそれを使用
        if windowViewModels.count == 1,
           let (windowNumber, viewModel) = windowViewModels.first {
            activeWindowNumber = windowNumber
            DebugLogger.log("📋 keyWindowViewModel: single window=\(windowNumber), hasOpenFile=\(viewModel.hasOpenFile)", level: .verbose)
            return viewModel
        }

        // ウィンドウが登録されている場合のみ警告（起動時は無視）
        if !windowViewModels.isEmpty {
            DebugLogger.log("⚠️ WindowCoordinator: No window available (active=\(activeWindowNumber ?? -1), registered=\(Array(windowViewModels.keys)))", level: .normal)
        }
        return nil
    }

    /// 現在のキーウィンドウのshowHistory値を取得する
    var keyWindowShowHistory: Bool? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return showHistoryGetters[keyWindow.windowNumber]?()
    }

    /// 現在のキーウィンドウのshowHistoryを設定する
    func setKeyWindowShowHistory(_ value: Bool) {
        guard let keyWindow = NSApp.keyWindow else { return }
        showHistorySetters[keyWindow.windowNumber]?(value)
    }

    /// 現在のキーウィンドウの検索フォーカス状態を取得する
    var keyWindowSearchFocused: Bool? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return searchFocusGetters[keyWindow.windowNumber]?()
    }

    /// 現在のキーウィンドウの検索フォーカスを設定する
    func setKeyWindowSearchFocus(_ value: Bool) {
        guard let keyWindow = NSApp.keyWindow else { return }
        searchFocusSetters[keyWindow.windowNumber]?(value)
    }

    /// ⌘Fショートカットの処理（履歴表示とフォーカスの制御）
    /// - 履歴非表示 → 履歴を表示（フォーカスはonChangeで設定される）
    /// - 履歴表示中、検索フォーカスなし → 検索フィールドにフォーカス（選択クリア）
    /// - 履歴表示中、検索フォーカスあり → 履歴を閉じる
    func toggleHistoryWithFocus() {
        guard let keyWindow = NSApp.keyWindow else { return }
        let windowNumber = keyWindow.windowNumber

        let showHistory = showHistoryGetters[windowNumber]?() ?? false
        let searchFocused = searchFocusGetters[windowNumber]?() ?? false

        if !showHistory {
            // 履歴非表示 → 表示する
            showHistorySetters[windowNumber]?(true)
        } else if !searchFocused {
            // 履歴表示中、検索フォーカスなし → 検索フィールドにフォーカス（選択クリア）
            clearSelectionCallbacks[windowNumber]?()
            searchFocusSetters[windowNumber]?(true)
        } else {
            // 履歴表示中、検索フォーカスあり → 閉じてメインビューにフォーカス
            showHistorySetters[windowNumber]?(false)
            focusMainViewCallbacks[windowNumber]?()
        }
    }

    /// キーウィンドウがファイルを開いているかどうか
    var keyWindowHasOpenFile: Bool {
        keyWindowViewModel?.hasOpenFile ?? false
    }

    /// フォーカス通知を送信すべきかチェック（デバウンス）
    /// - Returns: trueなら通知を送信すべき、falseなら無視すべき
    func shouldPostFocusNotification(for windowNumber: Int) -> Bool {
        let now = Date()
        if let lastTime = lastFocusNotificationTime[windowNumber] {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < focusDebounceInterval {
                DebugLogger.log("⏱️ Debounce: window \(windowNumber) skipped (elapsed: \(Int(elapsed * 1000))ms < \(Int(focusDebounceInterval * 1000))ms)", level: .normal)
                return false
            }
        }
        lastFocusNotificationTime[windowNumber] = now
        return true
    }

    /// 現在の登録状態をログ出力（デバッグ用）
    func logCurrentState() {
        let keyWindowNum = NSApp.keyWindow?.windowNumber
        let registeredWindows = Array(windowViewModels.keys).sorted()
        let hasOpenFiles = windowViewModels.map { ($0.key, $0.value.hasOpenFile) }
        DebugLogger.log("📋 WindowCoordinator state: active=\(activeWindowNumber ?? -1), keyWindow=\(keyWindowNum ?? -1), registered=\(registeredWindows), hasOpenFile=\(hasOpenFiles)", level: .verbose)
    }
}
