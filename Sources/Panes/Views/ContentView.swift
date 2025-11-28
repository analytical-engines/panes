import SwiftUI
import AppKit

struct ContentView: View {
    @State private var viewModel = BookViewModel()
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(AppSettings.self) private var appSettings
    @State private var isFilePickerPresented = false
    @Environment(\.openWindow) private var openWindow
    @State private var eventMonitor: Any?
    @State private var myWindowNumber: Int?
    private let windowID = UUID()

    // 「このアプリケーションで開く」からのファイル待ち状態
    @State private var isWaitingForFile = false

    // ファイル選択後に開くURLを一時保持（onChangeでトリガー）
    @State private var pendingURLs: [URL] = []

    // 最後に作成されたウィンドウのIDを保持する静的変数
    private static var lastCreatedWindowID: UUID?
    private static var lastCreatedWindowIDLock = NSLock()

    // 次に作成されるウィンドウがファイル待ち状態かどうか
    private static var nextWindowShouldWaitForFile = false

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.viewMode == .single, let image = viewModel.currentImage {
            SinglePageView(
                image: image,
                showStatusBar: viewModel.showStatusBar,
                archiveFileName: viewModel.archiveFileName,
                currentFileName: viewModel.currentFileName,
                singlePageIndicator: viewModel.singlePageIndicator,
                pageInfo: viewModel.pageInfo
            )
        } else if viewModel.viewMode == .spread, let firstPageImage = viewModel.firstPageImage {
            SpreadPageView(
                readingDirection: viewModel.readingDirection,
                firstPageImage: firstPageImage,
                secondPageImage: viewModel.secondPageImage,
                singlePageAlignment: viewModel.currentPageAlignment,
                showStatusBar: viewModel.showStatusBar,
                archiveFileName: viewModel.archiveFileName,
                currentFileName: viewModel.currentFileName,
                singlePageIndicator: viewModel.singlePageIndicator,
                pageInfo: viewModel.pageInfo
            )
        } else if isWaitingForFile {
            LoadingView()
        } else {
            InitialScreenView(
                errorMessage: viewModel.errorMessage,
                onOpenFile: openFilePicker,
                onOpenHistoryFile: openHistoryFile
            )
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            mainContent
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusable()
        .focusEffectDisabled()
        .focusedValue(\.bookViewModel, viewModel)
        .background(WindowNumberGetter(windowNumber: $myWindowNumber))
        .navigationTitle(viewModel.windowTitle)
        .onAppear(perform: handleOnAppear)
        .onDisappear(perform: handleOnDisappear)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.zip, .jpeg, .png],
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
        .onChange(of: pendingURLs) { _, newValue in
            if !newValue.isEmpty {
                withAnimation { isWaitingForFile = true }
            }
        }
        .onChange(of: isWaitingForFile) { _, newValue in
            if newValue && !pendingURLs.isEmpty {
                let urls = pendingURLs
                pendingURLs = []
                DispatchQueue.main.async { viewModel.openFiles(urls: urls) }
            }
        }
        .onKeyPress(.leftArrow) { viewModel.nextPage(); return .handled }
        .onKeyPress(.rightArrow) { viewModel.previousPage(); return .handled }
        .onKeyPress(keys: [.space]) { press in
            if press.modifiers.contains(.shift) { viewModel.previousPage() }
            else { viewModel.nextPage() }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { press in
            if press.modifiers.contains(.command) && press.modifiers.contains(.control) {
                toggleFullScreen()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.home) { viewModel.goToFirstPage(); return .handled }
        .onKeyPress(.end) { viewModel.goToLastPage(); return .handled }
        .onKeyPress(keys: [.tab]) { _ in viewModel.skipForward(pages: 10); return .handled }
    }

    private func handleOnAppear() {
        // ウィンドウ番号を取得（少し遅延させて確実に取得）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
                self.myWindowNumber = window.windowNumber
                DebugLogger.log("🪟 Window number set in onAppear: \(window.windowNumber)", level: .verbose)
            }
        }

        // viewModelに履歴マネージャーとアプリ設定を設定
        viewModel.historyManager = historyManager
        viewModel.appSettings = appSettings

        // 履歴マネージャーにもアプリ設定を設定
        historyManager.appSettings = appSettings

        // このウィンドウを最後に作成されたウィンドウとして登録
        ContentView.lastCreatedWindowIDLock.lock()
        ContentView.lastCreatedWindowID = windowID
        if ContentView.nextWindowShouldWaitForFile {
            isWaitingForFile = true
            ContentView.nextWindowShouldWaitForFile = false
        }
        ContentView.lastCreatedWindowIDLock.unlock()

