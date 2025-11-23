import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = BookViewModel()
    @State private var historyManager = FileHistoryManager()
    @State private var isFilePickerPresented = false
    @Environment(\.openWindow) private var openWindow
    @State private var eventMonitor: Any?

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
        .onAppear {
            // viewModelに履歴マネージャーを設定
            viewModel.historyManager = historyManager

            // Shift+Tabのキーイベントを直接監視
            // (SwiftUIの.onKeyPressではShift+Tabがフォーカス移動用に予約されているため捕捉できない)
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Tabキーの場合
                if event.keyCode == 48 { // 48 = Tab key
                    if event.modifierFlags.contains(.shift) {
                        viewModel.skipBackward(pages: 10)
                        return nil // イベントを消費
                    }
                }
                return event // 他のイベントは通常通り処理
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
