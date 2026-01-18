import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let rar = UTType(filenameExtension: "rar")!
    static let cbr = UTType(filenameExtension: "cbr")!
    static let cbz = UTType(filenameExtension: "cbz")!
    static let sevenZip = UTType(filenameExtension: "7z")!
}

/// タブの種類
enum HistoryTab: String, CaseIterable {
    case archives
    case images
}

/// 初期画面で選択可能なアイテムの種類
enum SelectableHistoryItem: Equatable, Hashable {
    case archive(id: String, filePath: String)
    case standaloneImage(id: String, filePath: String)
    case archiveContentImage(id: String, parentPath: String, relativePath: String)
    case session(id: UUID)

    var id: String {
        switch self {
        case .archive(let id, _): return id
        case .standaloneImage(let id, _): return id
        case .archiveContentImage(let id, _, _): return id
        case .session(let id): return id.uuidString
        }
    }

    var sessionId: UUID? {
        if case .session(let id) = self { return id }
        return nil
    }
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

    // 画像情報モーダル表示用
    @State private var showImageInfo = false

    // 履歴フィルタ（ファイルを閉じても維持）
    @State private var historyFilterText: String = ""
    @State private var showHistoryFilter: Bool = false
    @State private var historySelectedTab: HistoryTab = .archives
    // スクロール位置復元用（最後に開いたエントリのID）
    @State private var lastOpenedArchiveId: String?
    @State private var lastOpenedImageId: String?
    // スクロールトリガー（初期画面に戻るたびにインクリメント）
    @State private var scrollTrigger: Int = 0

