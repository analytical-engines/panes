import Foundation

/// 見開きモード中の単ページ表示時の配置
enum SinglePageAlignment: String, Codable {
    case right      // 右側表示
    case left       // 左側表示
    case center     // センタリング（ウィンドウフィッティング）
}

/// ページごとの表示設定
struct PageDisplaySettings: Codable {
    /// 強制的に単ページ表示するページのインデックス集合
    var forceSinglePageIndices: Set<Int> = []

    /// アスペクト比判定が完了したページのインデックス集合
    var checkedPageIndices: Set<Int> = []

    /// ページごとの単ページ表示時の配置設定
    var pageAlignments: [Int: SinglePageAlignment] = [:]

    /// 指定したページが単ページ表示かどうか
    func isForcedSinglePage(_ index: Int) -> Bool {
        return forceSinglePageIndices.contains(index)
    }

    /// 指定したページがアスペクト比判定済みかどうか
    func isPageChecked(_ index: Int) -> Bool {
        return checkedPageIndices.contains(index)
    }

    /// ページを判定済みとしてマーク
    mutating func markAsChecked(_ index: Int) {
        checkedPageIndices.insert(index)
    }

    /// 単ページ表示を切り替え
    mutating func toggleForceSinglePage(at index: Int) {
        if forceSinglePageIndices.contains(index) {
            forceSinglePageIndices.remove(index)
        } else {
            forceSinglePageIndices.insert(index)
        }
        // 手動で設定した場合も判定済みとしてマーク
        checkedPageIndices.insert(index)
    }

    /// 指定したインデックスまでの単ページ属性の累積が奇数かどうか
    /// （見開きのシフト判定に使用）
    func hasOddSinglePagesUpTo(_ index: Int) -> Bool {
        let count = forceSinglePageIndices.filter { $0 < index }.count
        return count % 2 == 1
    }

    /// 指定したページの配置設定を取得
    func alignment(for index: Int) -> SinglePageAlignment? {
        return pageAlignments[index]
    }

    /// 指定したページの配置設定を変更
    mutating func setAlignment(_ alignment: SinglePageAlignment, for index: Int) {
        pageAlignments[index] = alignment
    }
}
