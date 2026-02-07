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

// MARK: - Swipe Gesture View

/// トラックパッドスワイプジェスチャーを処理するビュー
/// システム環境設定の「ページ間をスワイプ」に連動
struct SwipeGestureView<Content: View>: NSViewRepresentable {
    let content: Content
    let isEnabled: Bool
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    init(
        isEnabled: Bool = true,
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.isEnabled = isEnabled
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
    }

    func makeNSView(context: Context) -> SwipeableContainerView {
        let containerView = SwipeableContainerView()
        containerView.onSwipeLeft = onSwipeLeft
        containerView.onSwipeRight = onSwipeRight
        containerView.isSwipeEnabled = isEnabled

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        context.coordinator.hostingView = hostingView
        return containerView
    }

    func updateNSView(_ containerView: SwipeableContainerView, context: Context) {
        containerView.onSwipeLeft = onSwipeLeft
        containerView.onSwipeRight = onSwipeRight
        containerView.isSwipeEnabled = isEnabled

        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = content
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var hostingView: NSHostingView<Content>?
    }
}

/// スワイプジェスチャーを受け付けるNSView
class SwipeableContainerView: NSView {
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    var isSwipeEnabled: Bool = true

    /// スワイプ状態
    private enum SwipeState: CustomStringConvertible {
        case idle           // 待機中
        case tracking       // ジェスチャー追跡中（まだ発火していない）
        case triggered      // 発火済み（ジェスチャー終了まで待機）

        var description: String {
            switch self {
            case .idle: return "idle"
            case .tracking: return "tracking"
            case .triggered: return "triggered"
            }
        }
    }

    private var state: SwipeState = .idle
    /// スワイプ検出用の累積値
    private var accumulatedDeltaX: CGFloat = 0
    /// スワイプ検出の閾値
    private let swipeThreshold: CGFloat = 50.0

    override var acceptsFirstResponder: Bool { true }

    private func phaseString(_ phase: NSEvent.Phase) -> String {
        var parts: [String] = []
        if phase.contains(.began) { parts.append("began") }
        if phase.contains(.stationary) { parts.append("stationary") }
        if phase.contains(.changed) { parts.append("changed") }
        if phase.contains(.ended) { parts.append("ended") }
        if phase.contains(.cancelled) { parts.append("cancelled") }
        if phase.contains(.mayBegin) { parts.append("mayBegin") }
        return parts.isEmpty ? "none(\(phase.rawValue))" : parts.joined(separator: ",")
    }

    override func scrollWheel(with event: NSEvent) {
        guard isSwipeEnabled else {
            super.scrollWheel(with: event)
            return
        }

        // デバッグログ
        DebugLogger.log("📜 scrollWheel: phase=\(phaseString(event.phase)) momentum=\(phaseString(event.momentumPhase)) deltaX=\(String(format: "%.1f", event.scrollingDeltaX)) state=\(state) accumulated=\(String(format: "%.1f", accumulatedDeltaX))", level: .minimal)

        // 縦スクロールが優勢な場合は通常のスクロールとして扱う
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) * 2 {
            super.scrollWheel(with: event)
            return
        }

        // 慣性スクロールは無視
        if event.momentumPhase != [] {
            return
        }

        switch state {
        case .idle:
            // ジェスチャー開始
            if event.phase == .began || event.phase == .changed {
                state = .tracking
                accumulatedDeltaX = event.scrollingDeltaX
                DebugLogger.log("📜 → state changed to tracking", level: .minimal)
            }

        case .tracking:
            // ジェスチャー終了チェック
            if event.phase == .ended || event.phase == .cancelled {
                DebugLogger.log("📜 → gesture ended, back to idle", level: .minimal)
                state = .idle
                accumulatedDeltaX = 0
                return
            }

            // 累積
            accumulatedDeltaX += event.scrollingDeltaX

            // 閾値チェック
            if accumulatedDeltaX > swipeThreshold {
                state = .triggered
                DebugLogger.log("📜 → TRIGGERED right swipe!", level: .minimal)
                onSwipeRight?()
            } else if accumulatedDeltaX < -swipeThreshold {
                state = .triggered
                DebugLogger.log("📜 → TRIGGERED left swipe!", level: .minimal)
                onSwipeLeft?()
            }

        case .triggered:
            // ジェスチャー終了を待つ（それまで何もしない）
            if event.phase == .ended || event.phase == .cancelled {
                DebugLogger.log("📜 → gesture ended after trigger, back to idle", level: .minimal)
                state = .idle
                accumulatedDeltaX = 0
            }
        }
    }
}
