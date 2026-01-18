import Foundation
import AppKit
import Observation

/// カスタムショートカットで実行可能なアクション
enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    var id: String { rawValue }
    case nextPage = "nextPage"
    case previousPage = "previousPage"
    case skipForward = "skipForward"
    case skipBackward = "skipBackward"
    case goToFirstPage = "goToFirstPage"
    case goToLastPage = "goToLastPage"
    case toggleFullScreen = "toggleFullScreen"
    case toggleViewMode = "toggleViewMode"
    case toggleReadingDirection = "toggleReadingDirection"
    case zoomIn = "zoomIn"
    case zoomOut = "zoomOut"
    case closeFile = "closeFile"
    case fitToWindow = "fitToWindow"
    case fitToOriginalSize = "fitToOriginalSize"

    /// 表示名
    var displayName: String {
        switch self {
        case .nextPage: return L("shortcut_next_page")
        case .previousPage: return L("shortcut_previous_page")
        case .skipForward: return L("shortcut_skip_forward")
        case .skipBackward: return L("shortcut_skip_backward")
        case .goToFirstPage: return L("shortcut_first_page")
        case .goToLastPage: return L("shortcut_last_page")
        case .toggleFullScreen: return L("shortcut_fullscreen")
        case .toggleViewMode: return L("shortcut_view_mode")
        case .toggleReadingDirection: return L("shortcut_reading_direction")
        case .zoomIn: return L("shortcut_zoom_in")
        case .zoomOut: return L("shortcut_zoom_out")
        case .closeFile: return L("shortcut_close_file")
        case .fitToWindow: return L("shortcut_fit_to_window")
        case .fitToOriginalSize: return L("shortcut_fit_to_original")
        }
    }

    /// 固定ショートカット（メニューバー等で定義済み、変更不可）
    var hardcodedShortcuts: [String] {
        switch self {
        case .nextPage: return []
        case .previousPage: return ["⇧Tab"]
        case .skipForward: return []
        case .skipBackward: return []
        case .goToFirstPage: return []
        case .goToLastPage: return []
        case .toggleFullScreen: return []
        case .toggleViewMode: return ["⇧⌘M"]
        case .toggleReadingDirection: return ["⇧⌘R"]
        case .zoomIn: return ["⌘+"]
        case .zoomOut: return ["⌘-"]
        case .closeFile: return ["⇧⌘W"]
        case .fitToWindow: return []
        case .fitToOriginalSize: return []
        }
    }
}

/// キーバインディング（キー + モディファイア）
struct KeyBinding: Codable, Equatable, Hashable {
    /// キーコード（NSEvent.keyCode）
    let keyCode: UInt16

    /// 表示用のキー文字（例: "J", "Space", "Tab"）
    let keyDisplay: String

    /// モディファイアフラグ
    let modifiers: ModifierFlags

    /// モディファイアフラグ（Codable対応のため独自定義）
    struct ModifierFlags: OptionSet, Codable, Equatable, Hashable {
        let rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        static let shift = ModifierFlags(rawValue: 1 << 0)
        static let control = ModifierFlags(rawValue: 1 << 1)
        static let option = ModifierFlags(rawValue: 1 << 2)
        static let command = ModifierFlags(rawValue: 1 << 3)

        /// NSEvent.ModifierFlagsから変換
        init(from nsFlags: NSEvent.ModifierFlags) {
            var flags: ModifierFlags = []
            if nsFlags.contains(.shift) { flags.insert(.shift) }
            if nsFlags.contains(.control) { flags.insert(.control) }
            if nsFlags.contains(.option) { flags.insert(.option) }
            if nsFlags.contains(.command) { flags.insert(.command) }
            self = flags
        }

