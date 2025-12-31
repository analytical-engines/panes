import Foundation
import SwiftUI

/// 表示順序におけるページデータ
/// ソースインデックスと表示位置のマッピングを管理
struct PageData {
    /// このページのソース画像インデックス（ImageSource内での位置）
    let sourceIndex: Int
}

/// 見開きモード中の単ページ表示時の配置
enum SinglePageAlignment: String, Codable {
    case right      // 右側表示
    case left       // 左側表示
    case center     // センタリング（ウィンドウフィッティング）
}

/// 画像のフィッティングモード
enum FittingMode: String, Codable, CaseIterable {
    case window         // ウィンドウサイズにフィッティング（アスペクト比維持、全体が収まる）
    case height         // ウィンドウの縦サイズにフィッティング（横はスクロール可能）
    case width          // ウィンドウの横サイズにフィッティング（縦はスクロール可能）
    case originalSize   // 等倍表示（1:1ピクセル、スクロール可能）
}

/// 画像の補間アルゴリズム
enum InterpolationMode: String, Codable, CaseIterable {
    case nearestNeighbor    // 最近傍法（ピクセルアート向け）
    case bilinear           // バイリニア補間
    case highQuality        // 高品質（デフォルト）

    /// SwiftUIのImage.Interpolationに変換
    var swiftUIInterpolation: SwiftUI.Image.Interpolation {
        switch self {
        case .nearestNeighbor: return .none
        case .bilinear: return .medium
        case .highQuality: return .high
        }
    }
}

/// 画像の回転角度（90度単位）
enum ImageRotation: Int, Codable {
    case none = 0       // 回転なし
    case cw90 = 90      // 時計回り90度
    case cw180 = 180    // 180度
    case cw270 = 270    // 時計回り270度（反時計回り90度）

    /// 時計回りに90度回転
    func rotatedClockwise() -> ImageRotation {
        switch self {
        case .none: return .cw90
        case .cw90: return .cw180
        case .cw180: return .cw270
        case .cw270: return .none
        }
    }

    /// 反時計回りに90度回転
    func rotatedCounterClockwise() -> ImageRotation {
        switch self {
        case .none: return .cw270
        case .cw90: return .none
        case .cw180: return .cw90
        case .cw270: return .cw180
        }
    }

    /// 90度または270度回転の場合、アスペクト比が入れ替わる
    var swapsAspectRatio: Bool {
        return self == .cw90 || self == .cw270
    }
}

/// 画像の反転設定
struct ImageFlip: Codable, Equatable {
    var horizontal: Bool = false  // 水平反転（左右反転）
    var vertical: Bool = false    // 垂直反転（上下反転）

    static let none = ImageFlip()
}

/// ページごとの表示設定
struct PageDisplaySettings: Codable {
    /// ユーザーが手動で単ページ表示を設定したページのインデックス集合
    var userForcedSinglePageIndices: Set<Int> = []

    /// 自動検出により横長と判定されたページのインデックス集合
    var autoDetectedLandscapeIndices: Set<Int> = []

    /// アスペクト比判定が完了したページのインデックス集合（回転考慮後）
    var checkedPageIndices: Set<Int> = []

    /// 非表示（スキップ）するページのインデックス集合
    var hiddenPageIndices: Set<Int> = []

    /// ページごとの単ページ表示時の配置設定
    var pageAlignments: [Int: SinglePageAlignment] = [:]

    /// ページごとの回転設定
    var pageRotations: [Int: ImageRotation] = [:]

    /// ページごとの反転設定
    var pageFlips: [Int: ImageFlip] = [:]

    /// カスタム表示順序（ソースインデックスの配列、空の場合はデフォルト順序）
    var customDisplayOrder: [Int] = []

    /// 壊れた画像をランドスケープ（横長）プレースホルダーで表示するページのインデックス集合
    var landscapePlaceholderIndices: Set<Int> = []

    // MARK: - 後方互換性のためのCodable対応

    enum CodingKeys: String, CodingKey {
        case userForcedSinglePageIndices
        case autoDetectedLandscapeIndices
        case checkedPageIndices
        case hiddenPageIndices
        case pageAlignments
        case pageRotations
        case pageFlips
        case customDisplayOrder
        case landscapePlaceholderIndices
        // 旧キー
        case forceSinglePageIndices
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 新フォーマットを試す
        if let userForced = try? container.decode(Set<Int>.self, forKey: .userForcedSinglePageIndices) {
            userForcedSinglePageIndices = userForced
            autoDetectedLandscapeIndices = (try? container.decode(Set<Int>.self, forKey: .autoDetectedLandscapeIndices)) ?? []
        } else if let oldForced = try? container.decode(Set<Int>.self, forKey: .forceSinglePageIndices) {
            // 旧フォーマットからの移行：全てユーザー設定として扱う
            userForcedSinglePageIndices = oldForced
            autoDetectedLandscapeIndices = []
        }

