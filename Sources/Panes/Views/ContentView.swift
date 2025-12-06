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
    @Environment(\.openWindow) private var openWindow
    @State private var eventMonitor: Any?
    @State private var myWindowNumber: Int?
    @State private var windowID = UUID()

    // 「このアプリケーションで開く」からのファイル待ち状態
    @State private var isWaitingForFile = false

    // ファイル選択後に開くURLを一時保持（onChangeでトリガー）
    @State private var pendingURLs: [URL] = []

    // 最後に作成されたウィンドウのIDを保持する静的変数
    // nonisolated(unsafe)を使用: NSLockで保護されているためスレッドセーフ
    nonisolated(unsafe) private static var lastCreatedWindowID: UUID?
    nonisolated(unsafe) private static var lastCreatedWindowIDLock = NSLock()

    // 次に作成されるウィンドウがファイル待ち状態かどうか
    nonisolated(unsafe) private static var nextWindowShouldWaitForFile = false

    // セッション復元用のフレーム
    @State private var pendingFrame: CGRect?

    // ウィンドウフレーム追跡用
    @State private var currentWindowFrame: CGRect?

    // 通知オブザーバが登録済みかどうか
    @State private var notificationObserversRegistered = false

    // 画像情報モーダル表示用
    @State private var showImageInfo = false

    // 履歴フィルタ（ファイルを閉じても維持）
    @State private var historyFilterText: String = ""
    @State private var showHistoryFilter: Bool = false

    // メモ編集用
    @State private var showMemoEdit = false
    @State private var editingMemoText = ""
    @State private var editingMemoFileKey: String?  // 履歴エントリ編集時に使用

    // メインビューのフォーカス管理
    @FocusState private var isMainViewFocused: Bool

    @ViewBuilder
    private var mainContent: some View {
        // isWaitingForFileを最優先でチェック（D&D時にローディング画面を表示するため）
        if isWaitingForFile {
            LoadingView()
        } else if viewModel.viewMode == .single, let image = viewModel.currentImage {
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
                totalPages: viewModel.visiblePageCount,
                isSpreadView: true,
                hasSecondPage: viewModel.secondPageImage != nil,
                currentFileName: viewModel.currentFileName,
                isCurrentPageUserForcedSingle: viewModel.isCurrentPageUserForcedSingle,
                isSecondPageUserForcedSingle: viewModel.isSecondPageUserForcedSingle,
                readingDirection: viewModel.readingDirection,
                onJumpToPage: { viewModel.goToPage($0) }
            )
        } else {
            InitialScreenView(
                errorMessage: viewModel.errorMessage,
                filterText: $historyFilterText,
                showFilterField: $showHistoryFilter,
                onOpenFile: openFilePicker,
                onOpenHistoryFile: openHistoryFile,
                onOpenInNewWindow: openInNewWindow,
                onEditMemo: { fileKey, currentMemo in
                    editingMemoFileKey = fileKey
                    editingMemoText = currentMemo ?? ""
                    showMemoEdit = true
                }
            )
            .contextMenu { initialScreenContextMenu }
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

        // 非表示切り替え
        // 単ページモードでは「非表示にする」は無効、「表示する（解除）」は有効
        Button(action: {
            viewModel.toggleHidden(at: pageIndex)
        }) {
            Label(
                viewModel.isHidden(at: pageIndex)
                    ? L("menu_show_page")
                    : L("menu_hide_page"),
                systemImage: viewModel.isHidden(at: pageIndex)
                    ? "eye"
                    : "eye.slash"
            )
        }
        .disabled(viewModel.viewMode == .single && !viewModel.isHidden(at: pageIndex))

        Divider()

        // 画像をクリップボードにコピー
        Button(action: {
            viewModel.copyImageToClipboard(at: pageIndex)
        }) {
            Label(L("menu_copy_image"), systemImage: "doc.on.doc")
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

        // メモ編集
        Button(action: {
            editingMemoText = viewModel.getCurrentMemo() ?? ""
            showMemoEdit = true
        }) {
            Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
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
        Button(action: {
            appSettings.showHistoryOnLaunch.toggle()
        }) {
            Label(
                appSettings.showHistoryOnLaunch
                    ? L("menu_hide_history")
                    : L("menu_show_history_toggle"),
                systemImage: appSettings.showHistoryOnLaunch
                    ? "eye.slash"
                    : "eye"
            )
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

        // メモ編集
        Button(action: {
            editingMemoText = viewModel.getCurrentMemo() ?? ""
            showMemoEdit = true
        }) {
            Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
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
        .focused($isMainViewFocused)
        .focusEffectDisabled()
        .focusedValue(\.bookViewModel, viewModel)
        .background(WindowNumberGetter(windowNumber: $myWindowNumber))
        .navigationTitle(viewModel.windowTitle)
        .onAppear(perform: handleOnAppear)
        .onDisappear(perform: handleOnDisappear)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onChange(of: pendingURLs) { _, newValue in
            if !newValue.isEmpty {
                withAnimation { isWaitingForFile = true }
            }
        }
        .onChange(of: isWaitingForFile) { _, newValue in
            if newValue && !pendingURLs.isEmpty {
                let urls = pendingURLs
                pendingURLs = []
                DebugLogger.log("📬 Opening file via onChange(isWaitingForFile): \(urls.first?.lastPathComponent ?? "unknown")", level: .normal)
                DispatchQueue.main.async { viewModel.openFiles(urls: urls) }
            }
        }
        .onChange(of: viewModel.hasOpenFile) { _, hasFile in
            if hasFile {
                // ファイルが開かれたらローディング状態を解除
                isWaitingForFile = false

                // セッション復元モードの場合はフレームを設定して完了通知
                if let frame = pendingFrame {
                    // 復元フレームでウィンドウを登録
                    sessionManager.registerWindow(
                        id: windowID,
                        filePath: viewModel.currentFilePath ?? "",
                        fileKey: viewModel.currentFileKey,
                        currentPage: viewModel.currentPage,
                        frame: frame
                    )

                    // myWindowNumber がまだ設定されていない場合、ここで取得を試みる
                    if myWindowNumber == nil {
                        // WindowNumberGetter がまだ実行されていない場合、キーウィンドウから取得
                        if let window = NSApp.keyWindow {
                            myWindowNumber = window.windowNumber
                            DebugLogger.log("🪟 Window number captured from keyWindow in onChange: \(window.windowNumber)", level: .normal)
                        }
                    }

                    // フレーム適用は全復元完了後に一括で行う
                    DebugLogger.log("📐 Window ready, waiting for batch frame application: \(windowID)", level: .normal)
                    sessionManager.windowDidFinishLoading(id: windowID)
                    // pendingFrameはフレーム適用時に使用するため保持
                } else if let frame = currentWindowFrame {
                    // 通常モード：現在のフレームでウィンドウを登録
                    sessionManager.registerWindow(
                        id: windowID,
                        filePath: viewModel.currentFilePath ?? "",
                        fileKey: viewModel.currentFileKey,
                        currentPage: viewModel.currentPage,
                        frame: frame
                    )

                    // 統合キューからの読み込み完了を通知
                    if sessionManager.isProcessing {
                        sessionManager.windowDidFinishLoading(id: windowID)
                    }
                }
            } else {
                // セッションマネージャーからも削除
                sessionManager.removeWindow(id: windowID)
                // D&D中でなければローディング状態をリセット（D&D中はisWaitingForFileを維持）
                // Note: isWaitingForFileはファイル読み込み完了時にfalseになる
            }
        }
        .onChange(of: viewModel.currentPage) { _, newPage in
            // ページが変わったらセッションマネージャーを更新
            sessionManager.updateWindowState(id: windowID, currentPage: newPage)
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            // エラーが発生した場合もローディング状態を解除
            if newValue != nil {
                isWaitingForFile = false
            }
        }
        .onChange(of: myWindowNumber) { _, newWindowNumber in
            // WindowNumberGetterでウィンドウ番号が設定されたときにフレームも取得
            if let windowNumber = newWindowNumber,
               currentWindowFrame == nil,
               let window = NSApp.windows.first(where: { $0.windowNumber == windowNumber }) {
                currentWindowFrame = window.frame
                DebugLogger.log("🪟 Window frame captured via onChange(myWindowNumber): \(window.frame)", level: .normal)
                setupWindowFrameObserver(for: window)
            }
        }
        .onChange(of: showHistoryFilter) { _, newValue in
            // フィルタが非表示になったらメインビューにフォーカスを戻す
            if !newValue {
                DispatchQueue.main.async {
                    isMainViewFocused = true
                }
            }
        }
        .onChange(of: showMemoEdit) { _, newValue in
            // メモ編集モーダルが閉じられたらメインビューにフォーカスを戻す
            if !newValue {
                DispatchQueue.main.async {
                    isMainViewFocused = true
                }
            }
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
            // ⌘F でフィルタ表示/非表示（初期画面のみ）
            if press.modifiers.contains(.command) && !press.modifiers.contains(.control) && !viewModel.hasOpenFile {
                showHistoryFilter.toggle()
                if !showHistoryFilter {
                    historyFilterText = ""  // 非表示時にクリア
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.home) { viewModel.goToFirstPage(); return .handled }
        .onKeyPress(.end) { viewModel.goToLastPage(); return .handled }
        .onKeyPress(keys: [.tab]) { _ in viewModel.skipForward(pages: appSettings.pageJumpCount); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "iI")) { press in
            // ⌘I で画像情報表示
            if press.modifiers.contains(.command) && viewModel.hasOpenFile {
                showImageInfo.toggle()
                return .handled
            }
            return .ignored
        }
        .overlay {
            // 画像情報モーダル
            if showImageInfo {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showImageInfo = false }

                ImageInfoView(
                    infos: viewModel.getCurrentImageInfos(),
                    onDismiss: { showImageInfo = false }
                )
            }

            // メモ編集モーダル
            if showMemoEdit {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showMemoEdit = false
                        editingMemoFileKey = nil
                    }

                MemoEditPopover(
                    memo: $editingMemoText,
                    onSave: {
                        let newMemo = editingMemoText.isEmpty ? nil : editingMemoText
                        if let fileKey = editingMemoFileKey {
                            // 履歴エントリのメモを更新
                            historyManager.updateMemo(for: fileKey, memo: newMemo)
                        } else {
                            // 現在開いているファイルのメモを更新
                            viewModel.updateCurrentMemo(newMemo)
                        }
                        showMemoEdit = false
                        editingMemoFileKey = nil
                    },
                    onCancel: {
                        showMemoEdit = false
                        editingMemoFileKey = nil
                    }
                )
            }
        }
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
        if !notificationObserversRegistered {
            notificationObserversRegistered = true
            setupNotificationObservers()
            setupSessionObservers()
        }
    }

    /// ウィンドウフレーム変更の監視を設定
    private func setupWindowFrameObserver(for window: NSWindow) {
        let windowID = self.windowID
        let sessionManager = self.sessionManager
        let appSettings = self.appSettings

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            // queue: .mainなのでMainActorコンテキストで実行される
            MainActor.assumeIsolated {
                if let frame = window?.frame {
                    sessionManager.updateWindowFrame(id: windowID, frame: frame)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            // queue: .mainなのでMainActorコンテキストで実行される
            MainActor.assumeIsolated {
                if let frame = window?.frame {
                    sessionManager.updateWindowFrame(id: windowID, frame: frame)
                    // 最後のウィンドウサイズを保存
                    appSettings.updateLastWindowSize(frame.size)
                }
            }
        }
    }

    /// ファイルオープン通知の監視を設定
    private func setupSessionObservers() {
        let windowID = self.windowID

        // 最初のウィンドウでファイルを開く通知
        NotificationCenter.default.addObserver(
            forName: .openFileInFirstWindow,
            object: nil,
            queue: .main
        ) { _ in
            // 最後に作成されたウィンドウのみが処理
            ContentView.lastCreatedWindowIDLock.lock()
            let lastID = ContentView.lastCreatedWindowID
            let isLastCreated = lastID == windowID
            ContentView.lastCreatedWindowIDLock.unlock()

            DebugLogger.log("📬 openFileInFirstWindow - windowID: \(windowID), lastID: \(String(describing: lastID)), isLast: \(isLastCreated)", level: .normal)

            guard isLastCreated else {
                DebugLogger.log("📬 Ignoring - not the last created window", level: .verbose)
                return
            }

            Task { @MainActor in
                self.openPendingFile()
            }
        }

        // 新しいウィンドウ作成リクエスト（2つ目以降のファイル用）
        NotificationCenter.default.addObserver(
            forName: .needNewWindow,
            object: nil,
            queue: .main
        ) { [openWindow] _ in
            // 最後に作成されたウィンドウのみが処理
            ContentView.lastCreatedWindowIDLock.lock()
            let lastID = ContentView.lastCreatedWindowID
            let isLastCreated = lastID == windowID
            ContentView.lastCreatedWindowIDLock.unlock()

            DebugLogger.log("📬 needNewWindow - windowID: \(windowID), lastID: \(String(describing: lastID)), isLast: \(isLastCreated)", level: .normal)

            guard isLastCreated else {
                DebugLogger.log("📬 Ignoring needNewWindow - not the last created window", level: .verbose)
                return
            }

            // 新しいウィンドウを作成
            Task { @MainActor in
                DebugLogger.log("🪟 Creating new window from windowID: \(windowID)", level: .normal)
                openWindow(id: "new")
                try? await Task.sleep(nanoseconds: 200_000_000)

                // 新しいウィンドウにファイルを開かせる
                NotificationCenter.default.post(
                    name: .openFileInFirstWindow,
                    object: nil,
                    userInfo: nil
                )
            }
        }

        // 全ウィンドウのフレーム一括適用通知を受け取る
        NotificationCenter.default.addObserver(
            forName: .revealAllWindows,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                // 保存されている復元エントリのフレームを適用
                guard let frame = self.pendingFrame else {
                    DebugLogger.log("📐 No pending frame for window: \(windowID)", level: .verbose)
                    return
                }

                let targetFrame = self.validateWindowFrame(frame)
                DebugLogger.log("📐 Applying frame for window: \(windowID) -> \(targetFrame)", level: .normal)

                if let windowNumber = self.myWindowNumber,
                   let window = NSApp.windows.first(where: { $0.windowNumber == windowNumber }) {
                    window.setFrame(targetFrame, display: true, animate: false)
                    DebugLogger.log("📐 Frame applied to window: \(windowNumber)", level: .normal)
                }

                self.pendingFrame = nil
            }
        }
    }

    /// SessionManagerからの保留ファイルを開く
    private func openPendingFile() {
        guard let fileOpen = sessionManager.pendingFileOpen else {
            DebugLogger.log("⚠️ No pending file to open!", level: .normal)
            return
        }
        sessionManager.pendingFileOpen = nil

        DebugLogger.log("🔄 Opening file: \(fileOpen.filePath) windowID: \(windowID)", level: .normal)

        // ファイルがアクセス可能か確認
        let fileExists = FileManager.default.fileExists(atPath: fileOpen.filePath)
        guard fileExists else {
            showFileNotFoundNotification(filePath: fileOpen.filePath)
            sessionManager.windowDidFinishLoading(id: windowID)
            return
        }

        // セッション復元の場合はフレームを保存
        if fileOpen.isSessionRestore, let frame = fileOpen.frame {
            pendingFrame = frame
            DebugLogger.log("📐 Target frame saved: \(frame) windowID: \(windowID)", level: .normal)
        }

        // ファイルを開く
        let url = URL(fileURLWithPath: fileOpen.filePath)
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
                    viewModel?.skipBackward(pages: self.appSettings.pageJumpCount)
                    return nil
                } else {
                    DebugLogger.log("   Tab without shift, passing through", level: .verbose)
                }
            }
            return event
        }
    }

    private func setupNotificationObservers() {
        // 統合キューに移行したため、個別の通知ハンドラは不要になりました
        // setupSessionObservers() で統合的に処理します
    }

    private func handleOnDisappear() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        // セッションマネージャーからウィンドウを削除
        sessionManager.removeWindow(id: windowID)
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
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = [.zip, .cbz, .rar, .cbr, .jpeg, .png, .gif, .webP, .folder]
        openPanel.message = L("drop_files_hint")

        openPanel.begin { response in
            if response == .OK {
                let urls = openPanel.urls
                if !urls.isEmpty {
                    handleSelectedFiles(urls)
                }
            }
        }
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

    private func openInNewWindow(path: String) {
        let url = URL(fileURLWithPath: path)
        // 新しいウィンドウでファイルを開く
        sessionManager.openInNewWindow(url: url)
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
                    DebugLogger.log("📬 Opening file via D&D: \(urls.first?.lastPathComponent ?? "unknown")", level: .normal)
                    // 先にローディング状態にしてから閉じる（初期画面が表示されないように）
                    withAnimation { isWaitingForFile = true }
                    // 既にファイルが開いている場合は一度閉じる（hasOpenFileのonChangeをトリガーするため）
                    if viewModel.hasOpenFile {
                        viewModel.closeFile()
                    }
                    viewModel.openFiles(urls: urls)
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
    @Binding var filterText: String
    @Binding var showFilterField: Bool
    let onOpenFile: () -> Void
    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo)

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
            HistoryListView(filterText: $filterText, showFilterField: $showFilterField, onOpenHistoryFile: onOpenHistoryFile, onOpenInNewWindow: onOpenInNewWindow, onEditMemo: onEditMemo)
        }
    }
}

