import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let rar = UTType(filenameExtension: "rar")!
    static let cbr = UTType(filenameExtension: "cbr")!
    static let cbz = UTType(filenameExtension: "cbz")!
}

struct ContentView: View {
    @State private var viewModel = BookViewModel()
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(SessionManager.self) private var sessionManager
    @State private var isFilePickerPresented = false
    @Environment(\.openWindow) private var openWindow
    @State private var eventMonitor: Any?
    @State private var myWindowNumber: Int?
    @State private var windowID = UUID()

    // 「このアプリケーションで開く」からのファイル待ち状態
    @State private var isWaitingForFile = false

    // ファイル選択後に開くURLを一時保持（onChangeでトリガー）
    @State private var pendingURLs: [URL] = []

    // 最後に作成されたウィンドウのIDを保持する静的変数
    private static var lastCreatedWindowID: UUID?
    private static var lastCreatedWindowIDLock = NSLock()

    // 次に作成されるウィンドウがファイル待ち状態かどうか
    private static var nextWindowShouldWaitForFile = false

    // セッション復元用のエントリ
    @State private var restorationEntry: WindowSessionEntry?

    // 画像表示後に適用するフレーム（復元用）
    @State private var pendingRestorationFrame: CGRect?

    // ウィンドウフレーム追跡用
    @State private var currentWindowFrame: CGRect?

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.viewMode == .single, let image = viewModel.currentImage {
            SinglePageView(
                image: image,
                pageIndex: viewModel.currentPage,
                rotation: viewModel.getRotation(at: viewModel.currentPage),
                flip: viewModel.getFlip(at: viewModel.currentPage),
                showStatusBar: viewModel.showStatusBar,
                archiveFileName: viewModel.archiveFileName,
                currentFileName: viewModel.currentFileName,
                singlePageIndicator: viewModel.singlePageIndicator,
                pageInfo: viewModel.pageInfo,
                contextMenuBuilder: { pageIndex in imageContextMenu(for: pageIndex) }
            )
            .pageIndicatorOverlay(
                archiveName: viewModel.archiveFileName,
                currentPage: viewModel.currentPage,
                totalPages: viewModel.totalPages,
                isSpreadView: false,
                hasSecondPage: false,
                currentFileName: viewModel.currentFileName,
                isCurrentPageUserForcedSingle: viewModel.isCurrentPageUserForcedSingle,
                isSecondPageUserForcedSingle: false,
                readingDirection: viewModel.readingDirection,
                onJumpToPage: { viewModel.goToPage($0) }
            )
            .onAppear { applyPendingRestorationFrame() }
        } else if viewModel.viewMode == .spread, let firstPageImage = viewModel.firstPageImage {
            SpreadPageView(
                readingDirection: viewModel.readingDirection,
                firstPageImage: firstPageImage,
                firstPageIndex: viewModel.currentPage,
                secondPageImage: viewModel.secondPageImage,
                secondPageIndex: viewModel.currentPage + 1,
                singlePageAlignment: viewModel.currentPageAlignment,
                firstPageRotation: viewModel.getRotation(at: viewModel.currentPage),
                firstPageFlip: viewModel.getFlip(at: viewModel.currentPage),
                secondPageRotation: viewModel.getRotation(at: viewModel.currentPage + 1),
                secondPageFlip: viewModel.getFlip(at: viewModel.currentPage + 1),
                showStatusBar: viewModel.showStatusBar,
                archiveFileName: viewModel.archiveFileName,
                currentFileName: viewModel.currentFileName,
                singlePageIndicator: viewModel.singlePageIndicator,
                pageInfo: viewModel.pageInfo,
                contextMenuBuilder: { pageIndex in imageContextMenu(for: pageIndex) }
            )
            .pageIndicatorOverlay(
                archiveName: viewModel.archiveFileName,
                currentPage: viewModel.currentPage,
                totalPages: viewModel.totalPages,
                isSpreadView: true,
                hasSecondPage: viewModel.secondPageImage != nil,
                currentFileName: viewModel.currentFileName,
                isCurrentPageUserForcedSingle: viewModel.isCurrentPageUserForcedSingle,
                isSecondPageUserForcedSingle: viewModel.isSecondPageUserForcedSingle,
                readingDirection: viewModel.readingDirection,
                onJumpToPage: { viewModel.goToPage($0) }
            )
            .onAppear { applyPendingRestorationFrame() }
        } else if isWaitingForFile {
            LoadingView()
        } else {
            InitialScreenView(
                errorMessage: viewModel.errorMessage,
                onOpenFile: openFilePicker,
                onOpenHistoryFile: openHistoryFile
            )
            .contextMenu { initialScreenContextMenu }
        }
    }

    /// 画像表示後にフレームを適用する
    private func applyPendingRestorationFrame() {
        guard let targetFrame = pendingRestorationFrame else { return }
        pendingRestorationFrame = nil

        DebugLogger.log("📐 Starting frame application: \(targetFrame) for windowID: \(windowID)", level: .normal)

        // フレーム適用を複数回行い、SwiftUIのレイアウト調整に対抗する
        // より長い遅延も追加してSwiftUIのリサイズ後にも対応
        for delay in [0.1, 0.3, 0.5, 1.0, 2.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let windowNumber = self.myWindowNumber else {
                    DebugLogger.log("⚠️ Window number not yet available (delay \(delay)s)", level: .normal)
                    return
                }

                if let window = NSApp.windows.first(where: { $0.windowNumber == windowNumber }) {
                    let currentFrame = window.frame
                    if currentFrame != targetFrame {
                        DebugLogger.log("📐 Applying frame (delay \(delay)s): \(targetFrame) to window: \(windowNumber) (was: \(currentFrame))", level: .normal)
                        window.setFrame(targetFrame, display: true, animate: false)
                    } else {
                        DebugLogger.log("📐 Frame already correct (delay \(delay)s): \(targetFrame) window: \(windowNumber)", level: .verbose)
                    }
                } else {
                    DebugLogger.log("❌ Window not found: \(windowNumber) (delay \(delay)s)", level: .normal)
                }
            }
        }
    }

    /// 画像表示部分のコンテキストメニュー（ページ操作 + アーカイブ属性）
    @ViewBuilder
    private func imageContextMenu(for pageIndex: Int) -> some View {
        // === ページ操作 ===
        let _ = DebugLogger.log("🎯 Context menu built for page index: \(pageIndex) (display: \(pageIndex + 1))", level: .verbose)

        Button(action: {
            viewModel.toggleSingleDisplay(at: pageIndex)
        }) {
            Label(
                viewModel.isForcedSingle(at: pageIndex)
                    ? L("menu_remove_single_page_attribute")
                    : L("menu_force_single_page"),
                systemImage: viewModel.isForcedSingle(at: pageIndex)
                    ? "checkmark.square"
                    : "square"
            )
        }

        Menu {
            Button(action: {
                viewModel.setAlignment(.right, at: pageIndex)
            }) {
                HStack {
                    Text(L("menu_align_right"))
                    Spacer()
                    if viewModel.getAlignment(at: pageIndex) == .right {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button(action: {
                viewModel.setAlignment(.left, at: pageIndex)
            }) {
                HStack {
                    Text(L("menu_align_left"))
                    Spacer()
                    if viewModel.getAlignment(at: pageIndex) == .left {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button(action: {
                viewModel.setAlignment(.center, at: pageIndex)
            }) {
                HStack {
                    Text(L("menu_align_center"))
                    Spacer()
                    if viewModel.getAlignment(at: pageIndex) == .center {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label(L("menu_single_page_alignment"), systemImage: "arrow.left.and.right")
        }

        // 回転メニュー
        Menu {
            Button(action: {
                viewModel.rotateClockwise(at: pageIndex)
            }) {
                Label(L("menu_rotate_clockwise"), systemImage: "rotate.right")
            }

            Button(action: {
                viewModel.rotateCounterClockwise(at: pageIndex)
            }) {
                Label(L("menu_rotate_counterclockwise"), systemImage: "rotate.left")
            }

            Divider()

            Button(action: {
                viewModel.rotate180(at: pageIndex)
            }) {
                Label(L("menu_rotate_180"), systemImage: "arrow.up.arrow.down")
            }
        } label: {
            let rotation = viewModel.getRotation(at: pageIndex)
            Label(
                L("menu_rotation"),
                systemImage: rotation == .none ? "arrow.clockwise" : "arrow.clockwise.circle.fill"
            )
        }

        // 反転メニュー
        Menu {
            Button(action: {
                viewModel.toggleHorizontalFlip(at: pageIndex)
            }) {
                HStack {
                    Text(L("menu_flip_horizontal"))
                    Spacer()
                    if viewModel.getFlip(at: pageIndex).horizontal {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button(action: {
                viewModel.toggleVerticalFlip(at: pageIndex)
            }) {
                HStack {
                    Text(L("menu_flip_vertical"))
                    Spacer()
                    if viewModel.getFlip(at: pageIndex).vertical {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            let flip = viewModel.getFlip(at: pageIndex)
            Label(
                L("menu_flip"),
                systemImage: (flip.horizontal || flip.vertical) ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : "arrow.left.and.right.righttriangle.left.righttriangle.right"
            )
        }

        Divider()

        // === アーカイブ属性 ===
        // 表示モード切替
        Button(action: {
            viewModel.toggleViewMode()
        }) {
            Label(
                viewModel.viewMode == .spread
                    ? L("menu_single_view")
                    : L("menu_spread_view"),
                systemImage: viewModel.viewMode == .spread
                    ? "rectangle"
                    : "rectangle.split.2x1"
            )
        }

        // 読み進め方向切替
        Button(action: {
            viewModel.toggleReadingDirection()
        }) {
            Label(
                viewModel.readingDirection == .rightToLeft
                    ? L("menu_reading_direction_rtl")
                    : L("menu_reading_direction_ltr"),
                systemImage: viewModel.readingDirection == .rightToLeft
                    ? "arrow.left"
                    : "arrow.right"
            )
        }

        // ステータスバー表示切替
        Button(action: {
            viewModel.toggleStatusBar()
        }) {
            Label(
                viewModel.showStatusBar
                    ? L("menu_hide_status_bar")
                    : L("menu_show_status_bar"),
                systemImage: viewModel.showStatusBar
                    ? "eye.slash"
                    : "eye"
            )
        }

        Divider()

        // ページ設定サブメニュー
        Menu {
            Button(action: {
                exportPageSettings()
            }) {
                Label(L("menu_export_page_settings"), systemImage: "square.and.arrow.up")
            }

            Button(action: {
                importPageSettings()
            }) {
                Label(L("menu_import_page_settings"), systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(action: {
                resetPageSettings()
            }) {
                Label(L("menu_reset_page_settings"), systemImage: "arrow.counterclockwise")
            }
        } label: {
            Label(L("menu_page_settings"), systemImage: "gearshape")
        }

        Divider()

        // ファイルを閉じる
        Button(action: {
            viewModel.closeFile()
        }) {
            Label(L("menu_close_file"), systemImage: "xmark")
        }
    }

    /// 初期画面のコンテキストメニュー
    @ViewBuilder
    private var initialScreenContextMenu: some View {
        Button(action: openFilePicker) {
            Label(L("open_file"), systemImage: "folder")
        }
    }

    /// 背景部分のコンテキストメニュー（書庫ファイル属性のみ）
    @ViewBuilder
    private var backgroundContextMenu: some View {
        // 表示モード切替
        Button(action: {
            viewModel.toggleViewMode()
        }) {
            Label(
                viewModel.viewMode == .spread
                    ? L("menu_single_view")
                    : L("menu_spread_view"),
                systemImage: viewModel.viewMode == .spread
                    ? "rectangle"
                    : "rectangle.split.2x1"
            )
        }

        // 読み進め方向切替
        Button(action: {
            viewModel.toggleReadingDirection()
        }) {
            Label(
                viewModel.readingDirection == .rightToLeft
                    ? L("menu_reading_direction_rtl")
                    : L("menu_reading_direction_ltr"),
                systemImage: viewModel.readingDirection == .rightToLeft
                    ? "arrow.left"
                    : "arrow.right"
            )
        }

        // ステータスバー表示切替
        Button(action: {
            viewModel.toggleStatusBar()
        }) {
            Label(
                viewModel.showStatusBar
                    ? L("menu_hide_status_bar")
                    : L("menu_show_status_bar"),
                systemImage: viewModel.showStatusBar
                    ? "eye.slash"
                    : "eye"
            )
        }

        Divider()

        // ページ設定サブメニュー
        Menu {
            Button(action: {
                exportPageSettings()
            }) {
                Label(L("menu_export_page_settings"), systemImage: "square.and.arrow.up")
            }

            Button(action: {
                importPageSettings()
            }) {
                Label(L("menu_import_page_settings"), systemImage: "square.and.arrow.down")
            }

            Divider()

            Button(action: {
                resetPageSettings()
            }) {
                Label(L("menu_reset_page_settings"), systemImage: "arrow.counterclockwise")
            }
        } label: {
            Label(L("menu_page_settings"), systemImage: "gearshape")
        }

        Divider()

        // ファイルを閉じる
        Button(action: {
            viewModel.closeFile()
        }) {
            Label(L("menu_close_file"), systemImage: "xmark")
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }
                .contextMenu {
                    if viewModel.hasOpenFile {
                        backgroundContextMenu
                    } else {
                        initialScreenContextMenu
                    }
                }

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
            allowedContentTypes: [.zip, .cbz, .rar, .cbr, .jpeg, .png, .gif, .webP],
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
        .onChange(of: viewModel.hasOpenFile) { _, hasFile in
            if hasFile {
                // 復元モードの場合はフレームを設定して完了通知
                if let entry = restorationEntry {
                    // 復元フレームでウィンドウを登録
                    sessionManager.registerWindow(
                        id: windowID,
                        filePath: viewModel.currentFilePath ?? "",
                        fileKey: viewModel.currentFileKey,
                        currentPage: viewModel.currentPage,
                        frame: entry.frame
                    )

                    // 画像表示後にフレームを適用するために保存
                    let targetFrame = self.validateWindowFrame(entry.frame)
                    pendingRestorationFrame = targetFrame
                    DebugLogger.log("📐 Pending frame for image display: \(targetFrame) windowID: \(windowID)", level: .normal)

                    // myWindowNumber がまだ設定されていない場合、ここで取得を試みる
                    if myWindowNumber == nil {
                        // WindowNumberGetter がまだ実行されていない場合、キーウィンドウから取得
                        if let window = NSApp.keyWindow {
                            myWindowNumber = window.windowNumber
                            DebugLogger.log("🪟 Window number captured from keyWindow in onChange: \(window.windowNumber)", level: .normal)
                        }
                    }

                    // onChange から直接フレームを適用（onAppearより先に実行される可能性があるため）
                    applyPendingRestorationFrame()

                    sessionManager.windowDidFinishLoading(id: windowID)
                    restorationEntry = nil
                } else if let frame = currentWindowFrame {
                    // 通常モード：現在のフレームでウィンドウを登録
                    sessionManager.registerWindow(
                        id: windowID,
                        filePath: viewModel.currentFilePath ?? "",
                        fileKey: viewModel.currentFileKey,
                        currentPage: viewModel.currentPage,
                        frame: frame
                    )
                }
            } else {
                // ファイルが閉じられたらローディング状態をリセット
                isWaitingForFile = false
                // セッションマネージャーからも削除
                sessionManager.removeWindow(id: windowID)
            }
        }
        .onChange(of: viewModel.currentPage) { _, newPage in
            // ページが変わったらセッションマネージャーを更新
            sessionManager.updateWindowState(id: windowID, currentPage: newPage)
        }
        .onKeyPress(keys: [.leftArrow]) { handleLeftArrow($0) }
        .onKeyPress(keys: [.rightArrow]) { handleRightArrow($0) }
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
        // ウィンドウ番号とフレームを取得（WindowNumberGetterで設定された番号を使用）
        // isKeyWindow は複数ウィンドウ作成時に間違ったウィンドウを返す可能性があるため使用しない
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // myWindowNumber は WindowNumberGetter で設定される
            if let windowNumber = self.myWindowNumber,
               let window = NSApp.windows.first(where: { $0.windowNumber == windowNumber }) {
                self.currentWindowFrame = window.frame
                DebugLogger.log("🪟 Window frame captured in onAppear: \(window.frame) windowNumber: \(windowNumber)", level: .verbose)

                // ウィンドウフレーム変更の監視を設定
                setupWindowFrameObserver(for: window)
            } else {
                DebugLogger.log("⚠️ Window not yet available in onAppear, waiting for WindowNumberGetter", level: .verbose)
            }
        }

        // viewModelに履歴マネージャーとアプリ設定を設定
        viewModel.historyManager = historyManager
        viewModel.appSettings = appSettings

        // 履歴マネージャーにもアプリ設定を設定
        historyManager.appSettings = appSettings

        // このウィンドウを最後に作成されたウィンドウとして登録
        ContentView.lastCreatedWindowIDLock.lock()
        let previousID = ContentView.lastCreatedWindowID
        ContentView.lastCreatedWindowID = windowID
        DebugLogger.log("🪟 Registered as lastCreatedWindow: \(windowID) (previous: \(String(describing: previousID)))", level: .normal)
        if ContentView.nextWindowShouldWaitForFile {
            isWaitingForFile = true
            ContentView.nextWindowShouldWaitForFile = false
        }
        ContentView.lastCreatedWindowIDLock.unlock()

        setupEventMonitor()
        setupNotificationObservers()
        setupSessionObservers()
    }

    /// ウィンドウフレーム変更の監視を設定
    private func setupWindowFrameObserver(for window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            if let frame = window?.frame {
                self.currentWindowFrame = frame
                self.sessionManager.updateWindowFrame(id: self.windowID, frame: frame)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            if let frame = window?.frame {
                self.currentWindowFrame = frame
                self.sessionManager.updateWindowFrame(id: self.windowID, frame: frame)
                // 最後のウィンドウサイズを保存
                self.appSettings.updateLastWindowSize(frame.size)
            }
        }
    }

    /// セッション復元通知の監視を設定
    private func setupSessionObservers() {
        // 復元通知を受け取る
        NotificationCenter.default.addObserver(
            forName: .restoreWindow,
            object: nil,
            queue: .main
        ) { notification in
            // 最後に作成されたウィンドウのみが処理
            ContentView.lastCreatedWindowIDLock.lock()
            let lastID = ContentView.lastCreatedWindowID
            let isLastCreated = lastID == windowID
            ContentView.lastCreatedWindowIDLock.unlock()

            DebugLogger.log("📬 restoreWindow notification received - windowID: \(windowID), lastID: \(String(describing: lastID)), isLast: \(isLastCreated)", level: .normal)

            guard isLastCreated else {
                DebugLogger.log("📬 Ignoring - not the last created window", level: .verbose)
                return
            }

            if let entry = notification.userInfo?["entry"] as? WindowSessionEntry {
                DebugLogger.log("📬 Processing entry: \(entry.filePath)", level: .normal)
                restoreFromSession(entry)
            }
        }

        // 新しいウィンドウ作成リクエストを受け取る（2つ目以降のセッション復元用）
        NotificationCenter.default.addObserver(
            forName: .needNewRestoreWindow,
            object: nil,
            queue: .main
        ) { [openWindow] _ in
            // 最後に作成されたウィンドウのみが処理
            ContentView.lastCreatedWindowIDLock.lock()
            let lastID = ContentView.lastCreatedWindowID
            let isLastCreated = lastID == windowID
            ContentView.lastCreatedWindowIDLock.unlock()

            DebugLogger.log("📬 needNewRestoreWindow notification received - windowID: \(windowID), lastID: \(String(describing: lastID)), isLast: \(isLastCreated)", level: .normal)

            guard isLastCreated else {
                DebugLogger.log("📬 Ignoring needNewRestoreWindow - not the last created window", level: .verbose)
                return
            }

            // 新しいウィンドウを作成して復元
            Task { @MainActor in
                DebugLogger.log("🪟 Creating new window for restoration from windowID: \(windowID)", level: .normal)
                openWindow(id: "restore")
                try? await Task.sleep(nanoseconds: 200_000_000)

                // 新しいウィンドウに復元エントリを渡す
                if let entry = sessionManager.pendingRestoreEntry {
                    DebugLogger.log("📬 Posting restoreWindow for: \(entry.filePath)", level: .normal)
                    sessionManager.pendingRestoreEntry = nil
                    NotificationCenter.default.post(
                        name: .restoreWindow,
                        object: nil,
                        userInfo: ["entry": entry]
                    )
                } else {
                    DebugLogger.log("⚠️ No pending restore entry!", level: .normal)
                }
            }
        }
    }

    /// セッションからウィンドウを復元
    private func restoreFromSession(_ entry: WindowSessionEntry) {
        DebugLogger.log("🔄 Restoring window from session: \(entry.filePath) windowID: \(windowID)", level: .normal)

        // ファイルがアクセス可能か確認
        guard entry.isFileAccessible else {
            showFileNotFoundNotification(filePath: entry.filePath)
            sessionManager.windowDidFinishLoading(id: windowID)
            return
        }

        // 復元エントリを保存（フレーム設定は onChange(of: viewModel.hasOpenFile) で行う）
        restorationEntry = entry
        DebugLogger.log("📐 Target frame saved: \(entry.frame) windowID: \(windowID)", level: .normal)

        // ファイルを開く
        let url = URL(fileURLWithPath: entry.filePath)
        isWaitingForFile = true
        pendingURLs = [url]
    }

    /// ウィンドウフレームが画面内に収まるか検証
    private func validateWindowFrame(_ frame: CGRect) -> CGRect {
        guard let screen = NSScreen.main else { return frame }

        let screenFrame = screen.visibleFrame
        var validFrame = frame

        // 画面外にはみ出している場合は調整
        if validFrame.maxX > screenFrame.maxX {
            validFrame.origin.x = screenFrame.maxX - validFrame.width
        }
        if validFrame.minX < screenFrame.minX {
            validFrame.origin.x = screenFrame.minX
        }
        if validFrame.maxY > screenFrame.maxY {
            validFrame.origin.y = screenFrame.maxY - validFrame.height
        }
        if validFrame.minY < screenFrame.minY {
            validFrame.origin.y = screenFrame.minY
        }

        // サイズが画面より大きい場合は縮小
        if validFrame.width > screenFrame.width {
            validFrame.size.width = screenFrame.width
        }
        if validFrame.height > screenFrame.height {
            validFrame.size.height = screenFrame.height
        }

        return validFrame
    }

    /// ファイルが見つからない場合の通知
    private func showFileNotFoundNotification(filePath: String) {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        let alert = NSAlert()
        alert.messageText = L("session_restore_error_title")
        alert.informativeText = String(format: L("session_restore_file_not_found"), fileName)
        alert.alertStyle = .warning
        alert.runModal()
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

        // セッションマネージャーからウィンドウを削除
        sessionManager.removeWindow(id: windowID)
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

    // MARK: - Key Handlers

    private func handleLeftArrow(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.shift) {
            // Shift+←: 右→左なら正方向シフト、左→右なら逆方向シフト
            viewModel.shiftPage(forward: viewModel.readingDirection == .rightToLeft)
        } else {
            viewModel.nextPage()
        }
        return .handled
    }

    private func handleRightArrow(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.shift) {
            // Shift+→: 右→左なら逆方向シフト、左→右なら正方向シフト
            viewModel.shiftPage(forward: viewModel.readingDirection == .leftToRight)
        } else {
            viewModel.previousPage()
        }
        return .handled
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

    // MARK: - Page Settings Helpers

    /// ページ表示設定をExport
    private func exportPageSettings() {
        guard let data = viewModel.exportPageSettings() else { return }

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
    @State private var filterText: String = ""

    let onOpenHistoryFile: (String) -> Void

    var body: some View {
        let recentHistory = historyManager.getRecentHistory(limit: appSettings.maxHistoryCount)
        let filteredHistory = filterText.isEmpty
            ? recentHistory
            : recentHistory.filter { $0.fileName.localizedCaseInsensitiveContains(filterText) }

        if !recentHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(L("recent_files").dropLast()) [\(recentHistory.count)/\(appSettings.maxHistoryCount)]:")
                    .foregroundColor(.gray)
                    .font(.headline)
                    .padding(.top, 20)

                // フィルタ入力フィールド
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField(L("history_filter_placeholder"), text: $filterText)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredHistory) { entry in
                            HistoryEntryRow(entry: entry, onOpenHistoryFile: onOpenHistoryFile)
                        }
                    }
                }
                .frame(maxHeight: 300)

                // フィルタ結果の件数表示
                if !filterText.isEmpty {
                    Text(L("history_filter_result_format", filteredHistory.count, recentHistory.count))
                        .foregroundColor(.gray)
                        .font(.caption)
                }
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
struct SinglePageView<ContextMenu: View>: View {
    let image: NSImage
    let pageIndex: Int
    let rotation: ImageRotation
    let flip: ImageFlip
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String
    let contextMenuBuilder: (Int) -> ContextMenu

    var body: some View {
        VStack(spacing: 0) {
            ImageDisplayView(image: image, rotation: rotation, flip: flip)
                .contextMenu { contextMenuBuilder(pageIndex) }

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
struct SpreadPageView<ContextMenu: View>: View {
    let readingDirection: ReadingDirection
    let firstPageImage: NSImage
    let firstPageIndex: Int
    let secondPageImage: NSImage?
    let secondPageIndex: Int
    let singlePageAlignment: SinglePageAlignment
    let firstPageRotation: ImageRotation
    let firstPageFlip: ImageFlip
    let secondPageRotation: ImageRotation
    let secondPageFlip: ImageFlip
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String
    let contextMenuBuilder: (Int) -> ContextMenu

    var body: some View {
        VStack(spacing: 0) {
            SpreadView(
                readingDirection: readingDirection,
                firstPageImage: firstPageImage,
                firstPageIndex: firstPageIndex,
                secondPageImage: secondPageImage,
                secondPageIndex: secondPageIndex,
                singlePageAlignment: singlePageAlignment,
                firstPageRotation: firstPageRotation,
                firstPageFlip: firstPageFlip,
                secondPageRotation: secondPageRotation,
                secondPageFlip: secondPageFlip,
                contextMenuBuilder: contextMenuBuilder
            )

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
                let oldValue = self.windowNumber
                self.windowNumber = window.windowNumber

                // タイトルバーの文字色を白に設定
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: .darkAqua)

                if oldValue != window.windowNumber {
                    DebugLogger.log("🪟 WindowNumberGetter: captured \(window.windowNumber) (was: \(String(describing: oldValue)))", level: .normal)
                }
            }
        }
    }
}
