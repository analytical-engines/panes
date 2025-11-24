import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = BookViewModel()
    @Environment(FileHistoryManager.self) private var historyManager
    @State private var isFilePickerPresented = false
    @Environment(\.openWindow) private var openWindow
    @State private var eventMonitor: Any?
    @State private var myWindowNumber: Int?
    private let windowID = UUID()

    // 最後に作成されたウィンドウのIDを保持する静的変数
    private static var lastCreatedWindowID: UUID?
    private static var lastCreatedWindowIDLock = NSLock()

    var body: some View {
        ZStack {
            // 背景（クリック可能にして全体でフォーカスを受け取る）
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // タップでフォーカスを確保
                }

            if viewModel.viewMode == .single, let image = viewModel.currentImage {
                // 単ページ表示
                VStack(spacing: 0) {
                    // 画像エリア
                    ImageDisplayView(image: image)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 画像タップでもフォーカスを確保
                        }

                    // ステータスバー
                    if viewModel.showStatusBar {
                        HStack {
                            Text(viewModel.archiveFileName)
                                .foregroundColor(.white)
                            Spacer()
                            Text(viewModel.currentFileName)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(viewModel.pageInfo)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                    }
                }
            } else if viewModel.viewMode == .spread, let firstPageImage = viewModel.firstPageImage {
                // 見開き表示
                VStack(spacing: 0) {
                    // 画像エリア
                    SpreadView(
                        readingDirection: viewModel.readingDirection,
                        firstPageImage: firstPageImage,
                        secondPageImage: viewModel.secondPageImage,
                        singlePageAlignment: viewModel.currentPageAlignment
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 画像タップでもフォーカスを確保
                    }

                    // ステータスバー
                    if viewModel.showStatusBar {
                        HStack {
                            Text(viewModel.archiveFileName)
                                .foregroundColor(.white)
                            Spacer()
                            Text(viewModel.currentFileName)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(viewModel.pageInfo)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                    }
                }
            } else {
                // ファイル未選択時の表示
                VStack(spacing: 20) {
                    Text("ImageViewer")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    } else {
                        Text("zipファイルまたは画像ファイルをドロップ")
                            .foregroundColor(.gray)
                    }

                    Button("ファイルを開く") {
                        openFilePicker()
                    }
                    .buttonStyle(.borderedProminent)

                    // 履歴表示
                    let recentHistory = historyManager.getRecentHistory(limit: 20)
                    if !recentHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("最近開いたファイル:")
                                    .foregroundColor(.gray)
                                    .font(.headline)
                                Spacer()
                                Button("すべてクリア") {
                                    historyManager.clearAllHistory()
                                }
                                .foregroundColor(.red)
                                .font(.caption)
                            }
                            .padding(.top, 20)

                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(recentHistory) { entry in
                                        HStack(spacing: 0) {
                                            Button(action: {
                                                if entry.isAccessible {
                                                    openHistoryFile(path: entry.filePath)
                                                }
                                            }) {
                                                HStack {
                                                    Text(entry.fileName)
                                                        .foregroundColor(entry.isAccessible ? .white : .gray)
                                                    Spacer()
                                                    Text("(\(entry.accessCount)回)")
                                                        .foregroundColor(.gray)
                                                        .font(.caption)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!entry.isAccessible)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)

                                            Button(action: {
                                                historyManager.removeEntry(withId: entry.id)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray)
                                                    .opacity(0.6)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.trailing, 8)
                                        }
                                        .background(Color.white.opacity(entry.isAccessible ? 0.1 : 0.05))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                            .frame(maxHeight: 300)
                        }
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusable()  // フォーカス可能にする
        .focusEffectDisabled()  // フォーカスリングを非表示
        .focusedValue(\.bookViewModel, viewModel)  // メニューコマンドからアクセス可能に
        .background(WindowNumberGetter(windowNumber: $myWindowNumber))
        .onAppear {
            // ウィンドウ番号を取得（少し遅延させて確実に取得）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
                    self.myWindowNumber = window.windowNumber
                    DebugLogger.log("🪟 Window number set in onAppear: \(window.windowNumber)", level: .verbose)
                }
            }

            // viewModelに履歴マネージャーを設定
            viewModel.historyManager = historyManager

            // このウィンドウを最後に作成されたウィンドウとして登録
            ContentView.lastCreatedWindowIDLock.lock()
            ContentView.lastCreatedWindowID = windowID
            ContentView.lastCreatedWindowIDLock.unlock()

            // Shift+Tabのキーイベントを直接監視
            // (SwiftUIの.onKeyPressではShift+Tabがフォーカス移動用に予約されているため捕捉できない)
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
                // Tabキーの場合
                if event.keyCode == 48 { // 48 = Tab key
                    DebugLogger.log("🔑 Tab key detected", level: .verbose)
                    DebugLogger.log("   myWindowNumber: \(String(describing: self.myWindowNumber))", level: .verbose)
                    DebugLogger.log("   keyWindow?.windowNumber: \(String(describing: NSApp.keyWindow?.windowNumber))", level: .verbose)

                    // このウィンドウがキーウィンドウかチェック
                    let keyWindowNumber = NSApp.keyWindow?.windowNumber
                    let isMyWindowActive = (self.myWindowNumber == keyWindowNumber)

                    DebugLogger.log("   isMyWindowActive: \(isMyWindowActive)", level: .verbose)

                    guard isMyWindowActive else {
                        DebugLogger.log("   ❌ Not my window, ignoring", level: .verbose)
                        return event
                    }

                    if event.modifierFlags.contains(.shift) {
                        DebugLogger.log("   ✅ Shift+Tab detected in my window, skipping backward", level: .normal)
                        viewModel?.skipBackward(pages: 10)
                        return nil // イベントを消費
                    } else {
                        DebugLogger.log("   Tab without shift, passing through", level: .verbose)
                    }
                }
                return event // 他のイベントは通常通り処理
            }

            // Finderから「このアプリケーションで開く」で新しいウィンドウを開く通知を受け取る
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OpenFilesInNewWindow"),
                object: nil,
                queue: .main
            ) { [openWindow] notification in
                if let urls = notification.userInfo?["urls"] as? [URL] {
                    // Command+Nで新しいウィンドウを開く
                    Task { @MainActor in
                        openWindow(id: "new")
                        // 少し待ってから、新しいウィンドウにファイルオープンの通知を送る
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OpenFilesInNewlyCreatedWindow"),
                            object: nil,
                            userInfo: ["urls": urls]
                        )
                    }
                }
            }

            // 新しく作成されたウィンドウ用のファイルオープン通知
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("OpenFilesInNewlyCreatedWindow"),
                object: nil,
                queue: .main
            ) { [viewModel, windowID] notification in
                // このウィンドウが最後に作成されたウィンドウの場合のみファイルを開く
                ContentView.lastCreatedWindowIDLock.lock()
                let isLastCreated = ContentView.lastCreatedWindowID == windowID
                ContentView.lastCreatedWindowIDLock.unlock()

                guard isLastCreated else { return }

                if let urls = notification.userInfo?["urls"] as? [URL] {
                    Task { @MainActor in
                        viewModel.openFiles(urls: urls)
                    }
                }
            }
        }
        .onDisappear {
            // イベントモニターをクリーンアップ
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onKeyPress(.leftArrow) {
            viewModel.nextPage()  // 右→左なので、左矢印で次ページ
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.previousPage()  // 右→左なので、右矢印で前ページ
            return .handled
        }
        .onKeyPress(keys: [.space]) { press in
            // Shift+Spaceなら前ページ、通常Spaceなら次ページ
            if press.modifiers.contains(.shift) {
                viewModel.previousPage()
            } else {
                viewModel.nextPage()
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { press in
            // Command+Control+Fでフルスクリーン切り替え
            if press.modifiers.contains(.command) && press.modifiers.contains(.control) {
                toggleFullScreen()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.home) {
            viewModel.goToFirstPage()
            return .handled
        }
        .onKeyPress(.end) {
            viewModel.goToLastPage()
            return .handled
        }
        .onKeyPress(keys: [.tab]) { press in
            // 通常Tabで10ページ進む (Shift+Tabは上記のNSEventモニターで処理)
            viewModel.skipForward(pages: 10)
            return .handled
        }
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true  // 複数選択可能に
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .jpeg, .png]
        panel.message = "zipファイルまたは画像ファイルを選択してください"

        if panel.runModal() == .OK {
            let urls = panel.urls
            viewModel.openFiles(urls: urls)
        }
    }

    private func openHistoryFile(path: String) {
        let url = URL(fileURLWithPath: path)
        viewModel.openFiles(urls: [url])
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []

            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    do {
                        let item = try await provider.loadItem(forTypeIdentifier: "public.file-url")
                        if let data = item as? Data,
                           let path = String(data: data, encoding: .utf8),
                           let url = URL(string: path) {
                            urls.append(url)
                        } else if let url = item as? URL {
                            urls.append(url)
                        }
                    } catch {
                        print("Failed to load item: \(error)")
                    }
                }
            }

            // メインスレッドでファイルを開く
            await MainActor.run {
                if !urls.isEmpty {
                    self.viewModel.openFiles(urls: urls)
                }
            }
        }
    }
}

// ウィンドウ番号を取得するヘルパー
struct WindowNumberGetter: NSViewRepresentable {
    @Binding var windowNumber: Int?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // ウィンドウが利用可能になるまで待つ
        DispatchQueue.main.async {
            if let window = nsView.window {
                self.windowNumber = window.windowNumber
                DebugLogger.log("🪟 Window number captured: \(window.windowNumber)", level: .verbose)
            } else {
                DebugLogger.log("⚠️ Window not yet available", level: .verbose)
            }
        }
    }
}
