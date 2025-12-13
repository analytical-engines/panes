import SwiftUI
import AppKit
import UniformTypeIdentifiers

// FocusedValuesのキー定義
struct FocusedViewModelKey: FocusedValueKey {
    typealias Value = BookViewModel
}

struct FocusedShowHistoryKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var bookViewModel: FocusedViewModelKey.Value? {
        get { self[FocusedViewModelKey.self] }
        set { self[FocusedViewModelKey.self] = newValue }
    }

    var showHistory: FocusedShowHistoryKey.Value? {
        get { self[FocusedShowHistoryKey.self] }
        set { self[FocusedShowHistoryKey.self] = newValue }
    }
}

/// ウィンドウのデフォルトサイズを取得（UserDefaultsから読み込み）
private func getDefaultWindowSize() -> CGSize {
    let defaults = UserDefaults.standard
    let mode = defaults.string(forKey: "windowSizeMode") ?? "lastUsed"

    if mode == "fixed" {
        // 固定サイズモード
        let width = defaults.object(forKey: "fixedWindowWidth") != nil
            ? defaults.double(forKey: "fixedWindowWidth") : 1200
        let height = defaults.object(forKey: "fixedWindowHeight") != nil
            ? defaults.double(forKey: "fixedWindowHeight") : 800
        return CGSize(width: width, height: height)
    } else {
        // 最後のサイズモード
        let width = defaults.object(forKey: "lastWindowWidth") != nil
            ? defaults.double(forKey: "lastWindowWidth") : 1200
        let height = defaults.object(forKey: "lastWindowHeight") != nil
            ? defaults.double(forKey: "lastWindowHeight") : 800
        return CGSize(width: width, height: height)
    }
}

