import SwiftUI

/// 設定画面
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(L("tab_general"), systemImage: "gear")
                }

            WindowSettingsTab()
                .tabItem {
                    Label(L("tab_window"), systemImage: "macwindow")
                }

            HistorySettingsTab()
                .tabItem {
                    Label(L("tab_history"), systemImage: "clock")
                }

            ShortcutSettingsTab()
                .tabItem {
                    Label(L("tab_shortcut"), systemImage: "keyboard")
                }
        }
        .frame(width: 500, height: 420)
    }
}

/// 一般設定タブ
struct GeneralSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section(L("section_display")) {
                Picker(L("default_view_mode"), selection: $settings.defaultViewMode) {
                    Text(L("view_mode_single")).tag(ViewMode.single)
                    Text(L("view_mode_spread")).tag(ViewMode.spread)
                }
                .pickerStyle(.segmented)

                Picker(L("default_reading_direction"), selection: $settings.defaultReadingDirection) {
                    Text(L("reading_direction_rtl")).tag(ReadingDirection.rightToLeft)
                    Text(L("reading_direction_ltr")).tag(ReadingDirection.leftToRight)
                }
                .pickerStyle(.segmented)

                Toggle(L("show_status_bar"), isOn: $settings.defaultShowStatusBar)

                HStack {
                    Text(L("page_jump_count"))
                    Spacer()
                    TextField("", value: $settings.pageJumpCount, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text(L("page_jump_count_unit"))
                        .foregroundColor(.secondary)
                }

                Picker(L("page_transition_mode"), selection: $settings.pageTransitionMode) {
                    Text(L("page_transition_always")).tag(PageTransitionMode.always)
                    Text(L("page_transition_swipe_only")).tag(PageTransitionMode.swipeOnly)
                    Text(L("page_transition_never")).tag(PageTransitionMode.never)
                }

            }