        setupEventMonitor()
        setupNotificationObservers()
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
            if event.keyCode == 48 {
                DebugLogger.log("🔑 Tab key detected", level: .verbose)
                DebugLogger.log("   myWindowNumber: \(String(describing: self.myWindowNumber))", level: .verbose)
                DebugLogger.log("   keyWindow?.windowNumber: \(String(describing: NSApp.keyWindow?.windowNumber))", level: .verbose)

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
                    return nil
                } else {
                    DebugLogger.log("   Tab without shift, passing through", level: .verbose)
                }
            }
            return event
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenFilesInNewWindow"),
            object: nil,
            queue: .main
        ) { [openWindow] notification in
            if let urls = notification.userInfo?["urls"] as? [URL] {
                ContentView.lastCreatedWindowIDLock.lock()
                ContentView.nextWindowShouldWaitForFile = true
                ContentView.lastCreatedWindowIDLock.unlock()

                Task { @MainActor in
                    openWindow(id: "new")
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenFilesInNewlyCreatedWindow"),
                        object: nil,
                        userInfo: ["urls": urls]
                    )
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenFilesInNewlyCreatedWindow"),
            object: nil,
            queue: .main
        ) { [viewModel, windowID] notification in
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

    private func handleOnDisappear() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            handleSelectedFiles(urls)
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func openFilePicker() {
        isFilePickerPresented = true
    }

    private func handleSelectedFiles(_ urls: [URL]) {
        // withAnimationでアニメーション付きでローディング画面に遷移
        withAnimation {
            pendingURLs = urls
        }
    }

    private func openHistoryFile(path: String) {
        let url = URL(fileURLWithPath: path)
        // pendingURLsを設定するとonChangeがトリガーされる
        pendingURLs = [url]
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
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

            await MainActor.run {
                if !urls.isEmpty {
                    withAnimation {
                        self.pendingURLs = urls
                    }
                }
            }
        }
        return true
    }
}

/// ローディング画面（独自アニメーション）
struct LoadingView: View {
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
            Text(L("loading"))
                .foregroundColor(.gray)
        }
    }
}

/// 初期画面（ファイル未選択時）
struct InitialScreenView: View {
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(AppSettings.self) private var appSettings

    let errorMessage: String?
    let onOpenFile: () -> Void
    let onOpenHistoryFile: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(AppInfo.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                Text(L("drop_files_hint"))
                    .foregroundColor(.gray)
            }

            Button(L("open_file")) {
                onOpenFile()
            }
            .buttonStyle(.borderedProminent)

            // 履歴表示
            HistoryListView(onOpenHistoryFile: onOpenHistoryFile)
        }
    }
}

/// 履歴リスト
struct HistoryListView: View {
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(AppSettings.self) private var appSettings

    let onOpenHistoryFile: (String) -> Void

    var body: some View {
        let recentHistory = historyManager.getRecentHistory(limit: appSettings.maxHistoryCount)

        if !recentHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("recent_files"))
                    .foregroundColor(.gray)
                    .font(.headline)
                    .padding(.top, 20)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(recentHistory) { entry in
                            HistoryEntryRow(entry: entry, onOpenHistoryFile: onOpenHistoryFile)
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

/// 履歴エントリの行
struct HistoryEntryRow: View {
    @Environment(FileHistoryManager.self) private var historyManager

    let entry: FileHistoryEntry
    let onOpenHistoryFile: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                if entry.isAccessible {
                    onOpenHistoryFile(entry.filePath)
                }
            }) {
                HStack {
                    Text(entry.fileName)
                        .foregroundColor(entry.isAccessible ? .white : .gray)
                    Spacer()
                    Text(L("access_count_format", entry.accessCount))
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

/// ステータスバー
struct StatusBarView: View {
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String

    var body: some View {
        HStack {
            Text(archiveFileName)
                .foregroundColor(.white)
            Spacer()
            Text(currentFileName)
                .foregroundColor(.gray)
            Spacer()
            HStack(spacing: 8) {
                if !singlePageIndicator.isEmpty {
                    Text(singlePageIndicator)
                        .foregroundColor(.orange)
                }
                Text(pageInfo)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
}

/// 単ページ表示ビュー
struct SinglePageView: View {
    let image: NSImage
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String

    var body: some View {
        VStack(spacing: 0) {
            ImageDisplayView(image: image)
                .contentShape(Rectangle())
                .onTapGesture { }

            if showStatusBar {
                StatusBarView(
                    archiveFileName: archiveFileName,
                    currentFileName: currentFileName,
                    singlePageIndicator: singlePageIndicator,
                    pageInfo: pageInfo
                )
            }
        }
    }
}

/// 見開き表示ビュー
struct SpreadPageView: View {
    let readingDirection: ReadingDirection
    let firstPageImage: NSImage
    let secondPageImage: NSImage?
    let singlePageAlignment: SinglePageAlignment
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String

    var body: some View {
        VStack(spacing: 0) {
            SpreadView(
                readingDirection: readingDirection,
                firstPageImage: firstPageImage,
                secondPageImage: secondPageImage,
                singlePageAlignment: singlePageAlignment
            )
            .contentShape(Rectangle())
            .onTapGesture { }

            if showStatusBar {
                StatusBarView(
                    archiveFileName: archiveFileName,
                    currentFileName: currentFileName,
                    singlePageIndicator: singlePageIndicator,
                    pageInfo: pageInfo
                )
            }
        }
    }
}

// ウィンドウ番号を取得し、タイトルバーの設定を行うヘルパー
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

                // タイトルバーの文字色を白に設定
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: .darkAqua)

                DebugLogger.log("🪟 Window number captured: \(window.windowNumber)", level: .verbose)
            } else {
                DebugLogger.log("⚠️ Window not yet available", level: .verbose)
            }
        }
    }
}