        checkedPageIndices = (try? container.decode(Set<Int>.self, forKey: .checkedPageIndices)) ?? []
        hiddenPageIndices = (try? container.decode(Set<Int>.self, forKey: .hiddenPageIndices)) ?? []
        pageAlignments = (try? container.decode([Int: SinglePageAlignment].self, forKey: .pageAlignments)) ?? [:]
        pageRotations = (try? container.decode([Int: ImageRotation].self, forKey: .pageRotations)) ?? [:]
        pageFlips = (try? container.decode([Int: ImageFlip].self, forKey: .pageFlips)) ?? [:]
        customDisplayOrder = (try? container.decode([Int].self, forKey: .customDisplayOrder)) ?? []
        landscapePlaceholderIndices = (try? container.decode(Set<Int>.self, forKey: .landscapePlaceholderIndices)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userForcedSinglePageIndices, forKey: .userForcedSinglePageIndices)
        try container.encode(autoDetectedLandscapeIndices, forKey: .autoDetectedLandscapeIndices)
        try container.encode(checkedPageIndices, forKey: .checkedPageIndices)
        try container.encode(hiddenPageIndices, forKey: .hiddenPageIndices)
        try container.encode(pageAlignments, forKey: .pageAlignments)
        try container.encode(pageRotations, forKey: .pageRotations)
        try container.encode(pageFlips, forKey: .pageFlips)
        try container.encode(customDisplayOrder, forKey: .customDisplayOrder)
        try container.encode(landscapePlaceholderIndices, forKey: .landscapePlaceholderIndices)
    }

    // MARK: - 単ページ判定

    /// 指定したページが単ページ表示かどうか（ユーザー設定または自動検出）
    func isForcedSinglePage(_ index: Int) -> Bool {
        return userForcedSinglePageIndices.contains(index) || autoDetectedLandscapeIndices.contains(index)
    }

    /// 指定したページがユーザーによって手動設定されているかどうか
    func isUserForcedSinglePage(_ index: Int) -> Bool {
        return userForcedSinglePageIndices.contains(index)
    }

    /// 指定したページがアスペクト比判定済みかどうか
    func isPageChecked(_ index: Int) -> Bool {
        return checkedPageIndices.contains(index)
    }

    /// ページを判定済みとしてマーク
    mutating func markAsChecked(_ index: Int) {
        checkedPageIndices.insert(index)
    }

    /// 自動検出された横長属性を設定
    mutating func setAutoDetectedLandscape(_ index: Int) {
        autoDetectedLandscapeIndices.insert(index)
    }

    /// 指定ページの自動検出フラグをクリア（回転変更時に呼ぶ）
    mutating func clearAutoDetection(at index: Int) {
        autoDetectedLandscapeIndices.remove(index)
        checkedPageIndices.remove(index)
    }

    /// 全ページの自動検出をクリア（閾値変更時に呼ぶ）
    /// ユーザーが手動設定した属性は保持する
    mutating func clearAllAutoDetection() {
        autoDetectedLandscapeIndices.removeAll()
        checkedPageIndices.removeAll()
    }

    /// 単ページ表示を切り替え（ユーザー手動設定）
    mutating func toggleForceSinglePage(at index: Int) {
        if userForcedSinglePageIndices.contains(index) {
            userForcedSinglePageIndices.remove(index)
        } else {
            userForcedSinglePageIndices.insert(index)
            // ユーザーが手動設定した場合、自動検出からは除外
            autoDetectedLandscapeIndices.remove(index)
        }
    }

    /// 単ページ表示属性を設定（ユーザー手動設定）
    mutating func setForceSinglePage(at index: Int, forced: Bool) {
        if forced {
            userForcedSinglePageIndices.insert(index)
            autoDetectedLandscapeIndices.remove(index)
        } else {
            userForcedSinglePageIndices.remove(index)
        }
    }

    /// 指定したインデックスまでの単ページ属性の累積が奇数かどうか
    /// （見開きのシフト判定に使用）
    func hasOddSinglePagesUpTo(_ index: Int) -> Bool {
        let userCount = userForcedSinglePageIndices.filter { $0 < index }.count
        let autoCount = autoDetectedLandscapeIndices.filter { $0 < index }.count
        return (userCount + autoCount) % 2 == 1
    }

