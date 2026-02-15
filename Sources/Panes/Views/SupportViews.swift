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

/// サジェスト付きテキストフィールド（メモ/メタデータ編集用）
struct SuggestingTextField: View {
    let placeholder: String
    @Binding var text: String
    let width: CGFloat
    let providers: [any SearchSuggestionProvider]
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var suggestions: [SearchSuggestionItem] = []
    @State private var selectedIndex: Int = 0
    @State private var isShowingSuggestions: Bool = false
    @State private var isHoveringOverSuggestions: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    suggestions = SearchSuggestionEngine.computeSuggestions(for: newValue, providers: providers)
                    isShowingSuggestions = !suggestions.isEmpty
                    selectedIndex = 0
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused && !isHoveringOverSuggestions {
                        isShowingSuggestions = false
                    }
                }
                .onKeyPress(.tab) {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        applySuggestion(suggestions[selectedIndex])
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        selectedIndex = max(0, selectedIndex - 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        if selectedIndex < suggestions.count - 1 {
                            selectedIndex += 1
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    if isShowingSuggestions {
                        isShowingSuggestions = false
                        return .handled
                    }
                    return .ignored
                }
                .onSubmit {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        applySuggestion(suggestions[selectedIndex])
                    } else {
                        onSubmit()
                    }
                }

            if isShowingSuggestions && !suggestions.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                Text(suggestion.displayText)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(index == selectedIndex ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .contentShape(Rectangle())
                                    .id(index)
                                    .onTapGesture {
                                        applySuggestion(suggestion)
                                    }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .frame(width: width)
                .frame(maxHeight: 150)
                .background(Color.black.opacity(0.8))
                .cornerRadius(6)
                .onHover { hovering in
                    isHoveringOverSuggestions = hovering
                    if !hovering && !isFocused {
                        isShowingSuggestions = false
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    private func applySuggestion(_ suggestion: SearchSuggestionItem) {
        text = suggestion.fullText
        isShowingSuggestions = false
    }
}

/// メモ編集用のポップオーバー
struct MemoEditPopover: View {
    @Binding var memo: String
    let providers: [any SearchSuggestionProvider]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L("memo_edit_title"))
                .font(.headline)

            SuggestingTextField(
                placeholder: L("memo_placeholder"),
                text: $memo,
                width: 300,
                providers: providers,
                onSubmit: onSave
            )

            HStack {
                Button(L("cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(L("save")) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

/// 一括メタデータ編集用のポップオーバー
struct BatchMetadataEditPopover: View {
    let itemCount: Int
    @Binding var metadataText: String
    let providers: [any SearchSuggestionProvider]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L("batch_metadata_edit_title"))
                .font(.headline)
            Text(String(format: L("batch_metadata_edit_count"), itemCount))
                .font(.caption)
                .foregroundColor(.secondary)

            SuggestingTextField(
                placeholder: L("batch_metadata_placeholder"),
                text: $metadataText,
                width: 300,
                providers: providers,
                onSubmit: onSave
            )

            HStack {
                Button(L("cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(L("save")) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
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