        /// NSEvent.ModifierFlagsに変換
        func toNSEventModifierFlags() -> NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.shift) { flags.insert(.shift) }
            if contains(.control) { flags.insert(.control) }
            if contains(.option) { flags.insert(.option) }
            if contains(.command) { flags.insert(.command) }
            return flags
        }

        /// 表示用文字列
        var displayString: String {
            var parts: [String] = []
            if contains(.control) { parts.append("^") }
            if contains(.option) { parts.append("⌥") }
            if contains(.shift) { parts.append("⇧") }
            if contains(.command) { parts.append("⌘") }
            return parts.joined()
        }
    }

    /// NSEventからKeyBindingを生成
    init(from event: NSEvent) {
        self.keyCode = event.keyCode
        self.keyDisplay = Self.keyDisplayString(for: event)
        self.modifiers = ModifierFlags(from: event.modifierFlags)
    }

    /// 直接指定で生成
    init(keyCode: UInt16, keyDisplay: String, modifiers: ModifierFlags = []) {
        self.keyCode = keyCode
        self.keyDisplay = keyDisplay
        self.modifiers = modifiers
    }

    /// NSEventがこのKeyBindingにマッチするか
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }

        let eventModifiers = ModifierFlags(from: event.modifierFlags)
        return eventModifiers == modifiers
    }

    /// 表示用文字列（例: "⇧J", "⌘⌥K"）
    var displayString: String {
        return modifiers.displayString + keyDisplay
    }

    /// キーコードから表示文字列を生成
    private static func keyDisplayString(for event: NSEvent) -> String {
        // 特殊キーの処理
        switch event.keyCode {
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Esc"
        case 36: return "Return"
        case 76: return "Enter"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "PageUp"
        case 121: return "PageDown"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            // 通常の文字キー
            if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
                return chars
            }
            return "Key\(event.keyCode)"
        }
    }
}

/// カスタムショートカットの管理
@MainActor
@Observable
final class CustomShortcutManager {
    /// シングルトン
    static let shared = CustomShortcutManager()

    /// アクションごとのキーバインディング（複数可）
    private(set) var shortcuts: [ShortcutAction: [KeyBinding]] = [:]

    private let userDefaultsKey = "customKeyboardShortcuts"

    private init() {
        loadShortcuts()
    }

    /// ショートカットを追加
    func addShortcut(_ binding: KeyBinding, for action: ShortcutAction) {
        if shortcuts[action] == nil {
            shortcuts[action] = []
        }
        // 重複チェック
        if !shortcuts[action]!.contains(binding) {
            shortcuts[action]!.append(binding)
            saveShortcuts()
        }
    }

    /// ショートカットを削除
    func removeShortcut(_ binding: KeyBinding, from action: ShortcutAction) {
        shortcuts[action]?.removeAll { $0 == binding }
        saveShortcuts()
    }

    /// アクションの全ショートカットを削除
    func removeAllShortcuts(for action: ShortcutAction) {
        shortcuts[action] = nil
        saveShortcuts()
    }

    /// NSEventに対応するアクションを検索
    func findAction(for event: NSEvent) -> ShortcutAction? {
        for (action, bindings) in shortcuts {
            for binding in bindings {
                if binding.matches(event) {
                    return action
                }
            }
        }
        return nil
    }

    /// KeyBindingに対応するアクションを検索（衝突チェック用）
    func findAction(for binding: KeyBinding) -> ShortcutAction? {
        for (action, bindings) in shortcuts {
            if bindings.contains(binding) {
                return action
            }
        }
        return nil
    }

    /// 保存
    private func saveShortcuts() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// 読み込み
    private func loadShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        let decoder = JSONDecoder()
        if let loaded = try? decoder.decode([ShortcutAction: [KeyBinding]].self, from: data) {
            shortcuts = loaded
        }
    }

    /// 全カスタムショートカットをクリア
    func clearAll() {
        shortcuts = [:]
        saveShortcuts()
    }
}

/// ハードコーディングされた（変更不可の）ショートカット
struct HardcodedShortcut {
    let displayName: String
    let keyDisplay: String