    /// 指定したページの配置設定を取得
    func alignment(for index: Int) -> SinglePageAlignment? {
        return pageAlignments[index]
    }

    /// 指定したページの配置設定を変更
    mutating func setAlignment(_ alignment: SinglePageAlignment, for index: Int) {
        pageAlignments[index] = alignment
    }

    // MARK: - 回転設定

    /// 指定したページの回転設定を取得
    func rotation(for index: Int) -> ImageRotation {
        return pageRotations[index] ?? .none
    }

    /// 指定したページを時計回りに90度回転
    mutating func rotateClockwise(at index: Int) {
        let current = rotation(for: index)
        let newRotation = current.rotatedClockwise()
        if newRotation == .none {
            pageRotations.removeValue(forKey: index)
        } else {
            pageRotations[index] = newRotation
        }
        // 回転変更により実効アスペクト比が変わるため、自動検出をクリア
        clearAutoDetection(at: index)
    }

    /// 指定したページを反時計回りに90度回転
    mutating func rotateCounterClockwise(at index: Int) {
        let current = rotation(for: index)
        let newRotation = current.rotatedCounterClockwise()
        if newRotation == .none {
            pageRotations.removeValue(forKey: index)
        } else {
            pageRotations[index] = newRotation
        }
        // 回転変更により実効アスペクト比が変わるため、自動検出をクリア
        clearAutoDetection(at: index)
    }

    /// 指定したページを180度回転
    mutating func rotate180(at index: Int) {
        let current = rotation(for: index)
        let newRotation: ImageRotation
        switch current {
        case .none: newRotation = .cw180
        case .cw90: newRotation = .cw270
        case .cw180: newRotation = .none
        case .cw270: newRotation = .cw90
        }
        if newRotation == .none {
            pageRotations.removeValue(forKey: index)
        } else {
            pageRotations[index] = newRotation
        }
        // 180度回転はアスペクト比を変えないが、一貫性のためクリア
        // （実際には再判定しても同じ結果になる）
    }

    // MARK: - 反転設定

    /// 指定したページの反転設定を取得
    func flip(for index: Int) -> ImageFlip {
        return pageFlips[index] ?? .none
    }

    /// 指定したページの水平反転を切り替え
    mutating func toggleHorizontalFlip(at index: Int) {
        var current = flip(for: index)
        current.horizontal.toggle()
        if current == .none {
            pageFlips.removeValue(forKey: index)
        } else {
            pageFlips[index] = current
        }
    }

    /// 指定したページの垂直反転を切り替え
    mutating func toggleVerticalFlip(at index: Int) {
        var current = flip(for: index)
        current.vertical.toggle()
        if current == .none {
            pageFlips.removeValue(forKey: index)
        } else {
            pageFlips[index] = current
        }
    }

    // MARK: - 非表示設定

    /// 指定したページが非表示かどうか
    func isHidden(_ index: Int) -> Bool {
        return hiddenPageIndices.contains(index)
    }

    /// 指定したページの非表示設定を切り替え
    mutating func toggleHidden(at index: Int) {
        if hiddenPageIndices.contains(index) {
            hiddenPageIndices.remove(index)
        } else {
            hiddenPageIndices.insert(index)
        }
    }

    /// 非表示ページ数
    var hiddenPageCount: Int {
        return hiddenPageIndices.count
    }

    // MARK: - カスタム表示順序

    /// カスタム表示順序が設定されているかどうか
    var hasCustomDisplayOrder: Bool {
        return !customDisplayOrder.isEmpty
    }

    /// カスタム表示順序を設定
    mutating func setCustomDisplayOrder(_ order: [Int]) {
        customDisplayOrder = order
    }

    /// カスタム表示順序をクリア
    mutating func clearCustomDisplayOrder() {
        customDisplayOrder = []
    }

    // MARK: - 壊れた画像のプレースホルダー設定

    /// 指定したページがランドスケーププレースホルダーを使用するかどうか
    func isLandscapePlaceholder(_ index: Int) -> Bool {
        return landscapePlaceholderIndices.contains(index)
    }

    /// 指定したページのプレースホルダー縦横を切り替え
    mutating func togglePlaceholderOrientation(at index: Int) {
        if landscapePlaceholderIndices.contains(index) {
            landscapePlaceholderIndices.remove(index)
        } else {
            landscapePlaceholderIndices.insert(index)
        }
    }
}