    // メモ編集用
    @State private var showMemoEdit = false
    @State private var editingMemoText = ""
    @State private var editingMemoFileKey: String?  // 履歴エントリ編集時に使用
    @State private var editingImageCatalogId: String?  // 画像カタログエントリ編集時に使用

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
                    editingMemoFileKey = fileKey
                    editingMemoText = currentMemo ?? ""
                    showMemoEdit = true
                },
                onEditImageMemo: { id, currentMemo in
                    editingImageCatalogId = id
                    editingMemoText = currentMemo ?? ""
                    showMemoEdit = true
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
                        editingMemoFileKey = fileKey
                        editingMemoText = currentMemo ?? ""
                        showMemoEdit = true
                    },
                    onEditImageMemo: { id, currentMemo in
                        editingImageCatalogId = id
                        editingMemoText = currentMemo ?? ""
                        showMemoEdit = true
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
            editingImageCatalogId = viewModel.getCurrentImageCatalogId()
            editingMemoText = viewModel.getCurrentImageMemo() ?? ""
            showMemoEdit = true
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
            editingMemoFileKey = viewModel.currentFileKey
            editingMemoText = viewModel.getCurrentMemo() ?? ""
            showMemoEdit = true
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
        .onKeyPress(keys: [.upArrow]) { handleUpArrow($0) }
        .onKeyPress(keys: [.downArrow]) { handleDownArrow($0) }
        .onKeyPress(keys: [.pageUp]) { handlePageUp($0) }
        .onKeyPress(keys: [.pageDown]) { handlePageDown($0) }
        .onKeyPress(characters: .init(charactersIn: "\r\n")) { handleReturn($0) }
        .onKeyPress(characters: CharacterSet(charactersIn: "mM")) { handleMemoEdit($0) }
        .onKeyPress(keys: [.space]) { press in
            // ファイルを開いている時のみページ送り（検索フィールドへの入力を妨げない）
            guard viewModel.hasOpenFile else { return .ignored }
            if press.modifiers.contains(.shift) { viewModel.previousPage() }
            else { viewModel.nextPage() }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { press in
            if press.modifiers.contains(.command) && press.modifiers.contains(.control) {
                toggleFullScreen()
                return .handled
            }
            // ⌘F で履歴表示トグル（表示時はフォーカスも設定）
            if press.modifiers.contains(.command) && !press.modifiers.contains(.control) {
                if showHistory {
                    // 表示中なら閉じる
                    showHistory = false
                    isHistorySearchFocused = false
                    isShowingSuggestions = false
                    // メインビューにフォーカスを戻す
                    isMainViewFocused = true
                } else {
                    // 非表示なら表示＋フォーカス
                    showHistory = true
                    isHistorySearchFocused = true
                    selectedHistoryItem = nil  // 選択解除（IME変換確定との干渉を防ぐ）
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            // Escapeで履歴を閉じる（グローバル）
            if showHistory {
                showHistory = false
                isHistorySearchFocused = false
                isShowingSuggestions = false
                // メインビューにフォーカスを戻す
                isMainViewFocused = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.home) { viewModel.goToFirstPage(); return .handled }
        .onKeyPress(.end) { viewModel.goToLastPage(); return .handled }
        .onKeyPress(keys: [.tab]) { _ in
            // 候補表示中はTextField側で処理（補完確定）
            if isShowingSuggestions { return .ignored }
            viewModel.skipForward(pages: appSettings.pageJumpCount)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "iI")) { press in
            // ⌘I で画像情報表示
            if press.modifiers.contains(.command) && viewModel.hasOpenFile {
                showImageInfo.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "oO")) { press in
            // ⌘O でファイルを開く
            if press.modifiers.contains(.command) {
                openFilePicker()
                return .handled
            }
            return .ignored
        }
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
                    editingImageCatalogId = nil
                }

            MemoEditPopover(
                memo: $editingMemoText,
                onSave: {
                    let newMemo = editingMemoText.isEmpty ? nil : editingMemoText
                    if let fileKey = editingMemoFileKey {
                        // 履歴エントリのメモを更新
                        historyManager.updateMemo(for: fileKey, memo: newMemo)
                    } else if let catalogId = editingImageCatalogId {
                        // 画像カタログエントリのメモを更新
                        imageCatalogManager.updateMemo(for: catalogId, memo: newMemo)
                    } else {
                        // 現在開いているファイルのメモを更新
                        viewModel.updateCurrentMemo(newMemo)
                    }
                    showMemoEdit = false
                    editingMemoFileKey = nil
                    editingImageCatalogId = nil
                },
                onCancel: {
                    showMemoEdit = false
                    editingMemoFileKey = nil
                    editingImageCatalogId = nil
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

        setupEventMonitor()
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

    private func setupEventMonitor() {
        // 既存のモニターがあれば削除（重複防止）
        if let existingMonitor = eventMonitor {
            NSEvent.removeMonitor(existingMonitor)
            eventMonitor = nil
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak viewModel] event in
            // 自分のウィンドウか確認
            let keyWindowNumber = NSApp.keyWindow?.windowNumber
            let isMyWindowActive = (self.myWindowNumber == keyWindowNumber)
            guard isMyWindowActive else {
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

        // ⌘ + スクロールホイールでズーム
        // 既存のモニターがあれば削除（重複防止）
        if let existingMonitor = scrollEventMonitor {
            NSEvent.removeMonitor(existingMonitor)
            scrollEventMonitor = nil
        }

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak viewModel] event in
            // ⌘キーが押されているか確認
            guard event.modifierFlags.contains(.command) else {
                return event
            }

            // 自分のウィンドウか確認
            let keyWindowNumber = NSApp.keyWindow?.windowNumber
            guard self.myWindowNumber == keyWindowNumber else {
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
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
            scrollEventMonitor = nil
        }

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
        // 初期画面でのみ履歴ナビゲーション
        guard !viewModel.hasOpenFile else { return .ignored }
        guard !isHistorySearchFocused else { return .ignored }  // 検索フィールドにフォーカス中は無視
        guard !isShowingSuggestions else { return .ignored }  // 候補表示中は無視（TextField側で処理）
        guard !visibleHistoryItems.isEmpty else { return .ignored }

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
        // 初期画面でのみ履歴ナビゲーション
        guard !viewModel.hasOpenFile else { return .ignored }
        guard !visibleHistoryItems.isEmpty else { return .ignored }

        // 候補表示中は無視（TextField側で処理）
        if isShowingSuggestions {
            return .ignored
        }

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
        // 初期画面でのみ履歴ナビゲーション
        guard !viewModel.hasOpenFile else { return .ignored }
        guard !isHistorySearchFocused else { return .ignored }
        guard !visibleHistoryItems.isEmpty else { return .ignored }

        if let current = selectedHistoryItem,
           let currentIndex = visibleHistoryItems.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, currentIndex - pageScrollCount)
            selectedHistoryItem = visibleHistoryItems[newIndex]
        } else {
            selectedHistoryItem = visibleHistoryItems.first
        }
        return .handled
    }

    private func handlePageDown(_ press: KeyPress) -> KeyPress.Result {
        // 初期画面でのみ履歴ナビゲーション
        guard !viewModel.hasOpenFile else { return .ignored }
        guard !isHistorySearchFocused else { return .ignored }
        guard !visibleHistoryItems.isEmpty else { return .ignored }

        if let current = selectedHistoryItem,
           let currentIndex = visibleHistoryItems.firstIndex(where: { $0.id == current.id }) {
            let newIndex = min(visibleHistoryItems.count - 1, currentIndex + pageScrollCount)
            selectedHistoryItem = visibleHistoryItems[newIndex]
        } else {
            selectedHistoryItem = visibleHistoryItems.first
        }
        return .handled
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
                editingMemoFileKey = entry.id
                editingMemoText = entry.memo ?? ""
                showMemoEdit = true
            }
        case .standaloneImage(let id, _), .archiveContentImage(let id, _, _):
            // 画像カタログエントリからmemoを取得
            if let entry = imageCatalogManager.catalog.first(where: { $0.id == id }) {
                editingImageCatalogId = id
                editingMemoText = entry.memo ?? ""
                showMemoEdit = true
            }
        case .session:
            // セッションにはメモ機能なし
            return .ignored
        }
        return .handled
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

    /// 画像カタログからファイルを開く（書庫/フォルダ内の特定画像にジャンプ）
    private func openImageCatalogFile(path: String, relativePath: String?) {
        let url = URL(fileURLWithPath: path)
        // 相対パスを保存しておく（ファイルが開かれた後にページジャンプに使う）
        pendingRelativePath = relativePath
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
                    // 既にファイルが開いている場合は一度閉じる
                    if viewModel.hasOpenFile {
                        viewModel.closeFile()
                    }
                    // pendingURLsを設定してonChangeをトリガーする（履歴からの読み込みと同じ経路）
                    pendingURLs = urls
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

/// 初期画面（ファイル未選択時）
struct InitialScreenView: View {
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(AppSettings.self) private var appSettings

    let errorMessage: String?
    @Binding var filterText: String
    @Binding var showFilterField: Bool
    @Binding var selectedTab: HistoryTab
    @Binding var lastOpenedArchiveId: String?
    @Binding var lastOpenedImageId: String?
    @Binding var showHistory: Bool  // セッション中の履歴表示状態
    let scrollTrigger: Int
    @Binding var selectedItem: SelectableHistoryItem?
    var isSearchFocused: FocusState<Bool>.Binding
    @Binding var isShowingSuggestions: Bool
    let onOpenFile: () -> Void
    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo) for archives
    let onEditImageMemo: (String, String?) -> Void  // (id, currentMemo) for image catalog
    let onOpenImageCatalogFile: (String, String?) -> Void  // (filePath, relativePath) for image catalog
    var onRestoreSession: ((SessionGroup) -> Void)? = nil
    var onVisibleItemsChange: (([SelectableHistoryItem]) -> Void)? = nil
    var onExitSearch: (() -> Void)? = nil

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
            HistoryListView(filterText: $filterText, showFilterField: $showFilterField, selectedTab: $selectedTab, lastOpenedArchiveId: $lastOpenedArchiveId, lastOpenedImageId: $lastOpenedImageId, showHistory: $showHistory, scrollTrigger: scrollTrigger, selectedItem: $selectedItem, isSearchFocused: isSearchFocused, isShowingSuggestions: $isShowingSuggestions, onOpenHistoryFile: onOpenHistoryFile, onOpenInNewWindow: onOpenInNewWindow, onEditMemo: onEditMemo, onEditImageMemo: onEditImageMemo, onOpenImageFile: onOpenImageCatalogFile, onRestoreSession: onRestoreSession, onVisibleItemsChange: onVisibleItemsChange, onExitSearch: onExitSearch)
        }
    }
}