@main
struct ImageViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.bookViewModel) private var focusedViewModel: BookViewModel?
    @FocusedValue(\.showHistory) private var focusedShowHistory: Binding<Bool>?
    @State private var historyManager = FileHistoryManager()
    @State private var imageCatalogManager = ImageCatalogManager()
    @State private var appSettings = AppSettings()
    @State private var sessionManager = SessionManager()
    @State private var sessionGroupManager = SessionGroupManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(historyManager)
                .environment(imageCatalogManager)
                .environment(appSettings)
                .environment(sessionManager)
                .environment(sessionGroupManager)
                .onAppear {
                    // ウィンドウを最前面に
                    NSApp.activate(ignoringOtherApps: true)

                    // AppDelegateに参照を渡す
                    appDelegate.sessionManager = sessionManager
                    appDelegate.appSettings = appSettings
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(getDefaultWindowSize())
        .commands {
            // ファイルメニューにClose/履歴Export/Importを追加
            CommandGroup(after: .newItem) {
                Button(action: {
                    focusedViewModel?.closeFile()
                }) {
                    Label(L("menu_close_file"), systemImage: "xmark")
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(focusedViewModel?.hasOpenFile != true)

                Button(action: {
                    editCurrentFileMemo()
                }) {
                    Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(focusedViewModel?.hasOpenFile != true)

                Divider()

                Menu(L("menu_history")) {
                    Button(action: {
                        exportHistory()
                    }) {
                        Label(L("menu_export_history"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(!historyManager.canExportHistory)

                    Button(action: {
                        importHistory(merge: true)
                    }) {
                        Label(L("menu_import_history_merge"), systemImage: "square.and.arrow.down")
                    }

                    Button(action: {
                        importHistory(merge: false)
                    }) {
                        Label(L("menu_import_history_replace"), systemImage: "square.and.arrow.down.fill")
                    }
                }
            }

            CommandGroup(after: .sidebar) {
                // フォーカスされているウィンドウの履歴表示をトグル
                Toggle(L("menu_show_history"), isOn: Binding(
                    get: { focusedShowHistory?.wrappedValue ?? appSettings.lastHistoryVisible },
                    set: { newValue in
                        focusedShowHistory?.wrappedValue = newValue
                        // 「終了時の状態を復元」モードの場合は保存
                        if appSettings.historyDisplayMode == .restoreLast {
                            appSettings.lastHistoryVisible = newValue
                        }
                    }
                ))
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button(action: {
                    focusedViewModel?.toggleViewMode()
                }) {
                    Label(
                        focusedViewModel?.viewMode == .spread
                            ? L("menu_single_view")
                            : L("menu_spread_view"),
                        systemImage: focusedViewModel?.viewMode == .spread
                            ? "rectangle"
                            : "rectangle.split.2x1"
                    )
                }
                .disabled(focusedViewModel == nil)

                Divider()

                Button(action: {
                    focusedViewModel?.toggleReadingDirection()
                }) {
                    Label(
                        focusedViewModel?.readingDirection == .rightToLeft
                            ? L("menu_reading_direction_rtl")
                            : L("menu_reading_direction_ltr"),
                        systemImage: focusedViewModel?.readingDirection == .rightToLeft
                            ? "arrow.left"
                            : "arrow.right"
                    )
                }
                .disabled(focusedViewModel == nil)

                // フィッティングモード
                Menu(L("menu_fitting_mode")) {
                    Button(action: {
                        focusedViewModel?.fittingMode = .window
                    }) {
                        Label(
                            L("menu_fitting_window"),
                            systemImage: focusedViewModel?.fittingMode == .window
                                ? "checkmark"
                                : ""
                        )
                    }
                    Button(action: {
                        focusedViewModel?.fittingMode = .height
                    }) {
                        Label(
                            L("menu_fitting_height"),
                            systemImage: focusedViewModel?.fittingMode == .height
                                ? "checkmark"
                                : ""
                        )
                    }
                    Button(action: {
                        focusedViewModel?.fittingMode = .width
                    }) {
                        Label(
                            L("menu_fitting_width"),
                            systemImage: focusedViewModel?.fittingMode == .width
                                ? "checkmark"
                                : ""
                        )
                    }

                    Divider()

                    Button(action: {
                        focusedViewModel?.fittingMode = .originalSize
                    }) {
                        Label(
                            L("menu_fitting_original"),
                            systemImage: focusedViewModel?.fittingMode == .originalSize
                                ? "checkmark"
                                : ""
                        )
                    }
                    .disabled(focusedViewModel?.viewMode == .spread)
                }
                .disabled(focusedViewModel == nil)

                // ズーム
                Menu(L("menu_zoom")) {
                    Button(action: {
                        focusedViewModel?.zoomIn()
                    }) {
                        Label(L("menu_zoom_in"), systemImage: "plus.magnifyingglass")
                    }
                    .keyboardShortcut("+", modifiers: .command)

                    Button(action: {
                        focusedViewModel?.zoomOut()
                    }) {
                        Label(L("menu_zoom_out"), systemImage: "minus.magnifyingglass")
                    }
                    .keyboardShortcut("-", modifiers: .command)

                    Divider()

                    Button(action: {
                        focusedViewModel?.resetZoom()
                    }) {
                        Label(L("menu_zoom_reset"), systemImage: "1.magnifyingglass")
                    }
                    .keyboardShortcut("0", modifiers: .command)

                    Divider()

                    // 現在のズームレベル表示
                    Text("\(focusedViewModel?.zoomPercentage ?? 100)%")
                        .foregroundColor(.secondary)
                }
                .disabled(focusedViewModel == nil)

                Button(action: {
                    focusedViewModel?.toggleStatusBar()
                }) {
                    Label(
                        focusedViewModel?.showStatusBar == true
                            ? L("menu_hide_status_bar")
                            : L("menu_show_status_bar"),
                        systemImage: focusedViewModel?.showStatusBar == true
                            ? "eye.slash"
                            : "eye"
                    )
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(focusedViewModel == nil)

                Divider()

                // ページ設定メニュー（階層化）
                Menu(L("menu_page_settings")) {
                    Button(action: {
                        focusedViewModel?.toggleCurrentPageSingleDisplay()
                    }) {
                        Label(
                            focusedViewModel?.isCurrentPageForcedSingle == true
                                ? L("menu_remove_single_page_attribute")
                                : L("menu_force_single_page"),
                            systemImage: focusedViewModel?.isCurrentPageForcedSingle == true
                                ? "checkmark.square"
                                : "square"
                        )
                    }

                    // 単ページ配置設定
                    Menu(L("menu_single_page_alignment")) {
                        Button(action: {
                            focusedViewModel?.setCurrentPageAlignment(.right)
                        }) {
                            Label(
                                L("menu_align_right"),
                                systemImage: focusedViewModel?.currentPageAlignment == .right
                                    ? "checkmark"
                                    : ""
                            )
                        }

                        Button(action: {
                            focusedViewModel?.setCurrentPageAlignment(.left)
                        }) {
                            Label(
                                L("menu_align_left"),
                                systemImage: focusedViewModel?.currentPageAlignment == .left
                                    ? "checkmark"
                                    : ""
                            )
                        }

                        Button(action: {
                            focusedViewModel?.setCurrentPageAlignment(.center)
                        }) {
                            Label(
                                L("menu_align_center"),
                                systemImage: focusedViewModel?.currentPageAlignment == .center
                                    ? "checkmark"
                                    : ""
                            )
                        }
                    }

                    Divider()

                    Button(action: {
                        exportPageSettings()
                    }) {
                        Label(L("menu_export_page_settings"), systemImage: "square.and.arrow.up")
                    }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                    Button(action: {
                        importPageSettings()
                    }) {
                        Label(L("menu_import_page_settings"), systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .shift])

                    Divider()

                    Button(action: {
                        resetPageSettings()
                    }) {
                        Label(L("menu_reset_page_settings"), systemImage: "arrow.counterclockwise")
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                .disabled(focusedViewModel == nil)
            }

            // ウィンドウメニューにセッション保存を追加
            CommandGroup(before: .windowArrangement) {
                Button(action: {
                    saveCurrentWindowsAsSession()
                }) {
                    Label(L("menu_save_session"), systemImage: "square.stack.3d.up")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(sessionManager.activeWindows.isEmpty)

                Divider()
            }
        }

        // 設定ウィンドウ
        Settings {
            SettingsView()
                .environment(appSettings)
                .environment(historyManager)
                .environment(imageCatalogManager)
                .environment(sessionManager)
        }

        // 「このアプリケーションで開く」用のウィンドウグループ
        WindowGroup(id: "new") {
            ContentView()
                .environment(historyManager)
                .environment(imageCatalogManager)
                .environment(appSettings)
                .environment(sessionManager)
                .environment(sessionGroupManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(getDefaultWindowSize())

        // セッション復元用のウィンドウグループ
        WindowGroup(id: "restore") {
            ContentView()
                .environment(historyManager)
                .environment(imageCatalogManager)
                .environment(appSettings)
                .environment(sessionManager)
                .environment(sessionGroupManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(getDefaultWindowSize())
    }

    /// ページ表示設定をExport
    private func exportPageSettings() {
        guard let viewModel = focusedViewModel,
              let data = viewModel.exportPageSettings() else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = viewModel.exportFileName
        savePanel.title = L("export_panel_title")
        savePanel.prompt = L("export_panel_prompt")

        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            do {
                try data.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = L("export_error_title")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    /// ページ表示設定をImport
    private func importPageSettings() {
        guard let viewModel = focusedViewModel else { return }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = L("import_panel_title")
        openPanel.prompt = L("import_panel_prompt")

        let response = openPanel.runModal()
        if response == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                let result = viewModel.importPageSettings(from: data)

                let alert = NSAlert()
                alert.messageText = result.success ? L("import_success_title") : L("import_error_title")
                alert.informativeText = result.message
                alert.alertStyle = result.success ? .informational : .critical
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = L("import_error_title")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    /// ページ表示設定を初期化
    private func resetPageSettings() {
        guard let viewModel = focusedViewModel else { return }

        let alert = NSAlert()
        alert.messageText = L("reset_confirm_title")
        alert.informativeText = L("reset_confirm_message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("reset_confirm_ok"))
        alert.addButton(withTitle: L("reset_confirm_cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.resetPageSettings()
        }
    }

    /// 履歴をExport
    private func exportHistory() {
        guard let data = historyManager.exportHistory() else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "panes_history.json"
        savePanel.title = L("export_history_panel_title")
        savePanel.prompt = L("export_panel_prompt")

        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            do {
                try data.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = L("export_error_title")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    /// 現在のファイルのメモを編集
    private func editCurrentFileMemo() {
        guard let viewModel = focusedViewModel else { return }

        let alert = NSAlert()
        alert.messageText = L("memo_edit_title")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("save"))
        alert.addButton(withTitle: L("cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = viewModel.getCurrentMemo() ?? ""
        textField.placeholderString = L("memo_placeholder")
        alert.accessoryView = textField

        // テキストフィールドにフォーカスを設定
        alert.window.initialFirstResponder = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newMemo = textField.stringValue
            viewModel.updateCurrentMemo(newMemo.isEmpty ? nil : newMemo)
        }
    }

    /// 履歴をImport
    private func importHistory(merge: Bool) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = L("import_history_panel_title")
        openPanel.prompt = L("import_panel_prompt")

        let response = openPanel.runModal()
        if response == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                let result = historyManager.importHistory(from: data, merge: merge)

                let alert = NSAlert()
                if result.success {
                    alert.messageText = L("import_success_title")
                    let modeText = merge ? L("import_history_merged") : L("import_history_replaced")
                    alert.informativeText = String(format: L("import_history_success_format"), result.importedCount, modeText)
                    alert.alertStyle = .informational
                } else {
                    alert.messageText = L("import_error_title")
                    alert.informativeText = L("import_error_invalid_format")
                    alert.alertStyle = .critical
                }
                alert.runModal()
            } catch {
                let alert = NSAlert()
                alert.messageText = L("import_error_title")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    /// 現在のウィンドウをセッショングループとして保存
    private func saveCurrentWindowsAsSession() {
        let windowEntries = sessionManager.collectCurrentWindowStates()
        guard !windowEntries.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = L("save_session_title")
        alert.informativeText = String(format: L("save_session_message_format"), windowEntries.count)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("save"))
        alert.addButton(withTitle: L("cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = generateDefaultSessionName()
        textField.placeholderString = L("save_session_name_placeholder")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let name = textField.stringValue.isEmpty ? generateDefaultSessionName() : textField.stringValue
            _ = sessionGroupManager.createSessionGroup(name: name, from: windowEntries)
        }
    }

    /// デフォルトのセッション名を生成
    private func generateDefaultSessionName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: Date())
    }
}

// アプリケーションデリゲート
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var sessionManager: SessionManager?
    var appSettings: AppSettings?

    /// セッション復元が開始されたかどうか
    private var sessionRestorationStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // アプリ起動時にフォーカスを取得
        NSApp.activate(ignoringOtherApps: true)

        // セッション復元を遅延実行（参照が設定されるのを待つ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startSessionRestorationIfNeeded()
        }
    }

    /// セッション復元を開始（必要な場合）
    private func startSessionRestorationIfNeeded() {
        guard !sessionRestorationStarted else { return }
        sessionRestorationStarted = true

        guard appSettings?.sessionRestoreEnabled == true else {
            DebugLogger.log("📂 Session restore is disabled", level: .normal)
            return
        }

        guard let sessionManager = sessionManager else {
            DebugLogger.log("❌ SessionManager not available", level: .normal)
            return
        }

        // 同時読み込み制限を設定
        sessionManager.concurrentLoadingLimit = appSettings?.sessionConcurrentLoadingLimit ?? 1

        // セッション復元を開始
        sessionManager.startRestoration()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 復元中は終了しない
        if sessionManager?.isProcessing == true {
            return false
        }
        // 設定に従って終了するかどうかを決定
        return appSettings?.quitOnLastWindowClosed ?? true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // セッション保存が有効な場合のみ保存
        guard appSettings?.sessionRestoreEnabled == true else {
            DebugLogger.log("📂 Session save skipped (disabled)", level: .normal)
            return
        }

        guard let sessionManager = sessionManager else { return }

        // 現在のウィンドウ状態を収集して保存
        let entries = sessionManager.collectCurrentWindowStates()
        if !entries.isEmpty {
            sessionManager.saveSession(entries)
        } else {
            sessionManager.clearSession()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Finderから「このアプリケーションで開く」でファイルが渡される
        // SessionManagerの統合キューに追加
        sessionManager?.addFilesToOpen(urls: urls)
    }
}
