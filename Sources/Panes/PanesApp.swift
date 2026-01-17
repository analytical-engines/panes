import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Note: FocusedValuesは使用しない（パフォーマンス問題のため）
// 代わりにWindowCoordinatorを使用してNSApp.keyWindowから直接ViewModelを取得する

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
    // focusedValueは使用しない（パフォーマンス問題のため）
    // 代わりにWindowCoordinator.shared.keyWindowViewModelを使用
    @State private var historyManager = FileHistoryManager()
    @State private var imageCatalogManager = ImageCatalogManager()
    @State private var appSettings = AppSettings()
    @State private var sessionManager = SessionManager()
    @State private var sessionGroupManager = SessionGroupManager()
    @Environment(\.openWindow) private var openWindow

    /// キーウィンドウのViewModel（WindowCoordinator経由）
    private var focusedViewModel: BookViewModel? {
        WindowCoordinator.shared.keyWindowViewModel
    }

    /// キーウィンドウがファイルを開いているか
    private var keyWindowHasOpenFile: Bool {
        WindowCoordinator.shared.keyWindowHasOpenFile
    }

    var body: some Scene {
        WindowGroup(id: "main") {
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

                    // SessionGroupManagerに最大件数を設定
                    sessionGroupManager.maxSessionGroupCount = appSettings.maxSessionGroupCount
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(getDefaultWindowSize())
        .commands {
            // ファイルメニューにClose/履歴Export/Importを追加
            CommandGroup(after: .newItem) {
                // Note: .disabled()はAppDelegateのmenuNeedsUpdateで動的に制御
                // SwiftUIのCommands内でObservableを監視すると全ウィンドウ再描画が発生するため

                Button(action: {
                    focusedViewModel?.closeFile()
                }) {
                    Label(L("menu_close_file"), systemImage: "xmark")
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button(action: {
                    editCurrentFileMemo()
                }) {
                    Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                Menu(L("menu_page_settings")) {
                    Button(action: {
                        exportPageSettings()
                    }) {
                        Label(L("menu_export_page_settings"), systemImage: "square.and.arrow.up")
                    }

                    Button(action: {
                        importPageSettings()
                    }) {
                        Label(L("menu_import_page_settings"), systemImage: "square.and.arrow.down")
                    }
                }

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
                    get: { WindowCoordinator.shared.keyWindowShowHistory ?? appSettings.lastHistoryVisible },
                    set: { newValue in
                        WindowCoordinator.shared.setKeyWindowShowHistory(newValue)
                        // 「終了時の状態を復元」モードの場合は保存
                        if appSettings.historyDisplayMode == .restoreLast {
                            appSettings.lastHistoryVisible = newValue
                        }
                    }
                ))
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button(action: {
                    DebugLogger.log("🔄 Menu: Refresh history clicked", level: .normal)
                    historyManager.startBackgroundAccessibilityCheck()
                    imageCatalogManager.startBackgroundAccessibilityCheck()
                }) {
                    Label(L("menu_refresh_history"), systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button(action: {
                    let vm = focusedViewModel
                    let mode = vm?.viewMode == .spread ? "spread" : (vm?.viewMode == .single ? "single" : "nil")
                    DebugLogger.log("🔘 toggleViewMode action: focusedViewModel=\(vm != nil), viewMode=\(mode)", level: .normal)
                    vm?.toggleViewMode()
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
                // Note: .disabled()はAppDelegateのmenuNeedsUpdateで動的に制御

                // 整列メニュー
                Menu(L("menu_sort")) {
                    ForEach(ImageSortMethod.allCases, id: \.self) { method in
                        Button(action: {
                            focusedViewModel?.applySort(method)
                        }) {
                            Label(
                                method.displayName,
                                systemImage: focusedViewModel?.sortMethod == method
                                    ? "checkmark"
                                    : ""
                            )
                        }
                    }

                    Divider()

                    // 逆順トグル
                    // Note: チェックマークはAppDelegateのmenuNeedsUpdateで動的に制御
                    Button(action: {
                        focusedViewModel?.toggleSortReverse()
                    }) {
                        Label(L("menu_sort_reverse"), systemImage: "")
                    }
                }
                // Note: .disabled()はAppDelegateのmenuNeedsUpdateで動的に制御

                // 表示サイズ（フィッティング + ズーム統合）
                Menu(L("menu_display_size")) {
                    Button(action: {
                        focusedViewModel?.setFittingMode(.window)
                    }) {
                        Label(L("menu_fitting_window"), systemImage: "")
                    }
                    Button(action: {
                        focusedViewModel?.setFittingMode(.height)
                    }) {
                        Label(L("menu_fitting_height"), systemImage: "")
                    }
                    Button(action: {
                        focusedViewModel?.setFittingMode(.width)
                    }) {
                        Label(L("menu_fitting_width"), systemImage: "")
                    }
                    Button(action: {
                        focusedViewModel?.setFittingMode(.originalSize)
                    }) {
                        Label(L("menu_fitting_original"), systemImage: "")
                    }
                    // Note: チェックマークはAppDelegateのmenuNeedsUpdateで動的に制御

                    Divider()

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
                }
                // Note: .disabled()はAppDelegateのmenuNeedsUpdateで動的に制御

                // 補間アルゴリズム
                Menu(L("menu_interpolation")) {
                    Button(action: {
                        focusedViewModel?.interpolationMode = .highQuality
                    }) {
                        Label(L("menu_interpolation_high"), systemImage: "")
                    }
                    Button(action: {
                        focusedViewModel?.interpolationMode = .bilinear
                    }) {
                        Label(L("menu_interpolation_bilinear"), systemImage: "")
                    }
                    Button(action: {
                        focusedViewModel?.interpolationMode = .nearestNeighbor
                    }) {
                        Label(L("menu_interpolation_nearest"), systemImage: "")
                    }
                    // Note: チェックマークはAppDelegateのmenuNeedsUpdateで動的に制御
                }
                // Note: .disabled()はAppDelegateのmenuNeedsUpdateで動的に制御

                Divider()

                // ページ設定リセット
                Button(action: {
                    resetPageSettings()
                }) {
                    Label(L("menu_reset_page_settings"), systemImage: "arrow.counterclockwise")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                // Note: .disabled()はAppDelegateのmenuNeedsUpdateで動的に制御

                Divider()

                // ステータスバー表示切替（フルスクリーンの上）
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
                // Note: .disabled()はAppDelegateのmenuNeedsUpdateで動的に制御
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
                .environment(sessionGroupManager)
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
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var sessionManager: SessionManager?
    var appSettings: AppSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // アプリ起動時にフォーカスを取得
        NSApp.activate(ignoringOtherApps: true)

        // 同時読み込み制限を設定（参照が設定されるのを待つ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if let sessionManager = self?.sessionManager,
               let appSettings = self?.appSettings {
                sessionManager.concurrentLoadingLimit = appSettings.concurrentLoadingLimit
            }
        }

        // メニューのデリゲートを設定（メニュー表示時に状態を更新するため）
        // SwiftUIのメニュー構築が完了するまで少し待つ
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupMenuDelegates()
        }
    }

    /// メニューのデリゲートを設定
    private func setupMenuDelegates() {
        guard let mainMenu = NSApp.mainMenu else {
            DebugLogger.log("📁 setupMenuDelegates: mainMenu is nil", level: .normal)
            return
        }

        // デバッグ: 全メニュー項目を出力
        DebugLogger.log("📋 Main menu items: \(mainMenu.items.map { "[\($0.title)]/[\($0.submenu?.title ?? "nil")]" })", level: .normal)

        // "File" メニューを探す（ローカライズ対応のため複数の名前をチェック）
        let fileMenuNames = ["File", "ファイル"]
        // "View" メニューを探す
        let viewMenuNames = ["View", "表示"]

        for menuItem in mainMenu.items {
            if let submenu = menuItem.submenu {
                let title = submenu.title.isEmpty ? menuItem.title : submenu.title

                if fileMenuNames.contains(title) {
                    submenu.delegate = self
                    submenu.autoenablesItems = false
                    DebugLogger.log("📁 File menu delegate set, autoenablesItems=false", level: .normal)
                } else if viewMenuNames.contains(title) {
                    submenu.delegate = self
                    submenu.autoenablesItems = false
                    DebugLogger.log("👁️ View menu delegate set, autoenablesItems=false", level: .normal)
                }
            }
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // メニューが表示される直前に呼ばれる
        let hasOpenFile = WindowCoordinator.shared.keyWindowHasOpenFile
        let viewModel = WindowCoordinator.shared.keyWindowViewModel

        DebugLogger.log("📋 menuNeedsUpdate: menu.title='\(menu.title)', hasOpenFile=\(hasOpenFile), viewModel=\(viewModel != nil)", level: .normal)

        // ファイルメニューの処理
        let fileMenuNames = ["File", "ファイル"]
        if fileMenuNames.contains(menu.title) {
            updateFileMenu(menu, hasOpenFile: hasOpenFile)
            return
        }

        // 表示メニューの処理
        let viewMenuNames = ["View", "表示"]
        if viewMenuNames.contains(menu.title) {
            updateViewMenu(menu, hasOpenFile: hasOpenFile, viewModel: viewModel)
            return
        }

        // サブメニューの処理（整列、表示サイズ、補間）
        let sortTitle = L("menu_sort")
        let displaySizeTitle = L("menu_display_size")
        let interpolationTitle = L("menu_interpolation")

        if menu.title == sortTitle {
            updateSortSubmenu(menu, hasOpenFile: hasOpenFile, viewModel: viewModel)
            return
        }
        if menu.title == displaySizeTitle {
            updateDisplaySizeSubmenu(menu, hasOpenFile: hasOpenFile, viewModel: viewModel)
            return
        }
        if menu.title == interpolationTitle {
            updateInterpolationSubmenu(menu, hasOpenFile: hasOpenFile, viewModel: viewModel)
            return
        }

        DebugLogger.log("📋 menuNeedsUpdate: unhandled menu '\(menu.title)'", level: .normal)
    }

    /// ファイルメニューの項目を更新
    private func updateFileMenu(_ menu: NSMenu, hasOpenFile: Bool) {
        DebugLogger.log("📁 updateFileMenu: hasOpenFile=\(hasOpenFile)", level: .verbose)

        let closeFileTitle = L("menu_close_file")
        let editMemoTitle = L("menu_edit_memo")
        let pageSettingsTitle = L("menu_page_settings")

        for item in menu.items {
            if item.title == closeFileTitle || item.title == editMemoTitle {
                item.isEnabled = hasOpenFile
            }
            // サブメニューも確認（ページ設定メニュー内の項目）
            if let submenu = item.submenu, item.title == pageSettingsTitle {
                for subItem in submenu.items {
                    subItem.isEnabled = hasOpenFile
                }
            }
        }
    }

    /// 表示メニューの項目を更新
    private func updateViewMenu(_ menu: NSMenu, hasOpenFile: Bool, viewModel: BookViewModel?) {
        DebugLogger.log("👁️ updateViewMenu: hasOpenFile=\(hasOpenFile), viewModel=\(viewModel != nil)", level: .normal)

        // ファイルが開いているかどうかで有効/無効を決定
        let singleViewTitle = L("menu_single_view")
        let spreadViewTitle = L("menu_spread_view")
        let sortTitle = L("menu_sort")
        let displaySizeTitle = L("menu_display_size")
        let resetPageSettingsTitle = L("menu_reset_page_settings")
        let statusBarShowTitle = L("menu_show_status_bar")
        let statusBarHideTitle = L("menu_hide_status_bar")

        DebugLogger.log("👁️ Looking for: single='\(singleViewTitle)', spread='\(spreadViewTitle)'", level: .normal)

        // 読み方向のタイトル
        let rtlTitle = L("menu_reading_direction_rtl")
        let ltrTitle = L("menu_reading_direction_ltr")

        for item in menu.items {
            let title = item.title
            DebugLogger.log("👁️ Menu item: '\(title)'", level: .verbose)

            // 見開き表示/単ページ表示 - タイトルとアイコンを動的に更新
            if title == singleViewTitle || title == spreadViewTitle {
                item.isEnabled = hasOpenFile
                // 現在の状態に応じてタイトルとアイコンを更新
                if let vm = viewModel {
                    let isSpread = vm.viewMode == .spread
                    let newTitle = isSpread ? singleViewTitle : spreadViewTitle
                    let newIcon = isSpread ? "rectangle" : "rectangle.split.2x1"
                    if item.title != newTitle {
                        item.title = newTitle
                        item.image = NSImage(systemSymbolName: newIcon, accessibilityDescription: nil)
                        DebugLogger.log("👁️ Updated view mode: '\(title)' -> '\(newTitle)' (icon: \(newIcon))", level: .normal)
                    }
                }
            }
            // 読み進め方向 - タイトルとアイコンを動的に更新
            else if title == rtlTitle || title == ltrTitle {
                item.isEnabled = hasOpenFile
                // 現在の状態に応じてタイトルとアイコンを更新
                if let vm = viewModel {
                    let isRTL = vm.readingDirection == .rightToLeft
                    let newTitle = isRTL ? rtlTitle : ltrTitle
                    let newIcon = isRTL ? "arrow.left" : "arrow.right"
                    if item.title != newTitle {
                        item.title = newTitle
                        item.image = NSImage(systemSymbolName: newIcon, accessibilityDescription: nil)
                        DebugLogger.log("👁️ Updated reading direction: '\(title)' -> '\(newTitle)' (icon: \(newIcon))", level: .normal)
                    }
                }
            }
            // 整列メニュー
            else if title == sortTitle {
                item.isEnabled = hasOpenFile
                // サブメニューにデリゲートを設定して開いた時にも更新されるようにする
                if let submenu = item.submenu {
                    submenu.delegate = self
                    submenu.autoenablesItems = false
                    updateSortSubmenu(submenu, hasOpenFile: hasOpenFile, viewModel: viewModel)
                }
            }
            // 表示サイズメニュー
            else if title == displaySizeTitle {
                item.isEnabled = hasOpenFile
                // サブメニューにデリゲートを設定して開いた時にも更新されるようにする
                if let submenu = item.submenu {
                    submenu.delegate = self
                    submenu.autoenablesItems = false
                    updateDisplaySizeSubmenu(submenu, hasOpenFile: hasOpenFile, viewModel: viewModel)
                }
            }
            // 補間メニュー
            else if title == L("menu_interpolation") {
                item.isEnabled = hasOpenFile
                // サブメニューにデリゲートを設定して開いた時にも更新されるようにする
                if let submenu = item.submenu {
                    submenu.delegate = self
                    submenu.autoenablesItems = false
                    updateInterpolationSubmenu(submenu, hasOpenFile: hasOpenFile, viewModel: viewModel)
                }
            }
            // ページ設定リセット
            else if title == resetPageSettingsTitle {
                item.isEnabled = hasOpenFile
            }
            // ステータスバー表示 - タイトルとアイコンを動的に更新
            else if title == statusBarShowTitle || title == statusBarHideTitle {
                item.isEnabled = hasOpenFile
                // 現在の状態に応じてタイトルとアイコンを更新
                if let vm = viewModel {
                    let isVisible = vm.showStatusBar
                    let newTitle = isVisible ? statusBarHideTitle : statusBarShowTitle
                    let newIcon = isVisible ? "eye.slash" : "eye"
                    if item.title != newTitle {
                        item.title = newTitle
                        item.image = NSImage(systemSymbolName: newIcon, accessibilityDescription: nil)
                        DebugLogger.log("👁️ Updated status bar: '\(title)' -> '\(newTitle)' (icon: \(newIcon))", level: .normal)
                    }
                }
            }
        }
    }

    /// 整列サブメニューの項目を更新
    private func updateSortSubmenu(_ menu: NSMenu, hasOpenFile: Bool, viewModel: BookViewModel?) {
        let reverseTitle = L("menu_sort_reverse")
        let currentSortMethod = viewModel?.sortMethod
        let supportsReverse = currentSortMethod?.supportsReverse ?? false
        let isReversed = viewModel?.isSortReversed ?? false

        // ソート方法のタイトルとenumのマッピング
        let sortMethodTitles: [(String, ImageSortMethod)] = [
            (L("sort_name"), .name),
            (L("sort_natural"), .natural),
            (L("sort_date"), .date),
            (L("sort_random"), .random),
            (L("sort_custom"), .custom)
        ]

        for item in menu.items {
            let title = item.title

            if title == reverseTitle {
                // 逆順は現在のソート方法が逆順をサポートする場合のみ有効
                let enabled = hasOpenFile && supportsReverse
                item.isEnabled = enabled
                // 逆順の場合はチェックマーク、そうでない場合はプレースホルダー
                if isReversed {
                    item.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                } else {
                    // チェックマークと同じサイズの透明プレースホルダー
                    let placeholder = NSImage(size: NSSize(width: 16, height: 16))
                    item.image = placeholder
                }
            } else if let matchedMethod = sortMethodTitles.first(where: { $0.0 == title })?.1 {
                // ソート方法のチェックマーク
                item.isEnabled = hasOpenFile
                item.image = currentSortMethod == matchedMethod
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            } else if !item.isSeparatorItem {
                item.isEnabled = hasOpenFile
            }
        }
    }

    /// 表示サイズサブメニューの項目を更新
    private func updateDisplaySizeSubmenu(_ menu: NSMenu, hasOpenFile: Bool, viewModel: BookViewModel?) {
        let windowTitle = L("menu_fitting_window")
        let heightTitle = L("menu_fitting_height")
        let widthTitle = L("menu_fitting_width")
        let originalSizeTitle = L("menu_fitting_original")

        let currentMode = viewModel?.fittingMode
        // ズームしている場合はチェックを外す（フィッティングモードから外れている状態）
        let isNotZoomed = viewModel?.zoomLevel == 1.0

        for item in menu.items {
            let title = item.title

            if title == windowTitle {
                item.isEnabled = hasOpenFile
                item.image = (currentMode == .window && isNotZoomed)
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            } else if title == heightTitle {
                item.isEnabled = hasOpenFile
                item.image = (currentMode == .height && isNotZoomed)
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            } else if title == widthTitle {
                item.isEnabled = hasOpenFile
                item.image = (currentMode == .width && isNotZoomed)
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            } else if title == originalSizeTitle {
                // オリジナルサイズは見開きモードでは無効
                item.isEnabled = hasOpenFile && viewModel?.viewMode != .spread
                item.image = (currentMode == .originalSize && isNotZoomed)
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            } else if !item.isSeparatorItem {
                item.isEnabled = hasOpenFile
            }
        }
    }

    /// 補間サブメニューの項目を更新
    private func updateInterpolationSubmenu(_ menu: NSMenu, hasOpenFile: Bool, viewModel: BookViewModel?) {
        let highTitle = L("menu_interpolation_high")
        let bilinearTitle = L("menu_interpolation_bilinear")
        let nearestTitle = L("menu_interpolation_nearest")

        let currentMode = viewModel?.interpolationMode

        for item in menu.items {
            let title = item.title
            item.isEnabled = hasOpenFile

            if title == highTitle {
                item.image = currentMode == .highQuality
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            } else if title == bilinearTitle {
                item.image = currentMode == .bilinear
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            } else if title == nearestTitle {
                item.image = currentMode == .nearestNeighbor
                    ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
                    : nil
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 復元中は終了しない
        if sessionManager?.isProcessing == true {
            return false
        }
        // 設定に従って終了するかどうかを決定
        return appSettings?.quitOnLastWindowClosed ?? true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Finderから「このアプリケーションで開く」でファイルが渡される
        // SessionManagerの統合キューに追加
        sessionManager?.addFilesToOpen(urls: urls)
    }
}