/// 履歴リスト
struct HistoryListView: View {
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(ImageCatalogManager.self) private var imageCatalogManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(SessionGroupManager.self) private var sessionGroupManager
    @Binding var filterText: String
    @Binding var showFilterField: Bool
    @Binding var selectedTab: HistoryTab  // 後方互換性のため残す（将来削除予定）
    @Binding var lastOpenedArchiveId: String?
    @Binding var lastOpenedImageId: String?
    @Binding var showHistory: Bool  // セッション中の履歴表示状態
    let scrollTrigger: Int
    @Binding var selectedItem: SelectableHistoryItem?
    var isSearchFocused: FocusState<Bool>.Binding
    @Binding var isShowingSuggestions: Bool  // 親に候補表示状態を伝える
    @State private var dismissedError = false
    /// セクションの折りたたみ状態
    @State private var isArchivesSectionCollapsed = false
    @State private var isImagesSectionCollapsed = false
    @State private var isStandaloneSectionCollapsed = false
    @State private var isArchiveContentSectionCollapsed = false
    @State private var isSessionsSectionCollapsed = false
    /// 表示中の全アイテムリスト（キーボードナビゲーション用）
    @State private var visibleItems: [SelectableHistoryItem] = []

    /// 入力補完用（isShowingSuggestionsはisShowingSuggestionsバインディングを使用）
    @State private var selectedSuggestionIndex: Int = 0
    @State private var suggestions: [String] = []

    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo) for archives
    let onEditImageMemo: (String, String?) -> Void  // (id, currentMemo) for image catalog
    let onOpenImageFile: (String, String?) -> Void  // (filePath, relativePath) - 画像ファイルを開く
    var onRestoreSession: ((SessionGroup) -> Void)? = nil
    var onVisibleItemsChange: (([SelectableHistoryItem]) -> Void)? = nil
    var onExitSearch: (() -> Void)? = nil

    var body: some View {
        Group {
            // SwiftData初期化エラーの表示
            if let error = historyManager.initializationError, !dismissedError {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(L("history_database_error"))
                            .font(.headline)
                            .foregroundColor(.red)
                    }

                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)

                    Text(L("history_database_error_description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button(action: {
                            showResetDatabaseConfirmation()
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(L("history_database_reset"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button(action: {
                            dismissedError = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle")
                                Text(L("history_database_continue"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)

                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text(L("history_database_quit"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.top, 20)
            }

            // バージョントリガーを監視することで、配列更新時に再描画される
            // (history/catalogは@ObservationIgnoredなので直接監視されない)
            let _ = historyManager.historyVersion
            let _ = imageCatalogManager.catalogVersion
            // scrollTrigger監視：フォーカス時にそのウィンドウだけ再描画するため
            let _ = scrollTrigger

            let recentHistory = historyManager.getRecentHistory(limit: appSettings.maxHistoryCount)
            let imageCatalog = imageCatalogManager.catalog
            let sessionGroups = sessionGroupManager.sessionGroups

            // 検索クエリをパース（デフォルトタイプはAppSettingsから取得）
            let parsedQuery = HistorySearchParser.parse(filterText, defaultType: appSettings.defaultHistorySearchType)
            // 統合検索を実行
            let searchResult = UnifiedSearchFilter.search(
                query: parsedQuery,
                archives: recentHistory,
                images: imageCatalog,
                sessions: sessionGroups
            )

            // 履歴表示が有効で、書庫または画像またはセッションがある場合
            if showHistory && (!recentHistory.isEmpty || !imageCatalog.isEmpty || !sessionGroups.isEmpty) {
                VStack(alignment: .leading, spacing: 8) {
                    // 検索フィールド（常に表示、⌘+Fでフォーカス）
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            // インライン補完付きテキストフィールド
                            ZStack(alignment: .leading) {
                                // インライン補完テキスト（グレー表示）
                                if let completion = getInlineCompletion(for: filterText), isSearchFocused.wrappedValue {
                                    HStack(spacing: 0) {
                                        Text(filterText)
                                            .foregroundColor(.clear)
                                        Text(completion)
                                            .foregroundColor(.gray.opacity(0.6))
                                    }
                                }
                                TextField(
                                    L("unified_search_placeholder"),
                                    text: $filterText
                                )
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .focused(isSearchFocused)
                                .onExitCommand {
                                    isShowingSuggestions = false
                                    isSearchFocused.wrappedValue = false
                                    onExitSearch?()
                                }
                                .onChange(of: filterText) { _, newValue in
                                    // 候補を更新
                                    suggestions = computeSuggestions(from: searchResult, query: newValue)
                                    isShowingSuggestions = !suggestions.isEmpty && isSearchFocused.wrappedValue
                                    selectedSuggestionIndex = 0
                                }
                                .onKeyPress(.tab) {
                                    // Tabで補完を適用
                                    if isShowingSuggestions && !suggestions.isEmpty {
                                        applySuggestion(suggestions[selectedSuggestionIndex])
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.upArrow) {
                                    // 候補リスト内で上に移動
                                    if isShowingSuggestions && !suggestions.isEmpty {
                                        selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.downArrow) {
                                    // 候補リスト内で下に移動
                                    if isShowingSuggestions && !suggestions.isEmpty {
                                        if selectedSuggestionIndex < suggestions.count - 1 {
                                            selectedSuggestionIndex += 1
                                        }
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.escape) {
                                    // Escapeで候補リストを閉じる → 履歴を閉じる
                                    if isShowingSuggestions {
                                        isShowingSuggestions = false
                                        return .handled
                                    }
                                    // 候補がない場合は履歴を閉じる
                                    showHistory = false
                                    isSearchFocused.wrappedValue = false
                                    return .handled
                                }
                            }
                            // 検索種別インジケーター
                            if !filterText.isEmpty && parsedQuery.targetType != .all {
                                Text(searchTargetLabel(parsedQuery.targetType))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.3))
                                    .cornerRadius(4)
                                    .foregroundColor(.white)
                            }
                            // クリアボタン
                            if !filterText.isEmpty {
                                Button(action: {
                                    filterText = ""
                                    isShowingSuggestions = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                            }
                            // フィルタードロップダウンメニュー
                            Menu {
                                Button(action: { insertSearchFilter("type:archive ") }) {
                                    Label(L("search_type_archive"), systemImage: "archivebox")
                                }
                                Button(action: { insertSearchFilter("type:image ") }) {
                                    Label(L("search_type_image"), systemImage: "photo.stack")
                                }
                                Button(action: { insertSearchFilter("type:session ") }) {
                                    Label(L("search_type_session"), systemImage: "square.stack.3d.up")
                                }
                                Divider()
                                Button(action: { insertSearchFilter("type:standalone ") }) {
                                    Label(L("search_type_standalone"), systemImage: "photo")
                                }
                                Button(action: { insertSearchFilter("type:content ") }) {
                                    Label(L("search_type_content"), systemImage: "photo.on.rectangle")
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundColor(.gray)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)

                        // ドロップダウン候補リスト
                        if isShowingSuggestions && !suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                    HStack {
                                        Text(suggestion)
                                            .foregroundColor(.white)
                                        Spacer()
                                        if index == selectedSuggestionIndex {
                                            Text("Tab")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(3)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(index == selectedSuggestionIndex ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .onTapGesture {
                                        applySuggestion(suggestion)
                                    }
                                }
                            }
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(6)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.top, 20)

                    // 検索結果のセクション表示
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                // 書庫セクション
                                if parsedQuery.includesArchives && !searchResult.archives.isEmpty {
                                    archivesSectionView(
                                        archives: searchResult.archives,
                                        totalCount: recentHistory.count,
                                        isFiltering: parsedQuery.hasKeyword
                                    )
                                }

                                // 画像セクション
                                if parsedQuery.includesImages && !searchResult.images.isEmpty {
                                    imagesSectionView(
                                        images: searchResult.images,
                                        totalCount: imageCatalog.count,
                                        isFiltering: parsedQuery.hasKeyword
                                    )
                                }

                            // セッションセクション
                            if parsedQuery.includesSessions && !searchResult.sessions.isEmpty {
                                sessionsSectionView(
                                    sessions: searchResult.sessions,
                                    totalCount: sessionGroups.count,
                                    isFiltering: parsedQuery.hasKeyword
                                )
                            }

                            // 検索結果が空の場合
                            if parsedQuery.hasKeyword && searchResult.isEmpty {
                                Text(L("search_no_results"))
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.visible)
                    .preferredColorScheme(.dark)
                    .frame(maxHeight: 400)
                    .onChange(of: selectedItem?.id) { _, newId in
                        if let id = newId {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 20)
                .onChange(of: searchResult.archives.count) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: searchResult.images.count) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: searchResult.sessions.map { $0.id }) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isArchivesSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isImagesSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isStandaloneSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isArchiveContentSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isSessionsSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onAppear {
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
            }
        }
    }

    /// 表示中のアイテムリストを更新
    private func updateVisibleItems(archives: [FileHistoryEntry], images: [ImageCatalogEntry], sessions: [SessionGroup], parsedQuery: ParsedSearchQuery) {
        var items: [SelectableHistoryItem] = []

        // 書庫セクション
        if parsedQuery.includesArchives && !archives.isEmpty && !isArchivesSectionCollapsed {
            for entry in archives {
                items.append(.archive(id: entry.id, filePath: entry.filePath))
            }
        }

        // 画像セクション
        if parsedQuery.includesImages && !images.isEmpty && !isImagesSectionCollapsed {
            let standaloneImages = images.filter { $0.catalogType == .standalone }
            let archiveContentImages = images.filter { $0.catalogType == .archiveContent }

            // 個別画像
            if !standaloneImages.isEmpty && !isStandaloneSectionCollapsed {
                for entry in standaloneImages {
                    items.append(.standaloneImage(id: entry.id, filePath: entry.filePath))
                }
            }

            // 書庫内画像
            if !archiveContentImages.isEmpty && !isArchiveContentSectionCollapsed {
                for entry in archiveContentImages {
                    items.append(.archiveContentImage(id: entry.id, parentPath: entry.filePath, relativePath: entry.relativePath ?? ""))
                }
            }
        }

        // セッションセクション
        if parsedQuery.includesSessions && !sessions.isEmpty && !isSessionsSectionCollapsed {
            for session in sessions {
                items.append(.session(id: session.id))
            }
        }

        visibleItems = items
        onVisibleItemsChange?(items)
    }

    /// 検索対象種別のラベル
    private func searchTargetLabel(_ type: SearchTargetType) -> String {
        switch type {
        case .all:
            return ""
        case .archive:
            return L("search_type_archive")
        case .image:
            return L("search_type_image")
        case .standalone:
            return L("search_type_standalone")
        case .content:
            return L("search_type_content")
        case .session:
            return L("search_type_session")
        }
    }

    /// 検索フィルターを挿入/置換する
    private func insertSearchFilter(_ filter: String) {
        // 既存のtype:プレフィックスを削除
        let typePattern = /^type:\w+\s*/
        let cleanedText = filterText.replacing(typePattern, with: "")

        if filter.isEmpty {
            // 「すべて」が選択された場合はtype:を削除するだけ
            filterText = cleanedText
        } else {
            // 新しいフィルターを先頭に追加
            filterText = filter + cleanedText
        }
    }

    /// type:プレフィックスの候補リスト
    private let typeFilterSuggestions = [
        "type:archive ",
        "type:image ",
        "type:session ",
        "type:standalone ",
        "type:content "
    ]

    /// 入力補完候補を計算する（type:プレフィックス用）
    private func computeSuggestions(
        from searchResult: UnifiedSearchResult,
        query: String
    ) -> [String] {
        guard !query.isEmpty else { return [] }

        let lowercaseQuery = query.lowercased()

        // 既にtype:プレフィックスが完成している場合は候補なし
        if lowercaseQuery.hasPrefix("type:") && lowercaseQuery.contains(" ") {
            return []
        }

        // "t", "ty", "typ", "type", "type:" などで始まる場合にtype:候補を表示
        let typePrefix = "type:"
        if typePrefix.hasPrefix(lowercaseQuery) || lowercaseQuery.hasPrefix("type:") {
            // type:の後の部分でフィルタリング
            if lowercaseQuery.hasPrefix("type:") {
                let afterType = String(lowercaseQuery.dropFirst(5))  // "type:" の後
                return typeFilterSuggestions.filter {
                    let suggestionAfterType = String($0.dropFirst(5).dropLast())  // "type:" と末尾スペースを除去
                    return suggestionAfterType.hasPrefix(afterType)
                }
            } else {
                // "t", "ty", "typ", "type" の場合は全候補
                return typeFilterSuggestions
            }
        }

        return []
    }

    /// インライン補完テキストを取得（最初の候補の残り部分）
    private func getInlineCompletion(for query: String) -> String? {
        guard !query.isEmpty, !suggestions.isEmpty else { return nil }

        let firstSuggestion = suggestions[selectedSuggestionIndex]
        let lowercaseQuery = query.lowercased()

        // 大文字小文字を無視して先頭一致を確認
        if firstSuggestion.lowercased().hasPrefix(lowercaseQuery) {
            // 元の候補から残りの部分を返す
            return String(firstSuggestion.dropFirst(query.count))
        }

        return nil
    }

    /// 補完を適用する
    private func applySuggestion(_ suggestion: String) {
        filterText = suggestion
        isShowingSuggestions = false
    }

    /// 書庫セクションビュー
    @ViewBuilder
    private func archivesSectionView(archives: [FileHistoryEntry], totalCount: Int, isFiltering: Bool) -> some View {
        // セクションヘッダー
        HStack {
            Button(action: { isArchivesSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isArchivesSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                    Image(systemName: "archivebox")
                    Text(L("tab_archives"))
                        .font(.subheadline.bold())
                    Text("(\(archives.count))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Spacer()

            if isFiltering {
                Text(L("history_filter_result_format", archives.count, totalCount))
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("[\(archives.count)/\(appSettings.maxHistoryCount)]")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 4)

        if !isArchivesSectionCollapsed {
            ForEach(Array(archives.enumerated()), id: \.element.id) { index, entry in
                HistoryEntryRow(
                    entry: entry,
                    onOpenHistoryFile: { filePath in
                        if index > 0 {
                            lastOpenedArchiveId = archives[index - 1].id
                        } else if index + 1 < archives.count {
                            lastOpenedArchiveId = archives[index + 1].id
                        } else {
                            lastOpenedArchiveId = nil
                        }
                        onOpenHistoryFile(filePath)
                    },
                    onOpenInNewWindow: onOpenInNewWindow,
                    onEditMemo: onEditMemo
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(selectedItem?.id == entry.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(entry.id)
            }
        }
    }

    /// 画像セクションビュー
    @ViewBuilder
    private func imagesSectionView(images: [ImageCatalogEntry], totalCount: Int, isFiltering: Bool) -> some View {
        let standaloneImages = images.filter { $0.catalogType == .standalone }
        let archiveContentImages = images.filter { $0.catalogType == .archiveContent }

        // セクションヘッダー
        HStack {
            Button(action: { isImagesSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isImagesSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                    Image(systemName: "photo")
                    Text(L("tab_images"))
                        .font(.subheadline.bold())
                    Text("(\(images.count))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Spacer()

            if isFiltering {
                Text(L("history_filter_result_format", images.count, totalCount))
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("[\(standaloneImages.count)/\(appSettings.maxStandaloneImageCount) + \(archiveContentImages.count)/\(appSettings.maxArchiveContentImageCount)]")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 4)

        if !isImagesSectionCollapsed {
            // 個別画像サブセクション
            if !standaloneImages.isEmpty {
                standaloneSubsectionView(
                    images: standaloneImages,
                    isFiltering: isFiltering
                )
            }

            // 書庫/フォルダ内画像サブセクション
            if !archiveContentImages.isEmpty {
                archiveContentSubsectionView(
                    images: archiveContentImages,
                    isFiltering: isFiltering
                )
            }
        }
    }

    /// 個別画像サブセクションビュー
    @ViewBuilder
    private func standaloneSubsectionView(images: [ImageCatalogEntry], isFiltering: Bool) -> some View {
        HStack {
            Button(action: { isStandaloneSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isStandaloneSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                    Image(systemName: "doc.richtext")
                        .font(.caption)
                    Text(L("search_type_standalone"))
                        .font(.caption.bold())
                    Text("(\(images.count))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))

            Spacer()

            if !isFiltering {
                Text("[\(images.count)/\(appSettings.maxStandaloneImageCount)]")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.leading, 16)
        .padding(.horizontal, 4)
        .padding(.top, 4)

        if !isStandaloneSectionCollapsed {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, entry in
                ImageCatalogEntryRow(
                    entry: entry,
                    onOpenImageFile: { filePath, relativePath in
                        if index > 0 {
                            lastOpenedImageId = images[index - 1].id
                        } else if index + 1 < images.count {
                            lastOpenedImageId = images[index + 1].id
                        } else {
                            lastOpenedImageId = nil
                        }
                        onOpenImageFile(filePath, relativePath)
                    },
                    onEditMemo: onEditImageMemo
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(selectedItem?.id == entry.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(entry.id)
            }
        }
    }

    /// 書庫/フォルダ内画像サブセクションビュー
    @ViewBuilder
    private func archiveContentSubsectionView(images: [ImageCatalogEntry], isFiltering: Bool) -> some View {
        HStack {
            Button(action: { isArchiveContentSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isArchiveContentSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                    Image(systemName: "doc.zipper")
                        .font(.caption)
                    Text(L("search_type_content"))
                        .font(.caption.bold())
                    Text("(\(images.count))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))

            Spacer()

            if !isFiltering {
                Text("[\(images.count)/\(appSettings.maxArchiveContentImageCount)]")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.leading, 16)
        .padding(.horizontal, 4)
        .padding(.top, 4)

        if !isArchiveContentSectionCollapsed {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, entry in
                ImageCatalogEntryRow(
                    entry: entry,
                    onOpenImageFile: { filePath, relativePath in
                        if index > 0 {
                            lastOpenedImageId = images[index - 1].id
                        } else if index + 1 < images.count {
                            lastOpenedImageId = images[index + 1].id
                        } else {
                            lastOpenedImageId = nil
                        }
                        onOpenImageFile(filePath, relativePath)
                    },
                    onEditMemo: onEditImageMemo
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(selectedItem?.id == entry.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(entry.id)
            }
        }
    }

    /// セッションセクションビュー
    @ViewBuilder
    private func sessionsSectionView(sessions: [SessionGroup], totalCount: Int, isFiltering: Bool) -> some View {
        // セクションヘッダー
        HStack {
            Button(action: { isSessionsSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isSessionsSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                    Image(systemName: "square.stack.3d.up")
                    Text(L("tab_sessions"))
                        .font(.subheadline.bold())
                    Text("(\(sessions.count))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Spacer()

            if isFiltering {
                Text(L("history_filter_result_format", sessions.count, totalCount))
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("[\(sessions.count)/\(sessionGroupManager.maxSessionGroupCount)]")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 4)

        if !isSessionsSectionCollapsed {
            ForEach(sessions) { session in
                SessionGroupRow(
                    session: session,
                    onRestore: {
                        onRestoreSession?(session)
                    },
                    onRename: { newName in
                        sessionGroupManager.renameSessionGroup(id: session.id, newName: newName)
                    },
                    onDelete: {
                        sessionGroupManager.deleteSessionGroup(id: session.id)
                    }
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(selectedItem?.sessionId == session.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(session.id.uuidString)
            }
        }
    }

    /// データベースリセットの確認ダイアログを表示
    private func showResetDatabaseConfirmation() {
        let alert = NSAlert()
        alert.messageText = L("history_database_reset_confirm_title")
        alert.informativeText = L("history_database_reset_confirm_message")
        alert.alertStyle = .critical
        alert.addButton(withTitle: L("history_database_reset"))
        alert.addButton(withTitle: L("cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            historyManager.resetDatabase()
        }
    }
}

/// セッショングループの行
struct SessionGroupRow: View {
    let session: SessionGroup
    let onRestore: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onRestore) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        Text(String(format: L("session_group_files_format"), session.fileCount))
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(formatDate(session.lastAccessedAt))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                // アクセス可能なファイル数
                if session.accessibleFileCount < session.fileCount {
                    Text("\(session.accessibleFileCount)/\(session.fileCount)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(action: onRestore) {
                Label(L("session_group_restore"), systemImage: "arrow.uturn.backward")
            }
            Divider()
            Button(action: {
                showRenameDialog()
            }) {
                Label(L("session_group_rename"), systemImage: "pencil")
            }
            Button(role: .destructive, action: {
                showDeleteConfirmation()
            }) {
                Label(L("session_group_delete"), systemImage: "trash")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func showRenameDialog() {
        let alert = NSAlert()
        alert.messageText = L("session_rename_title")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("save"))
        alert.addButton(withTitle: L("cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = session.name
        textField.placeholderString = L("session_rename_placeholder")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue
            if !newName.isEmpty {
                onRename(newName)
            }
        }
    }

    private func showDeleteConfirmation() {
        let alert = NSAlert()
        alert.messageText = L("session_delete_confirm_title")
        alert.informativeText = String(format: L("session_delete_confirm_message"), session.name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("session_group_delete"))
        alert.addButton(withTitle: L("cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            onDelete()
        }
    }
}

/// 画像カタログエントリの行
struct ImageCatalogEntryRow: View {
    @Environment(ImageCatalogManager.self) private var catalogManager

    let entry: ImageCatalogEntry
    let onOpenImageFile: (String, String?) -> Void  // (filePath, relativePath)
    let onEditMemo: (String, String?) -> Void  // (id, currentMemo)

    // ツールチップ用（一度だけ生成してキャッシュ）
    @State private var cachedTooltip: String?

    var body: some View {
        let isAccessible = catalogManager.isAccessible(for: entry)

        HStack(spacing: 0) {
            Button(action: {
                if isAccessible {
                    onOpenImageFile(entry.filePath, entry.relativePath)
                }
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.fileName)
                            .foregroundColor(isAccessible ? .white : .gray)
                        Spacer()
                        // 解像度があれば表示
                        if let resolution = entry.resolutionString {
                            Text(resolution)
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    // 親（書庫/フォルダ）名を表示
                    if let parentName = entry.parentName {
                        Text(parentName)
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.8))
                            .lineLimit(1)
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

            // 削除ボタン
            Button(action: {
                catalogManager.removeEntry(withId: entry.id)
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
                onOpenImageFile(entry.filePath, entry.relativePath)
            }) {
                Label(L("menu_open_in_new_window"), systemImage: "rectangle.badge.plus")
            }
            .disabled(!isAccessible)

            Divider()

            Button(action: {
                onEditMemo(entry.id, entry.memo)
            }) {
                Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
            }

            Divider()

            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.filePath)])
            }) {
                Label(L("menu_reveal_in_finder"), systemImage: "folder")
            }
            .disabled(!isAccessible)
        }
    }

    /// ツールチップ用のテキストを生成
    private func generateTooltip() -> String {
        var lines: [String] = []

        // ファイルパス（書庫/フォルダ内の場合は親パス + 相対パス）
        if entry.catalogType == .archiveContent, let relativePath = entry.relativePath {
            lines.append(entry.filePath)
            lines.append("  → " + relativePath)
        } else {
            lines.append(entry.filePath)
        }

        // 画像フォーマット
        if let format = entry.imageFormat {
            lines.append(L("tooltip_archive_type") + ": " + format)
        }

        // 解像度
        if let resolution = entry.resolutionString {
            lines.append(L("tooltip_resolution") + ": " + resolution)
        }

        // ファイルサイズ
        if let sizeStr = entry.fileSizeString {
            lines.append(L("tooltip_file_size") + ": " + sizeStr)
        }

        // 最終アクセス日時
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append(L("tooltip_last_access") + ": " + formatter.string(from: entry.lastAccessDate))

        return lines.joined(separator: "\n")
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
                onEditMemo(entry.id, entry.memo)
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

        // ファイルサイズ（fileKeyから取得、ファイルアクセス不要）
        if let sizeStr = entry.fileSizeString {
            lines.append(L("tooltip_file_size") + ": " + sizeStr)
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
    let fittingMode: FittingMode
    let zoomLevel: CGFloat
    let interpolation: InterpolationMode
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String
    let contextMenuBuilder: (Int) -> ContextMenu

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                // ズームが適用されている場合、または等倍表示の場合はスクロール可能にする
                if zoomLevel != 1.0 || fittingMode == .originalSize {
                    ZoomableScrollView(viewportSize: geometry.size) {
                        ImageDisplayView(
                            image: image,
                            rotation: rotation,
                            flip: flip,
                            fittingMode: fittingMode,
                            viewportSize: geometry.size,
                            zoomLevel: zoomLevel,
                            interpolation: interpolation
                        )
                        .contextMenu { contextMenuBuilder(pageIndex) }
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height,
                            alignment: .center
                        )
                    }
                } else {
                    switch fittingMode {
                    case .window:
                        ImageDisplayView(image: image, rotation: rotation, flip: flip, fittingMode: fittingMode, interpolation: interpolation)
                            .contextMenu { contextMenuBuilder(pageIndex) }
                    case .height:
                        // 縦フィット: 横スクロール可能、横センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
                            ImageDisplayView(
                                image: image,
                                rotation: rotation,
                                flip: flip,
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation
                            )
                            .contextMenu { contextMenuBuilder(pageIndex) }
                            .frame(minWidth: geometry.size.width, alignment: .center)
                        }
                    case .width:
                        // 横フィット: 縦スクロール可能、縦センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
                            ImageDisplayView(
                                image: image,
                                rotation: rotation,
                                flip: flip,
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation
                            )
                            .contextMenu { contextMenuBuilder(pageIndex) }
                            .frame(minHeight: geometry.size.height, alignment: .center)
                        }
                    case .originalSize:
                        // このケースはzoomLevel != 1.0 || fittingMode == .originalSizeで処理される
                        EmptyView()
                    }
                }
            }

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
    let fittingMode: FittingMode
    let zoomLevel: CGFloat
    let interpolation: InterpolationMode
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String
    var copiedPageIndex: Int? = nil
    let contextMenuBuilder: (Int) -> ContextMenu

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                // ズームが適用されている場合は常にスクロール可能にする
                if zoomLevel != 1.0 {
                    ZoomableScrollView(viewportSize: geometry.size) {
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
                            fittingMode: fittingMode,
                            viewportSize: geometry.size,
                            zoomLevel: zoomLevel,
                            interpolation: interpolation,
                            copiedPageIndex: copiedPageIndex,
                            contextMenuBuilder: contextMenuBuilder
                        )
                        .equatable()
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height,
                            alignment: .center
                        )
                    }
                } else {
                    switch fittingMode {
                    case .window:
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
                            fittingMode: fittingMode,
                            interpolation: interpolation,
                            copiedPageIndex: copiedPageIndex,
                            contextMenuBuilder: contextMenuBuilder
                        )
                        .equatable()
                    case .height:
                        // 縦フィット: 横スクロール可能、横センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
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
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation,
                                copiedPageIndex: copiedPageIndex,
                                contextMenuBuilder: contextMenuBuilder
                            )
                            .equatable()
                            .frame(minWidth: geometry.size.width, alignment: .center)
                        }
                    case .width:
                        // 横フィット: 縦スクロール可能、縦センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
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
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation,
                                copiedPageIndex: copiedPageIndex,
                                contextMenuBuilder: contextMenuBuilder
                            )
                            .equatable()
                            .frame(minHeight: geometry.size.height, alignment: .center)
                        }
                    case .originalSize:
                        // 等倍表示は見開きでは未対応、ウィンドウフィットにフォールバック
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
                            fittingMode: .window,
                            interpolation: interpolation,
                            copiedPageIndex: copiedPageIndex,
                            contextMenuBuilder: contextMenuBuilder
                        )
                        .equatable()
                    }
                }
            }

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
