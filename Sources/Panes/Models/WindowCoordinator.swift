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

    /// 現在アクティブなウィンドウ番号（markAsActiveで明示的に設定）
    private var activeWindowNumber: Int?

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

    /// 登録を解除する
    func unregister(windowNumber: Int) {
        windowViewModels.removeValue(forKey: windowNumber)
        showHistoryGetters.removeValue(forKey: windowNumber)
        showHistorySetters.removeValue(forKey: windowNumber)
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

    /// キーウィンドウがファイルを開いているかどうか
    var keyWindowHasOpenFile: Bool {
        keyWindowViewModel?.hasOpenFile ?? false
    }

    /// 現在の登録状態をログ出力（デバッグ用）
    func logCurrentState() {
        let keyWindowNum = NSApp.keyWindow?.windowNumber
        let registeredWindows = Array(windowViewModels.keys).sorted()
        let hasOpenFiles = windowViewModels.map { ($0.key, $0.value.hasOpenFile) }
        DebugLogger.log("📋 WindowCoordinator state: active=\(activeWindowNumber ?? -1), keyWindow=\(keyWindowNum ?? -1), registered=\(registeredWindows), hasOpenFile=\(hasOpenFiles)", level: .verbose)
    }
}
