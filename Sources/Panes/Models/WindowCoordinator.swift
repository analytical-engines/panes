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

    private init() {}

    // MARK: - Registration

    /// ViewModelを登録する
    func register(windowNumber: Int, viewModel: BookViewModel) {
        windowViewModels[windowNumber] = viewModel
        DebugLogger.log("📋 WindowCoordinator: registered viewModel for window \(windowNumber)", level: .verbose)
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

    /// 現在のキーウィンドウのViewModelを取得する
    var keyWindowViewModel: BookViewModel? {
        guard let keyWindow = NSApp.keyWindow else { return nil }
        return windowViewModels[keyWindow.windowNumber]
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
}
