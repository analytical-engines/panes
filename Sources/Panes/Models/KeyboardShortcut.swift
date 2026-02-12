import Foundation
import AppKit
import SwiftUI
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
    case shiftPageForward = "shiftPageForward"
    case shiftPageBackward = "shiftPageBackward"
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
        case .shiftPageForward: return L("shortcut_shift_page_forward")
        case .shiftPageBackward: return L("shortcut_shift_page_backward")
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

    /// デフォルトバインディング（初期値、ユーザーが削除・変更可能）
    var defaultBindings: [KeyBinding] {
        switch self {
        case .nextPage: return [
            KeyBinding(keyCode: 49, keyDisplay: "Space", modifiers: []),
        ]
        case .previousPage: return [
            KeyBinding(keyCode: 49, keyDisplay: "Space", modifiers: .shift),
        ]
        case .skipForward: return [
            KeyBinding(keyCode: 48, keyDisplay: "Tab", modifiers: []),
        ]
        case .skipBackward: return [
            KeyBinding(keyCode: 48, keyDisplay: "Tab", modifiers: .shift),
        ]
        case .goToFirstPage: return [
            KeyBinding(keyCode: 115, keyDisplay: "Home", modifiers: []),
        ]
        case .goToLastPage: return [
            KeyBinding(keyCode: 119, keyDisplay: "End", modifiers: []),
        ]
        case .toggleFullScreen: return [
            KeyBinding(keyCode: 3, keyDisplay: "F", modifiers: [.control, .command]),
        ]
        case .toggleViewMode: return []
        case .zoomIn: return [
            KeyBinding(keyCode: 24, keyDisplay: "+", modifiers: [.command]),
        ]
        case .zoomOut: return [
            KeyBinding(keyCode: 27, keyDisplay: "-", modifiers: [.command]),
        ]
        case .closeFile: return [
            KeyBinding(keyCode: 13, keyDisplay: "W", modifiers: [.shift, .command]),
        ]
        default: return []
        }
    }

    /// メニュー表示用: このアクションがメニュー項目に対応する場合のデフォルトKeyEquivalent
    var menuKeyEquivalent: (key: Character, modifiers: EventModifiers)? {
        switch self {
        case .toggleViewMode: return nil
        case .zoomIn: return ("+", .command)
        case .zoomOut: return ("-", .command)
        case .closeFile: return ("w", [.command, .shift])
        case .toggleFullScreen: return ("f", [.control, .command])
        default: return nil
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

        /// SwiftUI EventModifiersに変換
        func toEventModifiers() -> EventModifiers {
            var mods: EventModifiers = []
            if contains(.shift) { mods.insert(.shift) }
            if contains(.control) { mods.insert(.control) }
            if contains(.option) { mods.insert(.option) }
            if contains(.command) { mods.insert(.command) }
            return mods
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

    /// SwiftUI KeyboardShortcutに変換（メニュー表示用）
    var keyEquivalentCharacter: Character? {
        // 特殊キーはKeyEquivalentに変換できない場合がある
        switch keyCode {
        case 48: return "\t"          // Tab
        case 49: return " "           // Space
        case 36: return "\r"          // Return
        case 53: return "\u{1B}"      // Escape
        default:
            // 通常の文字キー: keyDisplayからCharacterを生成
            if let char = keyDisplay.lowercased().first {
                return char
            }
            return nil
        }
    }

    /// キーコードから表示文字列を生成
    static func keyDisplayString(for event: NSEvent) -> String {
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

// MARK: - バインディングの種別

/// バインディングの種別（UI表示用）
enum BindingType {
    case defaultBinding   // デフォルト（削除可能、復元可能）
    case customBinding    // ユーザー追加（削除可能）
}

/// 表示用バインディング情報
struct DisplayBinding: Identifiable {
    let id = UUID()
    let binding: KeyBinding
    let type: BindingType
}

// MARK: - CustomShortcutManager

/// カスタムショートカットの管理（三層モデル）
///
/// - OS固定: HardcodedShortcutで管理（⌘Q, ⌘W等）、変更不可
/// - デフォルト: ShortcutAction.defaultBindingsで定義、ユーザーが削除可能
/// - カスタム: ユーザーが自由に追加
@MainActor
@Observable
final class CustomShortcutManager {
    /// シングルトン
    static let shared = CustomShortcutManager()

    /// ユーザー追加のカスタムバインディング
    private(set) var customShortcuts: [ShortcutAction: [KeyBinding]] = [:]

    /// ユーザーが削除したデフォルトバインディング
    private(set) var removedDefaults: [ShortcutAction: [KeyBinding]] = [:]

    private let customShortcutsKey = "customKeyboardShortcuts"
    private let removedDefaultsKey = "removedDefaultShortcuts"

    private init() {
        loadState()
    }

    // MARK: - 有効バインディングの取得

    /// アクションの有効バインディング一覧（デフォルト−削除+カスタム）
    func effectiveBindings(for action: ShortcutAction) -> [KeyBinding] {
        let defaults = action.defaultBindings.filter { binding in
            !(removedDefaults[action]?.contains(binding) ?? false)
        }
        let custom = customShortcuts[action] ?? []
        return defaults + custom
    }

    /// 表示用バインディング一覧（種別付き）
    func displayBindings(for action: ShortcutAction) -> [DisplayBinding] {
        var result: [DisplayBinding] = []

        let activeDefaults = action.defaultBindings.filter { binding in
            !(removedDefaults[action]?.contains(binding) ?? false)
        }
        for binding in activeDefaults {
            result.append(DisplayBinding(binding: binding, type: .defaultBinding))
        }

        for binding in (customShortcuts[action] ?? []) {
            result.append(DisplayBinding(binding: binding, type: .customBinding))
        }

        return result
    }

    /// NSEventに対応するアクションを検索（全有効バインディングから）
    func findAction(for event: NSEvent) -> ShortcutAction? {
        for action in ShortcutAction.allCases {
            for binding in effectiveBindings(for: action) {
                if binding.matches(event) {
                    return action
                }
            }
        }
        return nil
    }

    /// 指定キーバインディングがいずれかのアクションに割り当てられているか検索（衝突チェック用）
    func findAction(for binding: KeyBinding) -> ShortcutAction? {
        for action in ShortcutAction.allCases {
            if effectiveBindings(for: action).contains(binding) {
                return action
            }
        }
        return nil
    }

    /// 指定キーコード+モディファイアがいずれかのアクションに割り当てられているか
    func hasBinding(keyCode: UInt16, modifiers: KeyBinding.ModifierFlags) -> Bool {
        for action in ShortcutAction.allCases {
            for binding in effectiveBindings(for: action) {
                if binding.keyCode == keyCode && binding.modifiers == modifiers {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - カスタムバインディング操作

    /// カスタムショートカットを追加
    func addCustomShortcut(_ binding: KeyBinding, for action: ShortcutAction) {
        if customShortcuts[action] == nil {
            customShortcuts[action] = []
        }
        if !customShortcuts[action]!.contains(binding) {
            customShortcuts[action]!.append(binding)
            saveState()
        }
    }

    /// カスタムショートカットを削除
    func removeCustomShortcut(_ binding: KeyBinding, from action: ShortcutAction) {
        customShortcuts[action]?.removeAll { $0 == binding }
        saveState()
    }

    // MARK: - デフォルトバインディング操作

    /// デフォルトバインディングを削除
    func removeDefaultBinding(_ binding: KeyBinding, from action: ShortcutAction) {
        if removedDefaults[action] == nil {
            removedDefaults[action] = []
        }
        if !removedDefaults[action]!.contains(binding) {
            removedDefaults[action]!.append(binding)
            saveState()
        }
    }

    /// 削除したデフォルトバインディングを復元
    func restoreDefaultBinding(_ binding: KeyBinding, for action: ShortcutAction) {
        removedDefaults[action]?.removeAll { $0 == binding }
        saveState()
    }

    /// アクションの削除されたデフォルト一覧
    func removedDefaultBindings(for action: ShortcutAction) -> [KeyBinding] {
        return removedDefaults[action] ?? []
    }

    // MARK: - リセット

    /// 全カスタマイズをリセット（デフォルトに戻す）
    func resetToDefaults() {
        customShortcuts = [:]
        removedDefaults = [:]
        saveState()
    }

    // MARK: - メニュー連動

    /// アクションの最初の有効バインディングからSwiftUI KeyboardShortcutを生成
    func keyboardShortcut(for action: ShortcutAction) -> (key: KeyEquivalent, modifiers: EventModifiers)? {
        guard let binding = effectiveBindings(for: action).first else { return nil }
        guard let char = binding.keyEquivalentCharacter else { return nil }
        return (KeyEquivalent(char), binding.modifiers.toEventModifiers())
    }

    // MARK: - 永続化

    private func saveState() {
        let encoder = JSONEncoder()
        if let customData = try? encoder.encode(customShortcuts) {
            UserDefaults.standard.set(customData, forKey: customShortcutsKey)
        }
        if let removedData = try? encoder.encode(removedDefaults) {
            UserDefaults.standard.set(removedData, forKey: removedDefaultsKey)
        }
    }

    private func loadState() {
        let decoder = JSONDecoder()

        if let customData = UserDefaults.standard.data(forKey: customShortcutsKey),
           let loaded = try? decoder.decode([ShortcutAction: [KeyBinding]].self, from: customData) {
            customShortcuts = loaded
        }

        if let removedData = UserDefaults.standard.data(forKey: removedDefaultsKey),
           let loaded = try? decoder.decode([ShortcutAction: [KeyBinding]].self, from: removedData) {
            removedDefaults = loaded
        }

        migrateIfNeeded()
    }

    /// 旧データからの移行: カスタムがデフォルトと重複している場合は除去
    private func migrateIfNeeded() {
        var changed = false
        for action in ShortcutAction.allCases {
            let defaults = action.defaultBindings
            if var custom = customShortcuts[action] {
                let before = custom.count
                custom.removeAll { defaults.contains($0) }
                if custom.count != before {
                    customShortcuts[action] = custom.isEmpty ? nil : custom
                    changed = true
                }
            }
        }
        if changed {
            saveState()
        }
    }
}

// MARK: - HardcodedShortcut（OS固定のみ）

/// OS管理の変更不可ショートカット（キーキャプチャ時の衝突チェック用）
struct HardcodedShortcut {
    let displayName: String
    let keyDisplay: String

    /// キーコードとモディファイアからOS固定ショートカットを検索
    static func find(keyCode: UInt16, modifiers: KeyBinding.ModifierFlags) -> HardcodedShortcut? {
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

    /// KeyBindingからOS固定ショートカットを検索
    static func find(for binding: KeyBinding) -> HardcodedShortcut? {
        return find(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }
}

// MARK: - メニューショートカット連動用ViewModifier

/// CustomShortcutManagerの設定に応じてメニューのキーボードショートカットを動的に変更する
struct DynamicShortcut: ViewModifier {
    let action: ShortcutAction
    let manager: CustomShortcutManager

    func body(content: Content) -> some View {
        if let shortcut = manager.keyboardShortcut(for: action) {
            content.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }
}
