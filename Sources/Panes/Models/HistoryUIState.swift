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

    /// キーボードナビゲーション選択（アンカー兼用）
    var selectedItem: SelectableHistoryItem?

    /// 複数選択中のアイテム
    var selectedItems: Set<SelectableHistoryItem> = []

    /// Shift+クリック用の起点
    var selectionAnchor: SelectableHistoryItem?

    /// 表示中アイテム一覧（キーボードナビゲーション用）
    var visibleItems: [SelectableHistoryItem] = []

    // MARK: - 拡張表示

    /// 展開中のアイテムID
    var expandedItems: Set<String> = []

    /// トグルアイコンクリック（排他的: 他を全て閉じる）
    func toggleExpand(_ id: String) {
        if expandedItems.contains(id) {
            expandedItems.remove(id)
        } else {
            expandedItems = [id]
        }
    }

    /// Shift+クリック（個別トグル: 他はそのまま）
    func toggleExpandKeeping(_ id: String) {
        if expandedItems.contains(id) {
            expandedItems.remove(id)
        } else {
            expandedItems.insert(id)
        }
    }

    func isExpanded(_ id: String) -> Bool {
        expandedItems.contains(id)
    }

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

    /// 通常クリック（単一選択、既存選択をクリア）
    func select(_ item: SelectableHistoryItem) {
        selectedItems = [item]
        selectedItem = item
        selectionAnchor = item
    }

    /// Cmd+クリック（トグル）
    func toggleSelection(_ item: SelectableHistoryItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
            selectedItem = selectedItems.first
        } else {
            selectedItems.insert(item)
            selectedItem = item
        }
        selectionAnchor = item
    }

    /// キーボード用トグル（カーソル位置を維持）
    func toggleSelectionKeepingCursor(_ item: SelectableHistoryItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }

    /// Shift+クリック（範囲選択）
    func extendSelection(to item: SelectableHistoryItem) {
        guard let anchor = selectionAnchor ?? selectedItem,
              let anchorIdx = visibleItems.firstIndex(where: { $0.id == anchor.id }),
              let targetIdx = visibleItems.firstIndex(where: { $0.id == item.id })
        else { select(item); return }
        let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
        selectedItems = Set(visibleItems[range])
        selectedItem = item
        // selectionAnchor は維持（連続Shift+クリック対応）
    }

    /// 全選択
    func selectAll() {
        selectedItems = Set(visibleItems)
    }

    /// 選択判定
    func isSelected(_ item: SelectableHistoryItem) -> Bool {
        selectedItems.contains(item)
    }

    /// カーソルのみ（選択されていないがカーソルが指している）判定
    func isCursorOnly(_ item: SelectableHistoryItem) -> Bool {
        selectedItem == item && !selectedItems.contains(item)
    }

    /// 選択をクリア
    func clearSelection() {
        selectedItem = nil
        selectedItems.removeAll()
        selectionAnchor = nil
    }

    /// スクロールトリガーをインクリメント
    func incrementScrollTrigger() {
        scrollTrigger += 1
    }

    /// 履歴リストの選択を指定オフセット分移動する
    func selectItem(byOffset offset: Int, extend: Bool = false) {
        if let current = selectedItem,
           let currentIndex = visibleItems.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(visibleItems.count - 1, currentIndex + offset))
            let item = visibleItems[newIndex]
            if extend {
                extendSelection(to: item)
            } else {
                selectedItem = item
                selectedItems = [item]
                selectionAnchor = item
            }
        } else {
            if let first = visibleItems.first {
                selectedItem = first
                selectedItems = [first]
                selectionAnchor = first
            }
        }
    }

    /// 履歴を閉じる（状態をリセット）
    func closeHistory() {
        showHistory = false
        selectedItem = nil
        selectedItems.removeAll()
        selectionAnchor = nil
        isSearchFocused = false
        isShowingSuggestions = false
    }
}
