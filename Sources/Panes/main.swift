import SwiftUI
import AppKit
import UniformTypeIdentifiers

// FocusedValuesのキー定義
struct FocusedViewModelKey: FocusedValueKey {
    typealias Value = BookViewModel
}

extension FocusedValues {
    var bookViewModel: FocusedViewModelKey.Value? {
        get { self[FocusedViewModelKey.self] }
        set { self[FocusedViewModelKey.self] = newValue }
    }
}

@main
struct ImageViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.bookViewModel) private var focusedViewModel: BookViewModel?
    @State private var historyManager = FileHistoryManager()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(historyManager)
                .environment(appSettings)
                .onAppear {
                    // ウィンドウを最前面に
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
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
                    .keyboardShortcut("s", modifiers: .command)

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
        }

        // 設定ウィンドウ
        Settings {
            SettingsView()
                .environment(appSettings)
                .environment(historyManager)
        }
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

        savePanel.begin { response in
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
    }

    /// ページ表示設定をImport
    private func importPageSettings() {
        guard let viewModel = focusedViewModel else { return }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = L("import_panel_title")
        openPanel.prompt = L("import_panel_prompt")

        openPanel.begin { response in
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

        savePanel.begin { response in
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
    }

    /// 履歴をImport
    private func importHistory(merge: Bool) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.title = L("import_history_panel_title")
        openPanel.prompt = L("import_panel_prompt")

        openPanel.begin { response in
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
    }
}

// アプリケーションデリゲート
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // アプリ起動時にフォーカスを取得
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 最後のウィンドウを閉じたらアプリを終了
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Finderから「このアプリケーションで開く」でファイルが渡される
        // 新しいウィンドウを開くための通知を送信
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenFilesInNewWindow"),
            object: nil,
            userInfo: ["urls": urls]
        )
    }
}
