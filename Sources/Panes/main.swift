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
}
