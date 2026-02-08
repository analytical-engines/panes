import SwiftUI
import AppKit

/// ローディング画面（独自アニメーション）
struct LoadingView: View {
    var phase: String?
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            // 独自のスピナー（円弧を回転）
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.gray, lineWidth: 3)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    // アニメーションを明示的に開始
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            Text(phase ?? L("loading"))
                .foregroundColor(.gray)
        }
    }
}

/// メモ編集用のポップオーバー
struct MemoEditPopover: View {
    @Binding var memo: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(L("memo_edit_title"))
                .font(.headline)

            TextField(L("memo_placeholder"), text: $memo)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .focused($isFocused)
                .onSubmit {
                    onSave()
                }

            HStack {
                Button(L("cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(L("save")) {
                    onSave()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            // 少し遅延させてフォーカスを設定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

// MARK: - Window Number Getter

/// ウィンドウ番号を取得し、タイトルバーの設定を行うヘルパー
struct WindowNumberGetter: NSViewRepresentable {
    @Binding var windowNumber: Int?

    func makeNSView(context: Context) -> NSView {
        let view = WindowNumberGetterView()
        view.onWindowAttached = { window in
            configureWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // ビューが既にウィンドウに追加されている場合は設定
        if let view = nsView as? WindowNumberGetterView {
            view.onWindowAttached = { window in
                configureWindow(window)
            }
            if let window = nsView.window {
                configureWindow(window)
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        let newWindowNumber = window.windowNumber

        // タイトルバーの文字色を白に設定
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)

        // macOSのState Restorationを無効化（独自のセッション復元を使用）
        window.isRestorable = false

        // SwiftUIのウィンドウフレーム自動保存を無効化
        window.setFrameAutosaveName("")

        // ビュー更新サイクル外でStateを変更（undefined behavior回避）
        if self.windowNumber != newWindowNumber {
            DispatchQueue.main.async {
                DebugLogger.log("🪟 WindowNumberGetter: captured \(newWindowNumber) (was: \(String(describing: self.windowNumber)))", level: .normal)
                self.windowNumber = newWindowNumber
            }
        }
    }
}

/// ウィンドウへの追加を検出するカスタムNSView
private class WindowNumberGetterView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            DebugLogger.log("🪟 WindowNumberGetterView: viewDidMoveToWindow called with window \(window.windowNumber)", level: .normal)
            onWindowAttached?(window)
        }
    }
}

