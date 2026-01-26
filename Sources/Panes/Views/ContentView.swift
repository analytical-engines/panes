import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let rar = UTType(filenameExtension: "rar")!
    static let cbr = UTType(filenameExtension: "cbr")!
    static let cbz = UTType(filenameExtension: "cbz")!
    static let sevenZip = UTType(filenameExtension: "7z")!
}

struct ContentView: View {
    @State private var viewModel = BookViewModel()
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(ImageCatalogManager.self) private var imageCatalogManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SessionGroupManager.self) private var sessionGroupManager
    @Environment(\.openWindow) private var openWindow
    @State private var eventMonitor: Any?
    @State private var scrollEventMonitor: Any?
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

    // 通知オブザーバのトークン（解除用）
    @State private var notificationObservers: [NSObjectProtocol] = []

    // モーダル表示状態（画像情報、メモ編集）
    @State private var modalState = ModalState()

    // 履歴フィルタ（ファイルを閉じても維持）
    @State private var historyFilterText: String = ""
    @State private var showHistoryFilter: Bool = false
    @State private var historySelectedTab: HistoryTab = .archives
    // スクロール位置復元用（最後に開いたエントリのID）
    @State private var lastOpenedArchiveId: String?
    @State private var lastOpenedImageId: String?
    // スクロールトリガー（初期画面に戻るたびにインクリメント）
    @State private var scrollTrigger: Int = 0

    // 画像カタログからのファイルオープン時に使用する相対パス
    @State private var pendingRelativePath: String?

    // 表示順序変更用（コピー/ペースト方式）
    @State private var copiedPageIndex: Int?

    // ピンチジェスチャー用のベースライン（ジェスチャー開始時のズームレベル）
    @State private var magnificationGestureBaseline: CGFloat = 1.0

    // セッション中の履歴表示状態（起動時にAppSettingsから初期化）
    @State private var showHistory: Bool = true

    // メインビューのフォーカス管理
    @FocusState private var isMainViewFocused: Bool

    // 初期画面のキーボードナビゲーション用
    @State private var selectedHistoryItem: SelectableHistoryItem?
    @State private var visibleHistoryItems: [SelectableHistoryItem] = []
    @FocusState private var isHistorySearchFocused: Bool
    @State private var isShowingSuggestions: Bool = false  // 入力補完候補表示中

    @ViewBuilder
    private var mainContent: some View {
        // isWaitingForFileを最優先でチェック（D&D時にローディング画面を表示するため）
        if isWaitingForFile {
            LoadingView(phase: viewModel.loadingPhase)
        } else if viewModel.viewMode == .single, let image = viewModel.currentImage {
            SinglePageView(
                image: image,
                pageIndex: viewModel.currentPage,
                rotation: viewModel.getRotation(at: viewModel.currentPage),
                flip: viewModel.getFlip(at: viewModel.currentPage),
                fittingMode: viewModel.fittingMode,
                zoomLevel: viewModel.zoomLevel,
                interpolation: viewModel.interpolationMode,
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
                fittingMode: viewModel.fittingMode,
                zoomLevel: viewModel.zoomLevel,
                interpolation: viewModel.interpolationMode,
                showStatusBar: viewModel.showStatusBar,
                archiveFileName: viewModel.archiveFileName,
                currentFileName: viewModel.currentFileName,
                singlePageIndicator: viewModel.singlePageIndicator,
                pageInfo: viewModel.pageInfo,
                copiedPageIndex: copiedPageIndex,
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
                selectedTab: $historySelectedTab,
                lastOpenedArchiveId: $lastOpenedArchiveId,
                lastOpenedImageId: $lastOpenedImageId,
                showHistory: $showHistory,
                scrollTrigger: scrollTrigger,
                selectedItem: $selectedHistoryItem,
                isSearchFocused: $isHistorySearchFocused,
                isShowingSuggestions: $isShowingSuggestions,
                onOpenFile: openFilePicker,
                onOpenHistoryFile: openHistoryFile,
                onOpenInNewWindow: openInNewWindow,
                onEditMemo: { fileKey, currentMemo in
                    modalState.openMemoEditForHistory(fileKey: fileKey, memo: currentMemo)
                },
                onEditImageMemo: { id, currentMemo in
                    modalState.openMemoEditForCatalog(catalogId: id, memo: currentMemo)
                },
                onOpenImageCatalogFile: openImageCatalogFile,
                onRestoreSession: { session in
                    sessionGroupManager.updateLastAccessed(id: session.id)
                    sessionManager.restoreSessionGroup(session)
                },
                onVisibleItemsChange: { items in
                    visibleHistoryItems = items
                },
                onExitSearch: {
                    isMainViewFocused = true
                    if selectedHistoryItem == nil, let first = visibleHistoryItems.first {
                        selectedHistoryItem = first
                    }
                }
            )
            .contextMenu { initialScreenContextMenu }
        }
    }

    /// 画像表示中に履歴をオーバーレイ表示するためのビュー
    @ViewBuilder
    private var historyOverlay: some View {
        ZStack {
            // 半透明の黒背景
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // 履歴リスト
                HistoryListView(
                    filterText: $historyFilterText,
                    showFilterField: $showHistoryFilter,
                    selectedTab: $historySelectedTab,
                    lastOpenedArchiveId: $lastOpenedArchiveId,
                    lastOpenedImageId: $lastOpenedImageId,
                    showHistory: $showHistory,
                    scrollTrigger: scrollTrigger,
                    selectedItem: $selectedHistoryItem,
                    isSearchFocused: $isHistorySearchFocused,
                    isShowingSuggestions: $isShowingSuggestions,
                    onOpenHistoryFile: openHistoryFile,
                    onOpenInNewWindow: openInNewWindow,
                    onEditMemo: { fileKey, currentMemo in
                        modalState.openMemoEditForHistory(fileKey: fileKey, memo: currentMemo)
                    },
                    onEditImageMemo: { id, currentMemo in
                        modalState.openMemoEditForCatalog(catalogId: id, memo: currentMemo)
                    },
                    onOpenImageFile: openImageCatalogFile,
                    onRestoreSession: { session in
                        sessionGroupManager.updateLastAccessed(id: session.id)
                        sessionManager.restoreSessionGroup(session)
                    },
                    onVisibleItemsChange: { items in
                        visibleHistoryItems = items
                    },
                    onExitSearch: {
                        isMainViewFocused = true
                        if selectedHistoryItem == nil, let first = visibleHistoryItems.first {
                            selectedHistoryItem = first
                        }
                    }
                )
            }
            .padding()
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

        // 回転・反転メニュー（壊れた画像の場合は無効化ボタンを表示）
        if viewModel.isBrokenImage(at: pageIndex) {
            Button(action: {}) {
                Label(L("menu_rotation_and_flip"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(true)
        } else {
            Menu {
                // 回転
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

                // 反転
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
            } label: {
                let rotation = viewModel.getRotation(at: pageIndex)
                let flip = viewModel.getFlip(at: pageIndex)
                let hasTransform = rotation != .none || flip.horizontal || flip.vertical
                Label(
                    L("menu_rotation_and_flip"),
                    systemImage: hasTransform ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath"
                )
            }
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

        // 壊れた画像のプレースホルダー縦横切り替え（壊れた画像のみ表示）
        if viewModel.isBrokenImage(at: pageIndex) {
            Button(action: {
                viewModel.togglePlaceholderOrientation(at: pageIndex)
            }) {
                Label(
                    viewModel.isLandscapePlaceholder(at: pageIndex)
                        ? L("menu_placeholder_portrait")
                        : L("menu_placeholder_landscape"),
                    systemImage: viewModel.isLandscapePlaceholder(at: pageIndex)
                        ? "rectangle.portrait"
                        : "rectangle"
                )
            }
        }

        Divider()

        // 画像メモを編集（書庫のメモは履歴リストから編集）
        Button(action: {
            if let catalogId = viewModel.getCurrentImageCatalogId() {
                modalState.openMemoEditForCatalog(catalogId: catalogId, memo: viewModel.getCurrentImageMemo())
            }
        }) {
            Label(L("menu_edit_image_memo"), systemImage: "photo")
        }
        .disabled(!viewModel.hasCurrentImageInCatalog())

        // 画像をクリップボードにコピー
        Button(action: {
            viewModel.copyImageToClipboard(at: pageIndex)
        }) {
            Label(L("menu_copy_image"), systemImage: "doc.on.doc")
        }
        .disabled(viewModel.isBrokenImage(at: pageIndex))

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

        // 表示順序変更メニュー（常に表示、操作時に自動でカスタムモードに切り替え）
        Menu {
            // 移動元としてマーク
            Button(action: {
                viewModel.ensureCustomSortMode()
                copiedPageIndex = pageIndex
            }) {
                Label(
                    copiedPageIndex == pageIndex
                        ? L("menu_page_marked")
                        : L("menu_mark_for_move"),
                    systemImage: copiedPageIndex == pageIndex
                        ? "checkmark.circle.fill"
                        : "circle"
                )
            }

            // ペースト操作（マークされたページがある場合のみ）
            if let copiedIndex = copiedPageIndex, copiedIndex != pageIndex {
                Divider()

                Button(action: {
                    viewModel.movePageBefore(sourceDisplayPage: copiedIndex, targetDisplayPage: pageIndex)
                    copiedPageIndex = nil
                }) {
                    Label(L("menu_insert_before"), systemImage: "arrow.left.to.line")
                }

                Button(action: {
                    viewModel.movePageAfter(sourceDisplayPage: copiedIndex, targetDisplayPage: pageIndex)
                    copiedPageIndex = nil
                }) {
                    Label(L("menu_insert_after"), systemImage: "arrow.right.to.line")
                }
            }

            // マーク解除
            if copiedPageIndex != nil {
                Divider()

                Button(action: {
                    copiedPageIndex = nil
                }) {
                    Label(L("menu_clear_mark"), systemImage: "xmark.circle")
                }
            }

            // カスタム順序をリセット（カスタムモード時のみ表示）
            if viewModel.sortMethod == .custom {
                Divider()

                Button(action: {
                    copiedPageIndex = nil
                    viewModel.resetCustomDisplayOrder()
                }) {
                    Label(L("menu_reset_custom_order"), systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Label(L("menu_display_order"), systemImage: "arrow.up.arrow.down.circle")
        }

        Divider()

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
            showHistory.toggle()
            // 「終了時の状態を復元」モードの場合は現在の状態を保存
            if appSettings.historyDisplayMode == .restoreLast {
                appSettings.lastHistoryVisible = showHistory
            }
        }) {
            Label(
                showHistory
                    ? L("menu_hide_history")
                    : L("menu_show_history_toggle"),
                systemImage: showHistory
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

        Divider()

        // 書庫のメモ編集（書庫ファイル属性）
        Button(action: {
            modalState.openMemoEditForCurrentFile(fileKey: viewModel.currentFileKey, memo: viewModel.getCurrentMemo())
        }) {
            Label(L("menu_edit_archive_memo"), systemImage: "archivebox")
        }

        Divider()

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

            // 画像表示中の履歴オーバーレイ
            if viewModel.hasOpenFile && showHistory {
                historyOverlay
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    // ピンチジェスチャー中：ベースラインから相対的にズームを適用
                    if viewModel.hasOpenFile {
                        viewModel.setZoom(magnificationGestureBaseline * value)
                    }
                }
                .onEnded { value in
                    // ジェスチャー終了時：最終値を確定してベースラインを更新
                    if viewModel.hasOpenFile {
                        viewModel.setZoom(magnificationGestureBaseline * value)
                        magnificationGestureBaseline = viewModel.zoomLevel
                    }
                }
        )
        .onAppear {
            // ベースラインを初期化
            magnificationGestureBaseline = viewModel.zoomLevel
        }
        .onChange(of: viewModel.zoomLevel) { _, newValue in
            // メニューやキーボードでズームが変更された場合にベースラインを更新
            magnificationGestureBaseline = newValue
        }
        .frame(minWidth: 800, minHeight: 600)
        .focusable()
        .focused($isMainViewFocused)
        .focusEffectDisabled()
        // focusedValueは削除：WindowCoordinatorで代替（パフォーマンス改善）
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
                // 画像カタログから開く場合（pendingRelativePathが設定されている場合）は書庫履歴に記録しない
                let shouldRecordToHistory = pendingRelativePath == nil
                DebugLogger.log("📬 Opening file via onChange(isWaitingForFile): \(urls.first?.lastPathComponent ?? "unknown")", level: .normal)
                DispatchQueue.main.async {
                    viewModel.imageCatalogManager = imageCatalogManager
                    viewModel.openFiles(urls: urls, recordToHistory: shouldRecordToHistory)
                }
            }
        }
        .onChange(of: viewModel.hasOpenFile) { _, hasFile in
            if hasFile {
                // ファイルが開かれたらローディング状態を解除
                isWaitingForFile = false

                // 履歴オーバーレイを閉じる
                showHistory = false

                // SwiftUIのフォーカスを設定（.onKeyPressが動作するために必要）
                isMainViewFocused = true

                // このウィンドウをアクティブとしてマーク（メニュー状態の更新に必要）
                if let windowNumber = myWindowNumber {
                    WindowCoordinator.shared.markAsActive(windowNumber: windowNumber)
                }

                // 画像カタログからの相対パス指定があれば、該当ページにジャンプ
                if let relativePath = pendingRelativePath {
                    pendingRelativePath = nil
                    viewModel.goToPageByRelativePath(relativePath)
                }

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
                } else {
                    // フレームがまだ取得できていない場合
                    // isProcessing中なら完了を通知（登録は後でonChange(of: currentWindowFrame)で行う）
                    if sessionManager.isProcessing {
                        sessionManager.windowDidFinishLoading(id: windowID)
                    }
                }
            } else {
                // セッションマネージャーからも削除
                sessionManager.removeWindow(id: windowID)
                // D&D中でなければローディング状態をリセット（D&D中はisWaitingForFileを維持）
                // Note: isWaitingForFileはファイル読み込み完了時にfalseになる

                // 初期画面に戻ったのでスクロール位置復元をトリガー
                scrollTrigger += 1

                // 初期画面に戻ったので、必要に応じて履歴とカタログを再読み込み
                if showHistory {
                    historyManager.notifyHistoryUpdate()
                    imageCatalogManager.notifyCatalogUpdate()
                }

                // 初期画面に戻ったのでフォーカスを復元
                isMainViewFocused = true
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
                // キュー処理中の場合は完了を通知（エラーでもカウントを進める）
                if sessionManager.isProcessing {
                    sessionManager.windowDidFinishLoading(id: windowID)
                }
            }
        }
        .onChange(of: viewModel.showFileIdentityDialog) { oldValue, newValue in
            // ファイル同一性ダイアログがキャンセルされた場合（ダイアログ閉じ＋ファイル未オープン）
            if oldValue && !newValue && !viewModel.hasOpenFile {
                isWaitingForFile = false
                // キュー処理中の場合は完了を通知（キャンセルでもカウントを進める）
                if sessionManager.isProcessing {
                    sessionManager.windowDidFinishLoading(id: windowID)
                }
            }
        }
        .onChange(of: myWindowNumber) { oldWindowNumber, newWindowNumber in
            // WindowNumberGetterでウィンドウ番号が設定されたときにフレームも取得
            if let windowNumber = newWindowNumber,
               currentWindowFrame == nil,
               let window = NSApp.windows.first(where: { $0.windowNumber == windowNumber }) {
                currentWindowFrame = window.frame
                DebugLogger.log("🪟 Window frame captured via onChange(myWindowNumber): \(window.frame)", level: .normal)
                setupWindowFrameObserver(for: window)
            }

            // WindowCoordinatorに登録（focusedValueの代替）
            if let oldNumber = oldWindowNumber {
                WindowCoordinator.shared.unregister(windowNumber: oldNumber)
            }
            if let newNumber = newWindowNumber {
                WindowCoordinator.shared.register(windowNumber: newNumber, viewModel: viewModel)
                WindowCoordinator.shared.registerShowHistory(
                    windowNumber: newNumber,
                    getter: { showHistory },
                    setter: { showHistory = $0 }
                )
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
        .onChange(of: showHistory) { _, newValue in
            // 履歴表示が有効になったら、必要に応じて履歴とカタログを再読み込み
            if newValue {
                historyManager.notifyHistoryUpdate()
                imageCatalogManager.notifyCatalogUpdate()
                // リスト未選択なら検索フィールドにフォーカス
                if selectedHistoryItem == nil {
                    DispatchQueue.main.async {
                        isHistorySearchFocused = true
                    }
                }
            }
        }
        .onChange(of: modalState.showMemoEdit) { _, newValue in
            // メモ編集モーダルが閉じられたらメインビューにフォーカスを戻す
            if !newValue {
                DispatchQueue.main.async {
                    isMainViewFocused = true
                }
            }
        }
        .onKeyPress(keys: [.leftArrow]) { handleLeftArrow($0) }
        .onKeyPress(keys: [.rightArrow]) { handleRightArrow($0) }
        .onKeyPress(keys: [.upArrow]) { handleUpArrow($0) }
        .onKeyPress(keys: [.downArrow]) { handleDownArrow($0) }
        .onKeyPress(keys: [.pageUp]) { handlePageUp($0) }
        .onKeyPress(keys: [.pageDown]) { handlePageDown($0) }
        .onKeyPress(characters: .init(charactersIn: "\r\n")) { handleReturn($0) }
        .onKeyPress(characters: CharacterSet(charactersIn: "mM")) { handleMemoEdit($0) }
        .onKeyPress(keys: [.space]) { handleSpace($0) }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { handleFKey($0) }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.home) { viewModel.goToFirstPage(); return .handled }
        .onKeyPress(.end) { viewModel.goToLastPage(); return .handled }
        .onKeyPress(keys: [.tab]) { handleTab($0) }
        .onKeyPress(characters: CharacterSet(charactersIn: "iI")) { handleImageInfo($0) }
        .onKeyPress(characters: CharacterSet(charactersIn: "oO")) { handleOpenFile($0) }
        .onReceive(NotificationCenter.default.publisher(for: .windowDidBecomeKey)) { notification in
            let start = CFAbsoluteTimeGetCurrent()
            // 自分のウィンドウがフォーカスを得た場合のみ履歴を更新
            guard let windowNumber = notification.userInfo?["windowNumber"] as? Int,
                  windowNumber == myWindowNumber else { return }
            // scrollTrigger をインクリメントして HistoryListView を再描画
            scrollTrigger += 1
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DebugLogger.log("⏱️ onReceive scrollTrigger update: \(String(format: "%.1f", elapsed))ms", level: .normal)
        }
        .overlay { modalOverlays }
    }

    // MARK: - Modal Overlays

    @ViewBuilder
    private var modalOverlays: some View {
        // 画像情報モーダル
        if modalState.showImageInfo {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { modalState.showImageInfo = false }

            ImageInfoView(
                infos: viewModel.getCurrentImageInfos(),
                onDismiss: { modalState.showImageInfo = false }
            )
        }

        // メモ編集モーダル
        if modalState.showMemoEdit {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    modalState.closeMemoEdit()
                }

            MemoEditPopover(
                memo: $modalState.editingMemoText,
                onSave: {
                    let newMemo = modalState.finalMemoText
                    if let fileKey = modalState.editingMemoFileKey {
                        // 履歴エントリのメモを更新
                        historyManager.updateMemo(for: fileKey, memo: newMemo)
                    } else if let catalogId = modalState.editingImageCatalogId {
                        // 画像カタログエントリのメモを更新
                        imageCatalogManager.updateMemo(for: catalogId, memo: newMemo)
                    } else {
                        // 現在開いているファイルのメモを更新
                        viewModel.updateCurrentMemo(newMemo)
                    }
                    modalState.closeMemoEdit()
                },
                onCancel: {
                    modalState.closeMemoEdit()
                }
            )
        }

        // ファイル同一性確認ダイアログ
        if viewModel.showFileIdentityDialog,
           let info = viewModel.fileIdentityDialogInfo {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { }  // 背景タップでは閉じない

            FileIdentityDialog(
                existingFileName: info.existingEntry.fileName,
                newFileName: info.newFileName,
                onChoice: { choice in
                    viewModel.handleFileIdentityChoice(choice)
                }
            )
        }

        // パスワード入力ダイアログ
        if viewModel.showPasswordDialog,
           let info = viewModel.passwordDialogInfo {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { }  // 背景タップでは閉じない

            PasswordDialog(
                fileName: info.fileName,
                errorMessage: info.errorMessage,
                onSubmit: { password, shouldSave in
                    viewModel.handlePasswordSubmit(password: password, shouldSave: shouldSave)
                    // フォーカスを復元
                    DispatchQueue.main.async {
                        isMainViewFocused = true
                    }
                },
                onCancel: {
                    viewModel.handlePasswordCancel()
                    // ローディング状態をリセット
                    isWaitingForFile = false
                    // キュー処理中の場合は完了を通知
                    if sessionManager.isProcessing {
                        sessionManager.windowDidFinishLoading(id: windowID)
                    }
                    // フォーカスを復元
                    DispatchQueue.main.async {
                        isMainViewFocused = true
                    }
                }
            )
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

        // viewModelに履歴マネージャー、画像カタログマネージャー、アプリ設定を設定
        viewModel.historyManager = historyManager
        viewModel.imageCatalogManager = imageCatalogManager
        viewModel.appSettings = appSettings

        // 履歴マネージャーにもアプリ設定を設定
        historyManager.appSettings = appSettings

        // 起動時の履歴表示状態を設定から初期化
        showHistory = appSettings.shouldShowHistoryOnLaunch

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

        setupEventMonitors()
        if !notificationObserversRegistered {
            notificationObserversRegistered = true
            setupNotificationObservers()
            setupSessionObservers()
        }

        // 起動時のバックグラウンドアクセス可否チェックを開始（一度だけ実行）
        historyManager.startInitialAccessibilityCheck()
        imageCatalogManager.startInitialAccessibilityCheck()
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
                    // セッション復元中（pendingFrameがある間）は lastWindowSize を更新しない
                    // 復元完了後に目的のフレームが適用されてから更新される
                    if self.pendingFrame == nil {
                        appSettings.updateLastWindowSize(frame.size)
                    }
                }
            }
        }

        // ウィンドウがフォーカスされた時に履歴/カタログを更新
        let viewModel = self.viewModel
        let windowNumber = window.windowNumber
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let focusStart = CFAbsoluteTimeGetCurrent()
                // このウィンドウをアクティブとしてマーク
                WindowCoordinator.shared.markAsActive(windowNumber: windowNumber)

                // 初期画面を表示中（ファイルを開いていない）場合のみ履歴を更新
                // 通知を発行し、該当ウィンドウのみが .onReceive で受け取って更新する
                // デバウンス: 500ms以内の連続イベントは無視
                if !viewModel.hasOpenFile {
                    if WindowCoordinator.shared.shouldPostFocusNotification(for: windowNumber) {
                        DebugLogger.log("🔵 Posting windowDidBecomeKey for window \(windowNumber)", level: .normal)
                        NotificationCenter.default.post(
                            name: .windowDidBecomeKey,
                            object: nil,
                            userInfo: ["windowNumber": windowNumber]
                        )
                    }
                }
                let focusElapsed = (CFAbsoluteTimeGetCurrent() - focusStart) * 1000
                DebugLogger.log("⏱️ Focus handler total: \(String(format: "%.1f", focusElapsed))ms (window \(windowNumber), hasOpenFile=\(viewModel.hasOpenFile))", level: .normal)
            }
        }
    }

    /// ファイルオープン通知の監視を設定
    private func setupSessionObservers() {
        let windowID = self.windowID

        // 最後に作成されたウィンドウで待機中ファイルを開く通知
        let observer1 = NotificationCenter.default.addObserver(
            forName: .openPendingFileInLastWindow,
            object: nil,
            queue: .main
        ) { _ in
            // 最後に作成されたウィンドウのみが処理
            // lastCreatedWindowIDがnilの場合は自分を登録して処理
            ContentView.lastCreatedWindowIDLock.lock()
            var lastID = ContentView.lastCreatedWindowID
            var shouldProcess = false
            if lastID == nil {
                // 誰も担当していないので自分が担当する
                ContentView.lastCreatedWindowID = windowID
                lastID = windowID
                shouldProcess = true
                DebugLogger.log("📬 openPendingFileInLastWindow - windowID: \(windowID) claimed ownership (was nil)", level: .normal)
            } else {
                shouldProcess = lastID == windowID
            }
            ContentView.lastCreatedWindowIDLock.unlock()

            DebugLogger.log("📬 openPendingFileInLastWindow - windowID: \(windowID), lastID: \(String(describing: lastID)), shouldProcess: \(shouldProcess)", level: .normal)

            guard shouldProcess else {
                DebugLogger.log("📬 Ignoring - not the last created window", level: .verbose)
                return
            }

            Task { @MainActor in
                // myWindowNumberが設定されるまで少し待つ
                var attempts = 0
                while self.myWindowNumber == nil && attempts < 20 {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    attempts += 1
                }

                // ウィンドウがまだ存在するか確認
                guard let windowNumber = self.myWindowNumber,
                      NSApp.windows.contains(where: { $0.windowNumber == windowNumber }) else {
                    DebugLogger.log("📬 Ignoring - window no longer exists: \(windowID) (after \(attempts) attempts)", level: .normal)
                    return
                }
                self.openPendingFile()
            }
        }
        notificationObservers.append(observer1)

        // 新しいウィンドウ作成リクエスト（2つ目以降のファイル用）
        let observer2 = NotificationCenter.default.addObserver(
            forName: .needNewWindow,
            object: nil,
            queue: .main
        ) { [openWindow] _ in
            // 最後に作成されたウィンドウのみが処理
            // lastCreatedWindowIDがnilの場合は自分を登録して処理
            ContentView.lastCreatedWindowIDLock.lock()
            var lastID = ContentView.lastCreatedWindowID
            var shouldProcess = false
            if lastID == nil {
                // 誰も担当していないので自分が担当する
                ContentView.lastCreatedWindowID = windowID
                lastID = windowID
                shouldProcess = true
                DebugLogger.log("📬 needNewWindow - windowID: \(windowID) claimed ownership (was nil)", level: .normal)
            } else {
                shouldProcess = lastID == windowID
            }
            ContentView.lastCreatedWindowIDLock.unlock()

            DebugLogger.log("📬 needNewWindow - windowID: \(windowID), lastID: \(String(describing: lastID)), shouldProcess: \(shouldProcess)", level: .normal)

            guard shouldProcess else {
                DebugLogger.log("📬 Ignoring needNewWindow - not the last created window", level: .verbose)
                return
            }

            // 新しいウィンドウを作成（または空のウィンドウで開く）
            Task { @MainActor in
                // myWindowNumberが設定されるまで少し待つ
                var attempts = 0
                while self.myWindowNumber == nil && attempts < 20 {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    attempts += 1
                }

                // ウィンドウがまだ存在するか確認
                guard let windowNumber = self.myWindowNumber,
                      NSApp.windows.contains(where: { $0.windowNumber == windowNumber }) else {
                    DebugLogger.log("📬 Ignoring needNewWindow - window no longer exists: \(windowID) (after \(attempts) attempts)", level: .normal)
                    return
                }

                // このウィンドウがファイルを開いていなければ、自分で開く
                // ただし forceNewWindow フラグが立っている場合は新規ウィンドウを作成
                let forceNew = self.sessionManager.pendingFileOpen?.forceNewWindow ?? false
                if !self.viewModel.hasOpenFile && !forceNew {
                    DebugLogger.log("📬 Using empty window for file: \(windowID)", level: .normal)
                    self.openPendingFile()
                    return
                }

                DebugLogger.log("🪟 Creating new window from windowID: \(windowID)", level: .normal)
                openWindow(id: "main")
                try? await Task.sleep(nanoseconds: 200_000_000)

                // 新しいウィンドウにファイルを開かせる
                NotificationCenter.default.post(
                    name: .openPendingFileInLastWindow,
                    object: nil,
                    userInfo: nil
                )
            }
        }
        notificationObservers.append(observer2)

        // 全ウィンドウのフレーム一括適用通知を受け取る
        let observer3 = NotificationCenter.default.addObserver(
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
        notificationObservers.append(observer3)
    }

    /// 通知オブザーバを解除
    private func removeNotificationObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        notificationObserversRegistered = false
        DebugLogger.log("🧹 Notification observers removed for window: \(windowID)", level: .normal)
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

    // MARK: - Event Monitors

    private func setupEventMonitors() {
        teardownEventMonitors()
        setupKeyDownMonitor()
        setupScrollWheelMonitor()
    }

    private func teardownEventMonitors() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
            scrollEventMonitor = nil
        }
    }

    private func setupKeyDownMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
            // 自分のウィンドウか確認
            guard self.myWindowNumber == NSApp.keyWindow?.windowNumber else {
                return event
            }

            // カスタムショートカットをチェック
            if let action = CustomShortcutManager.shared.findAction(for: event) {
                DebugLogger.log("🔑 Custom shortcut: \(action.rawValue)", level: .normal)
                if self.executeShortcutAction(action, viewModel: viewModel) {
                    return nil  // イベントを消費
                }
            }

            // 既存のハードコードショートカット（Shift+Tab）
            if event.keyCode == 48 {
                DebugLogger.log("🔑 Tab key detected", level: .verbose)

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

    private func setupScrollWheelMonitor() {
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak viewModel] event in
            // ⌘キーが押されているか確認
            guard event.modifierFlags.contains(.command) else {
                return event
            }

            // 自分のウィンドウか確認
            guard self.myWindowNumber == NSApp.keyWindow?.windowNumber else {
                return event
            }

            // ファイルが開いているか確認
            guard viewModel?.hasOpenFile == true else {
                return event
            }

            // スクロール量を取得（縦スクロールを使用）
            let delta = event.scrollingDeltaY

            // 感度調整（スクロール量に応じてズーム）
            let zoomFactor: CGFloat = 1.0 + (delta * 0.01)

            if let currentZoom = viewModel?.zoomLevel {
                viewModel?.setZoom(currentZoom * zoomFactor)
            }

            // イベントを消費（通常のスクロールとして処理しない）
            return nil
        }
    }

    /// カスタムショートカットのアクションを実行
    /// - Returns: アクションが実行された場合はtrue
    private func executeShortcutAction(_ action: ShortcutAction, viewModel: BookViewModel?) -> Bool {
        guard let viewModel = viewModel else { return false }

        // ファイルが開いていない場合は一部のアクションのみ許可
        if !viewModel.hasOpenFile {
            return false
        }

        switch action {
        case .nextPage:
            viewModel.nextPage()
        case .previousPage:
            viewModel.previousPage()
        case .skipForward:
            viewModel.skipForward(pages: appSettings.pageJumpCount)
        case .skipBackward:
            viewModel.skipBackward(pages: appSettings.pageJumpCount)
        case .goToFirstPage:
            viewModel.goToFirstPage()
        case .goToLastPage:
            viewModel.goToLastPage()
        case .toggleFullScreen:
            toggleFullScreen()
        case .toggleViewMode:
            viewModel.toggleViewMode()
        case .toggleReadingDirection:
            viewModel.toggleReadingDirection()
        case .zoomIn:
            viewModel.zoomIn()
        case .zoomOut:
            viewModel.zoomOut()
        case .closeFile:
            viewModel.closeFile()
        case .fitToWindow:
            viewModel.setFittingMode(.window)
        case .fitToOriginalSize:
            viewModel.setFittingMode(.originalSize)
        }

        return true
    }

    private func setupNotificationObservers() {
        // 統合キューに移行したため、個別の通知ハンドラは不要になりました
        // setupSessionObservers() で統合的に処理します
    }

    private func handleOnDisappear() {
        teardownEventMonitors()

        // 通知オブザーバを解除（メモリリーク防止）
        removeNotificationObservers()

        // WindowCoordinatorから解除
        if let windowNumber = myWindowNumber {
            WindowCoordinator.shared.unregister(windowNumber: windowNumber)
        }

        // lastCreatedWindowIDが自分なら更新（閉じたウィンドウを指さないように）
        ContentView.lastCreatedWindowIDLock.lock()
        if ContentView.lastCreatedWindowID == windowID {
            ContentView.lastCreatedWindowID = nil
            DebugLogger.log("🪟 lastCreatedWindowID cleared (window closed): \(windowID)", level: .normal)
        }
        ContentView.lastCreatedWindowIDLock.unlock()

        // セッションマネージャーからウィンドウを削除
        sessionManager.removeWindow(id: windowID)
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    // MARK: - Key Handlers

    /// 初期画面で履歴ナビゲーションが可能な状態か（ファイル未開封かつ履歴あり）
    private var canNavigateHistory: Bool {
        !viewModel.hasOpenFile && !visibleHistoryItems.isEmpty
    }

    /// 履歴リストのキーボードナビゲーションが可能な状態か（候補表示中・検索フォーカス中を除く）
    private var canNavigateHistoryList: Bool {
        canNavigateHistory && !isShowingSuggestions && !isHistorySearchFocused
    }

    private func handleLeftArrow(_ press: KeyPress) -> KeyPress.Result {
        // ファイルを開いている時のみページ送り（検索フィールドへの入力を妨げない）
        guard viewModel.hasOpenFile else { return .ignored }
        if press.modifiers.contains(.shift) {
            // Shift+←: 右→左なら正方向シフト、左→右なら逆方向シフト
            viewModel.shiftPage(forward: viewModel.readingDirection == .rightToLeft)
        } else {
            viewModel.nextPage()
        }
        return .handled
    }

    private func handleRightArrow(_ press: KeyPress) -> KeyPress.Result {
        // ファイルを開いている時のみページ送り（検索フィールドへの入力を妨げない）
        guard viewModel.hasOpenFile else { return .ignored }
        if press.modifiers.contains(.shift) {
            // Shift+→: 右→左なら逆方向シフト、左→右なら正方向シフト
            viewModel.shiftPage(forward: viewModel.readingDirection == .leftToRight)
        } else {
            viewModel.previousPage()
        }
        return .handled
    }

    private func handleUpArrow(_ press: KeyPress) -> KeyPress.Result {
        guard canNavigateHistoryList else { return .ignored }

        if let current = selectedHistoryItem,
           let currentIndex = visibleHistoryItems.firstIndex(where: { $0.id == current.id }) {
            if currentIndex > 0 {
                selectedHistoryItem = visibleHistoryItems[currentIndex - 1]
            } else {
                // 先頭にいる場合は検索フィールドにフォーカス
                selectedHistoryItem = nil
                isHistorySearchFocused = true
            }
        } else {
            // 選択がなければ最後のアイテムを選択
            selectedHistoryItem = visibleHistoryItems.last
        }
        return .handled
    }

    private func handleDownArrow(_ press: KeyPress) -> KeyPress.Result {
        guard canNavigateHistory else { return .ignored }
        guard !isShowingSuggestions else { return .ignored }

        // 検索フィールドにフォーカス中は、フォーカスを外してリストの先頭を選択
        if isHistorySearchFocused {
            isHistorySearchFocused = false
            isMainViewFocused = true
            selectedHistoryItem = visibleHistoryItems.first
            return .handled
        }

        if let current = selectedHistoryItem,
           let currentIndex = visibleHistoryItems.firstIndex(where: { $0.id == current.id }) {
            if currentIndex < visibleHistoryItems.count - 1 {
                selectedHistoryItem = visibleHistoryItems[currentIndex + 1]
            }
        } else {
            // 選択がなければ最初のアイテムを選択
            selectedHistoryItem = visibleHistoryItems.first
        }
        return .handled
    }

    /// PageUp/PageDownで移動するアイテム数
    private let pageScrollCount = 10

    private func handlePageUp(_ press: KeyPress) -> KeyPress.Result {
        guard canNavigateHistoryList else { return .ignored }
        selectHistoryItem(byOffset: -pageScrollCount)
        return .handled
    }

    private func handlePageDown(_ press: KeyPress) -> KeyPress.Result {
        guard canNavigateHistoryList else { return .ignored }
        selectHistoryItem(byOffset: pageScrollCount)
        return .handled
    }

    /// 履歴リストの選択を指定オフセット分移動する
    private func selectHistoryItem(byOffset offset: Int) {
        if let current = selectedHistoryItem,
           let currentIndex = visibleHistoryItems.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(visibleHistoryItems.count - 1, currentIndex + offset))
            selectedHistoryItem = visibleHistoryItems[newIndex]
        } else {
            selectedHistoryItem = visibleHistoryItems.first
        }
    }

    private func handleReturn(_ press: KeyPress) -> KeyPress.Result {
        // 初期画面でのみ履歴アイテムを開く
        guard !viewModel.hasOpenFile else { return .ignored }
        guard !isHistorySearchFocused else { return .ignored }  // 検索フィールドにフォーカス中は無視（IME変換確定と干渉するため）
        guard let selected = selectedHistoryItem else { return .ignored }

        let openInNew = press.modifiers.contains(.shift)  // ⇧+Enterで新しいウィンドウ

        switch selected {
        case .archive(_, let filePath):
            if openInNew {
                openInNewWindow(path: filePath)
            } else {
                openHistoryFile(path: filePath)
            }
        case .standaloneImage(_, let filePath):
            if openInNew {
                openInNewWindow(path: filePath)
            } else {
                openImageCatalogFile(path: filePath, relativePath: nil)
            }
        case .archiveContentImage(_, let parentPath, let relativePath):
            if openInNew {
                openInNewWindow(path: parentPath)  // 親アーカイブを新しいウィンドウで開く
            } else {
                openImageCatalogFile(path: parentPath, relativePath: relativePath.isEmpty ? nil : relativePath)
            }
        case .session(let sessionId):
            // セッションは複数ウィンドウを復元するのでShiftは無視
            if let session = sessionGroupManager.sessionGroups.first(where: { $0.id == sessionId }) {
                sessionGroupManager.updateLastAccessed(id: session.id)
                sessionManager.restoreSessionGroup(session)
            }
        }
        return .handled
    }

    private func handleMemoEdit(_ press: KeyPress) -> KeyPress.Result {
        // 初期画面でのみメモ編集
        guard !viewModel.hasOpenFile else { return .ignored }
        guard !isHistorySearchFocused else { return .ignored }  // 検索フィールド入力中は無視
        guard let selected = selectedHistoryItem else { return .ignored }

        switch selected {
        case .archive(let id, _):
            // 履歴エントリからidとmemoを取得（updateMemoはidで検索する）
            if let entry = historyManager.history.first(where: { $0.id == id }) {
                modalState.openMemoEditForHistory(fileKey: entry.id, memo: entry.memo)
            }
        case .standaloneImage(let id, _), .archiveContentImage(let id, _, _):
            // 画像カタログエントリからmemoを取得
            if let entry = imageCatalogManager.catalog.first(where: { $0.id == id }) {
                modalState.openMemoEditForCatalog(catalogId: id, memo: entry.memo)
            }
        case .session:
            // セッションにはメモ機能なし
            return .ignored
        }
        return .handled
    }

    private func handleSpace(_ press: KeyPress) -> KeyPress.Result {
        // ファイルを開いている時のみページ送り（検索フィールドへの入力を妨げない）
        guard viewModel.hasOpenFile else { return .ignored }
        if press.modifiers.contains(.shift) { viewModel.previousPage() }
        else { viewModel.nextPage() }
        return .handled
    }

    private func handleFKey(_ press: KeyPress) -> KeyPress.Result {
        // ⌘⌃F でフルスクリーン切り替え
        // 注: ⌘F（履歴トグル）はメニューショートカットで処理（TextFieldフォーカス中でも動作するため）
        if press.modifiers.contains(.command) && press.modifiers.contains(.control) {
            toggleFullScreen()
            return .handled
        }
        return .ignored
    }

    private func handleEscape() -> KeyPress.Result {
        // Escapeで履歴を閉じる（グローバル）
        if showHistory {
            showHistory = false
            selectedHistoryItem = nil
            isHistorySearchFocused = false
            isShowingSuggestions = false
            // メインビューにフォーカスを戻す
            isMainViewFocused = true
            return .handled
        }
        return .ignored
    }

    private func handleTab(_ press: KeyPress) -> KeyPress.Result {
        // 候補表示中はTextField側で処理（補完確定）
        if isShowingSuggestions { return .ignored }
        viewModel.skipForward(pages: appSettings.pageJumpCount)
        return .handled
    }

    private func handleImageInfo(_ press: KeyPress) -> KeyPress.Result {
        // ⌘I で画像情報表示
        if press.modifiers.contains(.command) && viewModel.hasOpenFile {
            modalState.toggleImageInfo()
            return .handled
        }
        return .ignored
    }

    private func handleOpenFile(_ press: KeyPress) -> KeyPress.Result {
        // ⌘O でファイルを開く
        if press.modifiers.contains(.command) {
            openFilePicker()
            return .handled
        }
        return .ignored
    }

    private func openFilePicker() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = [.zip, .cbz, .rar, .cbr, .sevenZip, .jpeg, .png, .gif, .webP, .folder]
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
        openFilesInCurrentWindow(urls: urls, animated: true)
    }

    /// 現在のウィンドウでファイルを開く（共通処理）
    /// 複数ファイルの場合、1つ目は現在のウィンドウで開き、2つ目以降は新規ウィンドウで開く
    private func openFilesInCurrentWindow(
        urls: [URL],
        relativePath: String? = nil,
        animated: Bool = false
    ) {
        guard !urls.isEmpty else { return }

        // 1つ目のファイルを現在のウィンドウで開く
        let firstURL = urls[0]
        if viewModel.hasOpenFile {
            viewModel.closeFile()
        }
        pendingRelativePath = relativePath
        if animated {
            withAnimation { pendingURLs = [firstURL] }
        } else {
            pendingURLs = [firstURL]
        }

        // 2つ目以降は新規ウィンドウで開く
        if urls.count > 1 {
            let remainingURLs = Array(urls.dropFirst())
            sessionManager.addFilesToOpen(urls: remainingURLs)
        }
    }

    private func openHistoryFile(path: String) {
        let url = URL(fileURLWithPath: path)
        openFilesInCurrentWindow(urls: [url])
    }

    private func openInNewWindow(path: String) {
        let url = URL(fileURLWithPath: path)
        // 新しいウィンドウでファイルを開く
        sessionManager.openInNewWindow(url: url)
    }

    /// 画像カタログからファイルを開く（書庫/フォルダ内の特定画像にジャンプ）
    private func openImageCatalogFile(path: String, relativePath: String?) {
        let url = URL(fileURLWithPath: path)
        openFilesInCurrentWindow(urls: [url], relativePath: relativePath)
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
                    // D&Dターゲットウィンドウを明示的にアクティブとして記録
                    // （NSApp.keyWindowがnilでもメニューが正しく機能するように）
                    if let windowNumber = self.myWindowNumber {
                        WindowCoordinator.shared.markAsActive(windowNumber: windowNumber)
                    }

                    // ウィンドウをキーウィンドウにする
                    if let windowNumber = self.myWindowNumber,
                       let window = NSApp.windows.first(where: { $0.windowNumber == windowNumber }) {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }

                    // D&D後にSwiftUIのフォーカスを設定（.onKeyPressが動作するために必要）
                    self.isMainViewFocused = true

                    DebugLogger.log("📬 D&D: \(urls.first?.lastPathComponent ?? "unknown") (window=\(self.myWindowNumber ?? -1))", level: .normal)
                    self.openFilesInCurrentWindow(urls: urls)
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
