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

    var body: some Scene {
        WindowGroup {
            ContentView()
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
                        focusedViewModel?.viewMode == .spread ? "Single View" : "Spread View",
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
                            ? "Reading Direction: Right to Left"
                            : "Reading Direction: Left to Right",
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
                            ? "Hide Status Bar"
                            : "Show Status Bar",
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
                            ? "Remove Single Page Attribute"
                            : "Force Single Page Display",
                        systemImage: focusedViewModel?.isCurrentPageForcedSingle == true
                            ? "checkmark.square"
                            : "square"
                    )
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(focusedViewModel == nil)

                Divider()

                // 単ページ配置設定（見開きモード中の単ページ表示時のみ有効）
                Menu("Single Page Alignment") {
                    Button(action: {
                        focusedViewModel?.setCurrentPageAlignment(.right)
                    }) {
                        Label(
                            "Right Side",
                            systemImage: focusedViewModel?.currentPageAlignment == .right
                                ? "checkmark"
                                : ""
                        )
                    }

                    Button(action: {
                        focusedViewModel?.setCurrentPageAlignment(.left)
                    }) {
                        Label(
                            "Left Side",
                            systemImage: focusedViewModel?.currentPageAlignment == .left
                                ? "checkmark"
                                : ""
                        )
                    }

                    Button(action: {
                        focusedViewModel?.setCurrentPageAlignment(.center)
                    }) {
                        Label(
                            "Center (Window Fitting)",
                            systemImage: focusedViewModel?.currentPageAlignment == .center
                                ? "checkmark"
                                : ""
                        )
                    }
                }
                .disabled(focusedViewModel == nil || focusedViewModel?.viewMode != .spread)
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