/// 履歴リスト
struct HistoryListView: View {
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(AppSettings.self) private var appSettings
    @Binding var filterText: String
    @Binding var showFilterField: Bool
    @FocusState private var isFilterFocused: Bool

    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo)

    var body: some View {
        let recentHistory = historyManager.getRecentHistory(limit: appSettings.maxHistoryCount)
        let filteredHistory = filterText.isEmpty
            ? recentHistory
            : recentHistory.filter { matchesFilter($0, pattern: filterText) }

        if appSettings.showHistoryOnLaunch && !recentHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(L("recent_files").dropLast()) [\(recentHistory.count)/\(appSettings.maxHistoryCount)]:")
                    .foregroundColor(.gray)
                    .font(.headline)
                    .padding(.top, 20)

                // フィルタ入力フィールド（⌘+Fで表示/非表示）
                if showFilterField {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField(L("history_filter_placeholder"), text: $filterText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .focused($isFilterFocused)
                            .onExitCommand {
                                filterText = ""
                                showFilterField = false
                            }
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
                    .onAppear {
                        // フィルタ表示時に自動フォーカス
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFilterFocused = true
                        }
                    }
                    .onDisappear {
                        // フィルタ非表示時にフォーカスをクリア（親ビューがキーイベントを受け取れるように）
                        isFilterFocused = false
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredHistory) { entry in
                            HistoryEntryRow(entry: entry, onOpenHistoryFile: onOpenHistoryFile, onOpenInNewWindow: onOpenInNewWindow, onEditMemo: onEditMemo)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
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

    /// フィルタにマッチするかチェック（ワイルドカード対応）
    private func matchesFilter(_ entry: FileHistoryEntry, pattern: String) -> Bool {
        // ワイルドカード文字が含まれている場合は正規表現として処理
        if pattern.contains("*") || pattern.contains("?") {
            let regexPattern = wildcardToRegex(pattern)
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                let fileNameMatch = regex.firstMatch(in: entry.fileName, range: NSRange(entry.fileName.startIndex..., in: entry.fileName)) != nil
                let memoMatch = entry.memo.map { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil } ?? false
                return fileNameMatch || memoMatch
            }
        }
        // 通常の部分一致検索
        return entry.fileName.localizedCaseInsensitiveContains(pattern) ||
               (entry.memo?.localizedCaseInsensitiveContains(pattern) ?? false)
    }

    /// ワイルドカードパターンを正規表現に変換
    private func wildcardToRegex(_ pattern: String) -> String {
        var result = NSRegularExpression.escapedPattern(for: pattern)
        result = result.replacingOccurrences(of: "\\*", with: ".*")
        result = result.replacingOccurrences(of: "\\?", with: ".")
        return result
    }
}

/// 履歴エントリの行
struct HistoryEntryRow: View {
    @Environment(FileHistoryManager.self) private var historyManager

    let entry: FileHistoryEntry
    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo)

    // ツールチップ用（一度だけ生成してキャッシュ）
    @State private var cachedTooltip: String?

    var body: some View {
        // FileHistoryManagerのキャッシュを使用（一度チェックしたらセッション中保持）
        let isAccessible = historyManager.isAccessible(for: entry)

        HStack(spacing: 0) {
            Button(action: {
                if isAccessible {
                    onOpenHistoryFile(entry.filePath)
                }
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.fileName)
                            .foregroundColor(isAccessible ? .white : .gray)
                        Spacer()
                        Text(L("access_count_format", entry.accessCount))
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    // メモがある場合は表示
                    if let memo = entry.memo, !memo.isEmpty {
                        Text(memo)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isAccessible)
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
        .background(Color.white.opacity(isAccessible ? 0.1 : 0.05))
        .cornerRadius(4)
        .help(Text(cachedTooltip ?? ""))
        .onAppear {
            // 表示時に一度だけツールチップを生成してキャッシュ
            if cachedTooltip == nil {
                cachedTooltip = generateTooltip()
            }
        }
        .contextMenu {
            Button(action: {
                onOpenInNewWindow(entry.filePath)
            }) {
                Label(L("menu_open_in_new_window"), systemImage: "macwindow.badge.plus")
            }
            .disabled(!isAccessible)

            Divider()

            Button(action: {
                onEditMemo(entry.fileKey, entry.memo)
            }) {
                Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
            }

            Divider()

            Button(action: {
                revealInFinder()
            }) {
                Label(L("menu_reveal_in_finder"), systemImage: "folder")
            }
            .disabled(!isAccessible)
        }
    }

    /// ツールチップ用のテキストを生成（ファイルアクセスなし）
    private func generateTooltip() -> String {
        var lines: [String] = []

        // ファイルパス
        lines.append(entry.filePath)

        // 書庫の種類（拡張子から判断、ファイルアクセス不要）
        let ext = URL(fileURLWithPath: entry.filePath).pathExtension.lowercased()
        let archiveType = archiveTypeDescription(for: ext)
        if !archiveType.isEmpty {
            lines.append(L("tooltip_archive_type") + ": " + archiveType)
        }

        // 最終アクセス日時（履歴データから、ファイルアクセス不要）
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append(L("tooltip_last_access") + ": " + formatter.string(from: entry.lastAccessDate))

        return lines.joined(separator: "\n")
    }

    /// 拡張子から書庫の種類を取得
    private func archiveTypeDescription(for ext: String) -> String {
        switch ext {
        case "zip":
            return "ZIP"
        case "cbz":
            return "CBZ (Comic Book ZIP)"
        case "rar":
            return "RAR"
        case "cbr":
            return "CBR (Comic Book RAR)"
        case "7z":
            return "7-Zip"
        case "tar":
            return "TAR"
        case "gz", "gzip":
            return "GZIP"
        case "jpg", "jpeg":
            return "JPEG"
        case "png":
            return "PNG"
        case "gif":
            return "GIF"
        case "webp":
            return "WebP"
        default:
            return ext.uppercased()
        }
    }

    /// Finderでファイルを表示
    private func revealInFinder() {
        let url = URL(fileURLWithPath: entry.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

/// グレー半透明スクロールバーのカスタムScrollView
struct CustomScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false

        // カスタムスクローラーを設定（システム設定に従う）
        let scroller = GrayScroller()
        scrollView.verticalScroller = scroller

        // SwiftUIコンテンツをホスト
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = hostingView

        // ドキュメントビューのサイズをスクロールビューの幅に合わせる
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            // コンテンツサイズが変わった時にスクロール領域を更新
            hostingView.invalidateIntrinsicContentSize()
            hostingView.layoutSubtreeIfNeeded()
        }
    }
}

/// グレー半透明のカスタムスクローラー
class GrayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // トラック背景を暗いグレーで描画（「常に表示」設定時用）
        let path = NSBezierPath(roundedRect: slotRect, xRadius: 4, yRadius: 4)
        NSColor.darkGray.withAlphaComponent(0.3).setFill()
        path.fill()
    }

    override func drawKnob() {
        let knobRect = self.rect(for: .knob).insetBy(dx: 2, dy: 2)
        guard !knobRect.isEmpty else { return }

        let path = NSBezierPath(roundedRect: knobRect, xRadius: 4, yRadius: 4)
        NSColor.gray.withAlphaComponent(0.6).setFill()
        path.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        // トラックを描画（「常に表示」設定時）
        if self.scrollerStyle == .legacy {
            self.drawKnobSlot(in: self.rect(for: .knobSlot), highlight: false)
        }
        self.drawKnob()
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

                // macOSのState Restorationを無効化（独自のセッション復元を使用）
                window.isRestorable = false

                // SwiftUIのウィンドウフレーム自動保存を無効化
                window.setFrameAutosaveName("")

                if oldValue != window.windowNumber {
                    DebugLogger.log("🪟 WindowNumberGetter: captured \(window.windowNumber) (was: \(String(describing: oldValue)))", level: .normal)
                }
            }
        }
    }
}