            Section(L("section_image_detection")) {
                HStack {
                    Text(L("landscape_threshold"))
                    Spacer()
                    TextField("", value: $settings.defaultLandscapeThreshold, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text(L("landscape_threshold_unit"))
                        .foregroundColor(.secondary)
                }
                Text(L("landscape_threshold_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L("section_app_behavior")) {
                Toggle(L("quit_on_last_window_closed"), isOn: $settings.quitOnLastWindowClosed)

                Text(L("quit_on_last_window_closed_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text(L("concurrent_loading_limit"))
                    Spacer()
                    TextField("", value: $settings.concurrentLoadingLimit, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }
                Text(L("concurrent_loading_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("check_for_updates_on_launch"), isOn: $settings.checkForUpdatesOnLaunch)
            }

            Section(L("section_initial_screen")) {
                HStack {
                    Text(L("background_image"))
                    Spacer()
                    if settings.initialScreenBackgroundImagePath.isEmpty {
                        Text(L("background_image_none"))
                            .foregroundColor(.secondary)
                    } else {
                        Text(URL(fileURLWithPath: settings.initialScreenBackgroundImagePath).lastPathComponent)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                HStack {
                    Button(L("background_image_select")) {
                        selectBackgroundImage()
                    }
                    if !settings.initialScreenBackgroundImagePath.isEmpty {
                        Button(L("background_image_clear")) {
                            settings.initialScreenBackgroundImagePath = ""
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// 背景画像を選択するファイルダイアログを表示
    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L("background_image_select_message")

        if panel.runModal() == .OK, let url = panel.url {
            settings.initialScreenBackgroundImagePath = url.path
        }
    }
}

/// ウィンドウ設定タブ
struct WindowSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section(L("section_window_size")) {
                Picker(L("window_size_mode"), selection: $settings.windowSizeMode) {
                    Text(L("window_size_mode_last_used")).tag(WindowSizeMode.lastUsed)
                    Text(L("window_size_mode_fixed")).tag(WindowSizeMode.fixed)
                }
                .pickerStyle(.segmented)

                Text(L("window_size_mode_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L("section_fixed_window_size")) {
                HStack {
                    Text(L("window_width"))
                    Spacer()
                    TextField("", value: $settings.fixedWindowWidth, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("px")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(L("window_height"))
                    Spacer()
                    TextField("", value: $settings.fixedWindowHeight, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("px")
                        .foregroundColor(.secondary)
                }
            }
            .disabled(settings.windowSizeMode != .fixed)
            .opacity(settings.windowSizeMode == .fixed ? 1.0 : 0.5)

            Section(L("section_last_window_size")) {
                HStack {
                    Text(L("current_last_window_size"))
                    Spacer()
                    Text("\(Int(settings.lastWindowWidth)) × \(Int(settings.lastWindowHeight)) px")
                        .foregroundColor(.secondary)
                }
            }
            .disabled(settings.windowSizeMode != .lastUsed)
            .opacity(settings.windowSizeMode == .lastUsed ? 1.0 : 0.5)
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// 履歴設定タブ
struct HistorySettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(ImageCatalogManager.self) private var imageCatalogManager
    @Environment(SessionGroupManager.self) private var sessionGroupManager

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section(L("section_history_display_settings")) {
                Picker(L("history_display_mode"), selection: $settings.historyDisplayMode) {
                    Text(L("history_display_always_show")).tag(HistoryDisplayMode.alwaysShow)
                    Text(L("history_display_always_hide")).tag(HistoryDisplayMode.alwaysHide)
                    Text(L("history_display_restore_last")).tag(HistoryDisplayMode.restoreLast)
                }
            }

            Section(L("section_history_management")) {
                // バージョントリガーを監視（配列は@ObservationIgnored）
                let _ = historyManager.historyVersion
                let _ = imageCatalogManager.catalogVersion

                HStack {
                    Text(L("reset_access_counts_label"))
                    Spacer()
                    Button(L("reset_access_counts")) {
                        historyManager.resetAllAccessCounts()
                    }
                    .disabled(historyManager.history.isEmpty)
                }

                // 書庫ファイル
                HStack {
                    Text(L("history_label_archive"))
                        .frame(width: 80, alignment: .leading)
                    Text("\(historyManager.history.count)")
                        .frame(width: 60, alignment: .trailing)
                        .monospacedDigit()
                    Text("/ \(L("history_max_prefix"))")
                    TextField("", value: $settings.maxHistoryCount, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                    Spacer()
                    Button(L("clear_all")) {
                        historyManager.clearAllHistory()
                    }
                    .foregroundColor(.red)
                    .disabled(historyManager.history.isEmpty)
                }

                // 個別画像
                HStack {
                    Text(L("history_label_standalone_image"))
                        .frame(width: 80, alignment: .leading)
                    Text("\(imageCatalogManager.standaloneCount)")
                        .frame(width: 60, alignment: .trailing)
                        .monospacedDigit()
                    Text("/ \(L("history_max_prefix"))")
                    TextField("", value: $settings.maxStandaloneImageCount, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                    Spacer()
                    Button(L("clear_all")) {
                        imageCatalogManager.clearStandaloneCatalog()
                    }
                    .foregroundColor(.red)
                    .disabled(imageCatalogManager.standaloneCount == 0)
                }

                // 書庫内画像
                HStack {
                    Text(L("history_label_archive_content_image"))
                        .frame(width: 80, alignment: .leading)
                    Text("\(imageCatalogManager.archiveContentCount)")
                        .frame(width: 60, alignment: .trailing)
                        .monospacedDigit()
                    Text("/ \(L("history_max_prefix"))")
                    TextField("", value: $settings.maxArchiveContentImageCount, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                    Spacer()
                    Button(L("clear_all")) {
                        imageCatalogManager.clearArchiveContentCatalog()
                    }
                    .foregroundColor(.red)
                    .disabled(imageCatalogManager.archiveContentCount == 0)
                }

                // セッション
                HStack {
                    Text(L("history_label_session"))
                        .frame(width: 80, alignment: .leading)
                    Text("\(sessionGroupManager.sessionGroups.count)")
                        .frame(width: 60, alignment: .trailing)
                        .monospacedDigit()
                    Text("/ \(L("history_max_prefix"))")
                    TextField("", value: $settings.maxSessionGroupCount, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                    Spacer()
                    Button(L("clear_all")) {
                        sessionGroupManager.clearAllSessionGroups()
                    }
                    .foregroundColor(.red)
                    .disabled(sessionGroupManager.sessionGroups.isEmpty)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
    }
}

/// ショートカット設定タブ
struct ShortcutSettingsTab: View {
    @State private var shortcutManager = CustomShortcutManager.shared
    @State private var capturingAction: ShortcutAction?

    var body: some View {
        Form {
            Section(L("section_shortcut")) {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    ShortcutRow(
                        action: action,
                        shortcutManager: shortcutManager,
                        onAddPressed: {
                            capturingAction = action
                        }
                    )
                }
            }

            Section {
                HStack {
                    Text(L("shortcut_arrow_keys_note"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(L("shortcut_reset_defaults")) {
                        shortcutManager.resetToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $capturingAction) { action in
            KeyCaptureView(
                action: action,
                shortcutManager: shortcutManager,
                onCapture: { binding in
                    shortcutManager.addCustomShortcut(binding, for: action)
                    capturingAction = nil
                },
                onCancel: {
                    capturingAction = nil
                }
            )
        }
    }
}

/// ショートカット行（三層表示: デフォルト + カスタム + 追加ボタン）
struct ShortcutRow: View {
    let action: ShortcutAction
    let shortcutManager: CustomShortcutManager
    let onAddPressed: () -> Void

    var body: some View {
        HStack {
            Text(action.displayName)
                .frame(minWidth: 120, alignment: .leading)

            Spacer()

            HStack(spacing: 4) {
                ForEach(shortcutManager.displayBindings(for: action)) { item in
                    switch item.type {
                    case .defaultBinding:
                        DefaultKeyChip(binding: item.binding) {
                            shortcutManager.removeDefaultBinding(item.binding, from: action)
                        }
                    case .customBinding:
                        CustomKeyChip(binding: item.binding) {
                            shortcutManager.removeCustomShortcut(item.binding, from: action)
                        }
                    }
                }

                // 削除されたデフォルトがある場合、復元ボタンを表示
                let removed = shortcutManager.removedDefaultBindings(for: action)
                if !removed.isEmpty {
                    Menu {
                        ForEach(removed, id: \.displayString) { binding in
                            Button(binding.displayString) {
                                shortcutManager.restoreDefaultBinding(binding, for: action)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // 追加ボタン
                Button(action: onAddPressed) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
}

/// デフォルトバインディングのチップ（削除可能、青色系）
struct DefaultKeyChip: View {
    let binding: KeyBinding
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 2) {
            Text(binding.displayString)
                .font(.system(.caption, design: .monospaced))

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.15))
        .cornerRadius(4)
        .onHover { isHovering = $0 }
    }
}

/// カスタムバインディングのチップ（削除可能、グレー系）
struct CustomKeyChip: View {
    let binding: KeyBinding
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 2) {
            Text(binding.displayString)
                .font(.system(.caption, design: .monospaced))

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(4)
        .onHover { isHovering = $0 }
    }
}

/// キーキャプチャモーダル
struct KeyCaptureView: View {
    let action: ShortcutAction
    let shortcutManager: CustomShortcutManager
    let onCapture: (KeyBinding) -> Void
    let onCancel: () -> Void

    @State private var capturedKey: String = ""
    @State private var eventMonitor: Any?
    @State private var showConflictAlert = false
    @State private var conflictBinding: KeyBinding?
    @State private var conflictAction: ShortcutAction?
    @State private var showHardcodedConflictAlert = false
    @State private var hardcodedConflict: HardcodedShortcut?

    var body: some View {
        VStack(spacing: 20) {
            Text(L("shortcut_press_key"))
                .font(.headline)

            Text(action.displayName)
                .font(.title2)
                .foregroundColor(.accentColor)

            if capturedKey.isEmpty {
                Text(L("shortcut_press_key_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(capturedKey)
                    .font(.system(.title, design: .monospaced))
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }

            Button(L("shortcut_cancel")) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(40)
        .frame(minWidth: 300)
        .onAppear {
            startCapturing()
        }
        .onDisappear {
            stopCapturing()
        }
        .alert(L("shortcut_conflict_title"), isPresented: $showConflictAlert) {
            Button(L("shortcut_overwrite"), role: .destructive) {
                if let binding = conflictBinding, let existingAction = conflictAction {
                    // 既存のバインディングを削除して新しいものを追加
                    // デフォルトバインディングか、カスタムバインディングかを判定
                    if existingAction.defaultBindings.contains(binding) {
                        shortcutManager.removeDefaultBinding(binding, from: existingAction)
                    } else {
                        shortcutManager.removeCustomShortcut(binding, from: existingAction)
                    }
                    onCapture(binding)
                }
            }
            Button(L("shortcut_cancel"), role: .cancel) {
                // キャプチャ画面に戻る
                capturedKey = ""
                startCapturing()
            }
        } message: {
            if let binding = conflictBinding, let existingAction = conflictAction {
                Text(String(format: L("shortcut_conflict_message"), binding.displayString, existingAction.displayName))
            }
        }
        .alert(L("shortcut_hardcoded_conflict_title"), isPresented: $showHardcodedConflictAlert) {
            Button(L("ok"), role: .cancel) {
                // キャプチャ画面に戻る
                capturedKey = ""
                startCapturing()
            }
        } message: {
            if let hardcoded = hardcodedConflict {
                Text(String(format: L("shortcut_hardcoded_conflict_message"), hardcoded.keyDisplay, hardcoded.displayName))
            }
        }
    }

    private func startCapturing() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escでキャンセル
            if event.keyCode == 53 {
                onCancel()
                return nil
            }

            // モディファイアのみは無視
            let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierOnlyKeyCodes.contains(event.keyCode) {
                return nil
            }

            // キーをキャプチャ
            let binding = KeyBinding(from: event)
            capturedKey = binding.displayString

            // 固定ショートカットとの衝突チェック（上書き不可）
            if let hardcoded = HardcodedShortcut.find(for: binding) {
                self.stopCapturing()
                hardcodedConflict = hardcoded
                showHardcodedConflictAlert = true
                return nil
            }

            // カスタムショートカットとの衝突チェック（上書き可能）
            if let existingAction = shortcutManager.findAction(for: binding), existingAction != action {
                self.stopCapturing()
                conflictBinding = binding
                conflictAction = existingAction
                showConflictAlert = true
            } else {
                // 衝突なし - そのまま登録
                onCapture(binding)
            }
            return nil
        }
    }

    private func stopCapturing() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
