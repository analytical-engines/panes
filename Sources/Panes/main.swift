import SwiftUI
import AppKit

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
                .disabled(focusedViewModel == nil)

                Divider()

                // 単ページ配置設定（見開きモード中の単ページ表示時のみ有効）
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
                .disabled(focusedViewModel == nil || focusedViewModel?.viewMode != .spread)
            }
        }

        // 設定ウィンドウ
        Settings {
            SettingsView()
                .environment(appSettings)
                .environment(historyManager)
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
