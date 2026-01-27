import SwiftUI

/// 履歴・検索UI関連の状態を管理するクラス
/// ContentViewごとに独立したインスタンスを持つ（ウィンドウローカル）
@Observable
final class HistoryUIState {
    // MARK: - 表示状態

    /// 履歴オーバーレイ表示
    var showHistory: Bool = true

    /// 検索フィールド表示（常に表示されるため主にフォーカス制御用）
    var showHistoryFilter: Bool = false

    /// 選択中タブ（後方互換性のため残す）
    var selectedTab: HistoryTab = .archives

    // MARK: - 検索状態

    /// 検索フィルターテキスト
    var filterText: String = ""

    /// 検索フィールドフォーカス状態（@FocusStateと同期）
    var isSearchFocused: Bool = false

    /// オートコンプリート候補表示中
    var isShowingSuggestions: Bool = false

    // MARK: - 選択状態

    /// キーボードナビゲーション選択
    var selectedItem: SelectableHistoryItem?

    /// 表示中アイテム一覧（キーボードナビゲーション用）
    var visibleItems: [SelectableHistoryItem] = []

    // MARK: - スクロール復元

    /// 最後に開いた書庫エントリのID
    var lastOpenedArchiveId: String?

    /// 最後に開いた画像エントリのID
    var lastOpenedImageId: String?

    /// スクロール強制更新用トリガー
    var scrollTrigger: Int = 0

    // MARK: - 計算プロパティ

    /// 履歴ナビゲーションが可能な状態か（履歴表示中かつ履歴あり）
    var canNavigateHistory: Bool {
        showHistory && !visibleItems.isEmpty
    }

    /// 履歴リストのキーボードナビゲーションが可能な状態か（候補表示中・検索フォーカス中を除く）
    var canNavigateHistoryList: Bool {
        canNavigateHistory && !isShowingSuggestions && !isSearchFocused
    }

    // MARK: - 便利メソッド

    /// 選択をクリア
    func clearSelection() {
        selectedItem = nil
    }

    /// スクロールトリガーをインクリメント
    func incrementScrollTrigger() {
        scrollTrigger += 1
    }

    /// 履歴リストの選択を指定オフセット分移動する
    func selectItem(byOffset offset: Int) {
        if let current = selectedItem,
           let currentIndex = visibleItems.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(visibleItems.count - 1, currentIndex + offset))
            selectedItem = visibleItems[newIndex]
        } else {
            selectedItem = visibleItems.first
        }
    }

    /// 履歴を閉じる（状態をリセット）
    func closeHistory() {
        showHistory = false
        selectedItem = nil
        isSearchFocused = false
        isShowingSuggestions = false
    }
}