    /// キーコードとモディファイアからハードコーディングされたショートカットを検索
    static func find(keyCode: UInt16, modifiers: KeyBinding.ModifierFlags) -> HardcodedShortcut? {
        // ⇧⌘W (keyCode 13 = W)
        if keyCode == 13 && modifiers == [.shift, .command] {
            return HardcodedShortcut(displayName: L("menu_close_file"), keyDisplay: "⇧⌘W")
        }
        // ⇧⌘M (keyCode 46 = M)
        if keyCode == 46 && modifiers == [.shift, .command] {
            return HardcodedShortcut(displayName: L("shortcut_view_mode"), keyDisplay: "⇧⌘M")
        }
        // ⌘F (keyCode 3 = F) - 履歴表示トグル
        if keyCode == 3 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("menu_show_history"), keyDisplay: "⌘F")
        }
        // ⌘+ (keyCode 24 = +/=)
        if keyCode == 24 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("shortcut_zoom_in"), keyDisplay: "⌘+")
        }
        // ⌘- (keyCode 27 = -)
        if keyCode == 27 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("shortcut_zoom_out"), keyDisplay: "⌘-")
        }
        // ⇧⌘R (keyCode 15 = R)
        if keyCode == 15 && modifiers == [.shift, .command] {
            return HardcodedShortcut(displayName: L("shortcut_reading_direction"), keyDisplay: "⇧⌘R")
        }
        // ⌘B (keyCode 11 = B)
        if keyCode == 11 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("menu_show_status_bar"), keyDisplay: "⌘B")
        }
        // ⇧⌘S (keyCode 1 = S)
        if keyCode == 1 && modifiers == [.shift, .command] {
            return HardcodedShortcut(displayName: L("menu_save_session"), keyDisplay: "⇧⌘S")
        }
        // ⇧Tab (keyCode 48 = Tab)
        if keyCode == 48 && modifiers == [.shift] {
            return HardcodedShortcut(displayName: L("shortcut_previous_page"), keyDisplay: "⇧Tab")
        }

        // システムショートカット
        // ⌘Q (keyCode 12 = Q) - Quit
        if keyCode == 12 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_quit"), keyDisplay: "⌘Q")
        }
        // ⌘W (keyCode 13 = W) - Close Window
        if keyCode == 13 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_close"), keyDisplay: "⌘W")
        }
        // ⌘C (keyCode 8 = C) - Copy
        if keyCode == 8 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_copy"), keyDisplay: "⌘C")
        }
        // ⌘V (keyCode 9 = V) - Paste
        if keyCode == 9 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_paste"), keyDisplay: "⌘V")
        }
        // ⌘X (keyCode 7 = X) - Cut
        if keyCode == 7 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_cut"), keyDisplay: "⌘X")
        }
        // ⌘A (keyCode 0 = A) - Select All
        if keyCode == 0 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_select_all"), keyDisplay: "⌘A")
        }
        // ⌘Z (keyCode 6 = Z) - Undo
        if keyCode == 6 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_undo"), keyDisplay: "⌘Z")
        }
        // ⇧⌘Z (keyCode 6 = Z) - Redo
        if keyCode == 6 && modifiers == [.shift, .command] {
            return HardcodedShortcut(displayName: L("system_shortcut_redo"), keyDisplay: "⇧⌘Z")
        }
        // ⌘, (keyCode 43 = ,) - Settings
        if keyCode == 43 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_settings"), keyDisplay: "⌘,")
        }
        // ⌘H (keyCode 4 = H) - Hide
        if keyCode == 4 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_hide"), keyDisplay: "⌘H")
        }
        // ⌘M (keyCode 46 = M) - Minimize
        if keyCode == 46 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_minimize"), keyDisplay: "⌘M")
        }
        // ⌘N (keyCode 45 = N) - New
        if keyCode == 45 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_new"), keyDisplay: "⌘N")
        }
        // ⌘O (keyCode 31 = O) - Open
        if keyCode == 31 && modifiers == [.command] {
            return HardcodedShortcut(displayName: L("system_shortcut_open"), keyDisplay: "⌘O")
        }

        return nil
    }

    /// KeyBindingからハードコーディングされたショートカットを検索
    static func find(for binding: KeyBinding) -> HardcodedShortcut? {
        return find(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }
}
