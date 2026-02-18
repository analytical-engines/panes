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

    // 履歴・検索UI状態
    @State private var historyState = HistoryUIState()

    // 画像カタログからのファイルオープン時に使用する相対パス
    @State private var pendingRelativePath: String?

    // 表示順序変更用（コピー/ペースト方式）
    @State private var copiedPageIndex: Int?

    // ピンチジェスチャー用のベースライン（ジェスチャー開始時のズームレベル）
    @State private var magnificationGestureBaseline: CGFloat = 1.0

    // ピンチジェスチャー中のビジュアルスケール（GPUトランスフォーム用）
    // ジェスチャー中はsetZoom()を呼ばず、scaleEffectのみで表示し、終了時に確定する
    @State private var pinchGestureScale: CGFloat = 1.0

    /// ページ遷移オーバーレイのスライド方向（-1=左, +1=右）
    /// スワイプ方向と一致させる: RTLでは次=右スワイプ→右退場、LTRでは次=左スワイプ→左退場
    private var transitionSlideDirection: CGFloat {
        let isForward = viewModel.lastNavigationDirection == .forward
        if viewModel.readingDirection == .rightToLeft {
            // RTL: 次ページ(右スワイプ)→右へ退場、前ページ(左スワイプ)→左へ退場
            return isForward ? 1 : -1
        } else {
            // LTR: 次ページ(左スワイプ)→左へ退場、前ページ(右スワイプ)→右へ退場
            return isForward ? -1 : 1
        }
    }

    // ページ遷移スナップショットオーバーレイのオフセット
    @State private var transitionOverlayOffset: CGFloat = 0

    // マウスドラッグスワイプ: 発火済みフラグ（ドラッグ中に1回だけ発火）
    @State private var dragSwipeTriggered: Bool = false

    // メインビューのフォーカス管理
    @FocusState private var isMainViewFocused: Bool

    // 履歴検索フィールドのフォーカス（@FocusStateはビューに紐づくためここに残す）
    @FocusState private var isHistorySearchFocused: Bool

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.appMode {
        case .initial:
            // 初期画面（ファイル未選択）
            InitialScreenView(
                errorMessage: viewModel.errorMessage,
                historyState: historyState,
                isSearchFocused: $isHistorySearchFocused,
                onOpenFile: openFilePicker,
                onOpenHistoryFile: openHistoryFile,
                onOpenInNewWindow: openSelectedInNewWindow,
                onEditMemo: { fileKey, currentMemo in
                    if historyState.selectedItems.count > 1 {
                        openStructuredBatchMetadataEdit()
                    } else {
                        modalState.openStructuredEditForSingle(fileKey: fileKey, catalogId: nil, memo: currentMemo)
                    }
                },
                onEditImageMemo: { id, currentMemo in
                    if historyState.selectedItems.count > 1 {
                        openStructuredBatchMetadataEdit()
                    } else {
                        modalState.openStructuredEditForSingle(fileKey: nil, catalogId: id, memo: currentMemo)
                    }
                },
                onOpenImageCatalogFile: openImageCatalogFile,
                onRestoreSession: { session in
                    sessionGroupManager.updateLastAccessed(id: session.id)
                    sessionManager.restoreSessionGroup(session)
                }
            )
            .contextMenu { initialScreenContextMenu }

        case .loading:
            // ファイル読み込み中
            LoadingView(phase: viewModel.loadingPhase)

        case .viewing:
            // 画像閲覧中
            viewingContent
                .overlay {
                    // ページ遷移スナップショットオーバーレイ（旧画面がスライドアウト）
                    if let snapshot = viewModel.transitionSnapshot {
                        GeometryReader { geo in
                            ZStack {
                                // 背景色で隙間を埋める（画像サイズ不一致対策）
                                Color.black
                                Image(nsImage: snapshot)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .offset(x: transitionOverlayOffset)
                        }
                    }
                }
                .onChange(of: viewModel.transitionSnapshot) { _, newValue in
                    if newValue != nil {
                        // スナップショットが設定された → スライドアウトアニメーション開始
                        // カスタムカーブ: 最初は小さく加速→後半は等速でスライド
                        withAnimation(.timingCurve(0.4, 0.0, 0.7, 1.0, duration: 0.2)) {
                            transitionOverlayOffset = transitionSlideDirection * 1200
                        } completion: {
                            viewModel.transitionSnapshot = nil
                            transitionOverlayOffset = 0
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            guard !dragSwipeTriggered else { return }
                            let horizontalDrag = value.translation.width
                            // 水平方向が十分で、かつ縦より水平が優勢な場合のみ
                            if abs(horizontalDrag) > 50 && abs(horizontalDrag) > abs(value.translation.height) {
                                dragSwipeTriggered = true
                                viewModel.nextNavigationIsSwipe = true
                                if horizontalDrag > 0 {
                                    // 右にドラッグ → RTL:次ページ, LTR:前ページ
                                    if viewModel.readingDirection == .rightToLeft {
                                        viewModel.nextPage()
                                    } else {
                                        viewModel.previousPage()
                                    }
                                } else {
                                    // 左にドラッグ → RTL:前ページ, LTR:次ページ
                                    if viewModel.readingDirection == .rightToLeft {
                                        viewModel.previousPage()
                                    } else {
                                        viewModel.nextPage()
                                    }
                                }
                            }
                        }
                        .onEnded { _ in
                            dragSwipeTriggered = false
                        }
                )
        }
    }

    /// 画像閲覧中のコンテンツ（viewing状態用）
    @ViewBuilder
    private var viewingContent: some View {
        if viewModel.viewMode == .single, let image = viewModel.currentImage {
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
                contextMenuBuilder: { pageIndex in imageContextMenu(for: pageIndex) },
                onTapLeft: {
                    // RTL: 左→次ページ, LTR: 左→前ページ
                    if viewModel.readingDirection == .rightToLeft {
                        viewModel.nextPage()
                    } else {
                        viewModel.previousPage()
                    }
                },
                onTapRight: {
                    // RTL: 右→前ページ, LTR: 右→次ページ
                    if viewModel.readingDirection == .rightToLeft {
                        viewModel.previousPage()
                    } else {
                        viewModel.nextPage()
                    }
                }
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
                contextMenuBuilder: { pageIndex in imageContextMenu(for: pageIndex) },
                onTapLeft: {
                    // RTL: 左→次ページ, LTR: 左→前ページ
                    if viewModel.readingDirection == .rightToLeft {
                        viewModel.nextPage()
                    } else {
                        viewModel.previousPage()
                    }
                },
                onTapRight: {
                    // RTL: 右→前ページ, LTR: 右→次ページ
                    if viewModel.readingDirection == .rightToLeft {
                        viewModel.previousPage()
                    } else {
                        viewModel.nextPage()
                    }
                }
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
            // viewing状態だが画像がまだ読み込まれていない場合のフォールバック
            LoadingView(phase: viewModel.loadingPhase)
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
                    historyState: historyState,
                    isSearchFocused: $isHistorySearchFocused,
                    onOpenHistoryFile: openHistoryFile,
                    onOpenInNewWindow: openSelectedInNewWindow,
                    onEditMemo: { fileKey, currentMemo in
                        if historyState.selectedItems.count > 1 {
                            openStructuredBatchMetadataEdit()
                        } else {
                            modalState.openStructuredEditForSingle(fileKey: fileKey, catalogId: nil, memo: currentMemo)
                        }
                    },
                    onEditImageMemo: { id, currentMemo in
                        if historyState.selectedItems.count > 1 {
                            openStructuredBatchMetadataEdit()
                        } else {
                            modalState.openStructuredEditForSingle(fileKey: nil, catalogId: id, memo: currentMemo)
                        }
                    },
                    onOpenImageFile: openImageCatalogFile,
                    onRestoreSession: { session in
                        sessionGroupManager.updateLastAccessed(id: session.id)
                        sessionManager.restoreSessionGroup(session)
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

        // 画像メモを編集（構造化UI）
        Button(action: {
            if let catalogId = viewModel.getCurrentImageCatalogId(at: pageIndex) {
                modalState.openStructuredEditForSingle(fileKey: nil, catalogId: catalogId, memo: viewModel.getCurrentImageMemo(at: pageIndex))
            }
        }) {
            Label(L("menu_edit_image_memo"), systemImage: "photo")
        }
        .disabled(!viewModel.hasCurrentImageInCatalog(at: pageIndex))

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
            historyState.showHistory.toggle()
            // 「終了時の状態を復元」モードの場合は現在の状態を保存
            if appSettings.historyDisplayMode == .restoreLast {
                appSettings.lastHistoryVisible = historyState.showHistory
            }
        }) {
            Label(
                historyState.showHistory
                    ? L("menu_hide_history")
                    : L("menu_show_history_toggle"),
                systemImage: historyState.showHistory
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

        // 書庫のメモ編集（構造化UI）
        Button(action: {
            modalState.openStructuredEditForSingle(fileKey: viewModel.currentFileKey, catalogId: nil, memo: viewModel.getCurrentMemo())
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
                .scaleEffect(pinchGestureScale)

            // 画像表示中の履歴オーバーレイ
            if viewModel.hasOpenFile && historyState.showHistory {
                historyOverlay
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    // ピンチジェスチャー中：GPUスケールのみ適用（再レンダリングなし）
                    guard viewModel.hasOpenFile else { return }

                    // 感度を下げるためダンピングを適用（0.5 = 半分の感度）
                    let dampening: CGFloat = 0.5
                    pinchGestureScale = 1.0 + (value - 1.0) * dampening
                }
                .onEnded { value in
                    // ジェスチャー終了時：実際のズームを確定しビジュアルスケールをリセット
                    guard viewModel.hasOpenFile else { return }

                    let dampening: CGFloat = 0.5
                    let dampedValue = 1.0 + (value - 1.0) * dampening
                    viewModel.setZoom(magnificationGestureBaseline * dampedValue)
                    magnificationGestureBaseline = viewModel.zoomLevel
                    pinchGestureScale = 1.0
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
                historyState.showHistory = false

                // SwiftUIのフォーカスを設定（.onKeyPressが動作するために必要）
                focusMainView()

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
                historyState.incrementScrollTrigger()

                // 初期画面に戻ったので、必要に応じて履歴とカタログを再読み込み
                if historyState.showHistory {
                    historyManager.notifyHistoryUpdate()
                    imageCatalogManager.notifyCatalogUpdate()
                }

                // 初期画面に戻ったのでフォーカスを復元
                focusMainView()
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
                    getter: { self.historyState.showHistory },
                    setter: { self.historyState.showHistory = $0 }
                )
                WindowCoordinator.shared.registerSearchFocus(
                    windowNumber: newNumber,
                    getter: { self.isHistorySearchFocused },
                    setter: { self.isHistorySearchFocused = $0 }
                )
                WindowCoordinator.shared.registerClearSelection(
                    windowNumber: newNumber,
                    callback: { self.historyState.clearSelection() }
                )
                WindowCoordinator.shared.registerFocusMainView(
                    windowNumber: newNumber,
                    callback: { self.focusMainView() }
                )
                WindowCoordinator.shared.registerOpenFilePicker(
                    windowNumber: newNumber,
                    callback: { self.openFilePicker() }
                )
            }
        }
        .onChange(of: historyState.showHistoryFilter) { _, newValue in
            // フィルタが非表示になったらメインビューにフォーカスを戻す
            if !newValue {
                DispatchQueue.main.async {
                    self.focusMainView()
                }
            }
        }
        .onChange(of: historyState.showHistory) { _, newValue in
            // 「終了時の状態を復元」モードの場合は保存
            if appSettings.historyDisplayMode == .restoreLast {
                appSettings.lastHistoryVisible = newValue
            }
            if newValue {
                // 履歴表示が有効になったら、必要に応じて履歴とカタログを再読み込み
                historyManager.notifyHistoryUpdate()
                imageCatalogManager.notifyCatalogUpdate()
                // リスト未選択なら検索フィールドにフォーカス
                if historyState.selectedItem == nil {
                    DispatchQueue.main.async {
                        isHistorySearchFocused = true
                    }
                }
            } else {
                // 履歴を閉じたらメインビューにフォーカスを戻す
                isHistorySearchFocused = false
                DispatchQueue.main.async {
                    self.focusMainView()
                }
            }
        }
        .onChange(of: modalState.showMemoEdit) { _, newValue in
            handleModalFocusChange(isShowing: newValue)
        }
        .onChange(of: modalState.showBatchMetadataEdit) { _, newValue in
            handleModalFocusChange(isShowing: newValue)
        }
        .onChange(of: modalState.showStructuredMetadataEdit) { _, newValue in
            handleModalFocusChange(isShowing: newValue)
        }
        .modifier(FocusSyncModifier(
            isHistorySearchFocused: $isHistorySearchFocused,
            historyState: historyState,
            onSearchFocusLost: {
                focusMainView(selectFirstHistoryItem: true)
            }
        ))
        // キー入力は setupKeyDownMonitor() のNSEventモニタで一元管理
        // HistoryViews.swiftの検索フィールド用.onKeyPressは別途維持
        .onReceive(NotificationCenter.default.publisher(for: .windowDidBecomeKey)) { notification in
            let start = CFAbsoluteTimeGetCurrent()
            // 自分のウィンドウがフォーカスを得た場合のみ履歴を更新
            guard let windowNumber = notification.userInfo?["windowNumber"] as? Int,
                  windowNumber == myWindowNumber else { return }
            // scrollTrigger をインクリメントして HistoryListView を再描画
            historyState.incrementScrollTrigger()
            // ウィンドウがフォーカスを得た時にメインビューのフォーカスを復元
            // （検索フィールドにフォーカスがない場合のみ）
            if !isHistorySearchFocused {
                focusMainView()
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DebugLogger.log("⏱️ onReceive scrollTrigger update: \(String(format: "%.1f", elapsed))ms", level: .normal)
        }
        .overlay { modalOverlays }
    }

    // MARK: - Modal Overlays

    @ViewBuilder
    private var structuredMetadataEditOverlay: some View {
        Color.black.opacity(0.8)
            .ignoresSafeArea()
            .onTapGesture {
                modalState.closeStructuredMetadataEdit()
            }

        StructuredMetadataEditor(
            isBatch: modalState.isStructuredEditBatch,
            itemCount: modalState.structuredEditTargets.count,
            metadataIndex: currentMetadataIndex(),
            tags: $modalState.structuredEditTags,
            partialTags: $modalState.structuredEditPartialTags,
            attributes: $modalState.structuredEditAttributes,
            partialAttributes: $modalState.structuredEditPartialAttributes,
            plainText: $modalState.structuredEditPlainText,
            originalTags: modalState.structuredEditOriginalTags,
            originalPartialTags: modalState.structuredEditOriginalPartialTags,
            originalAttributes: modalState.structuredEditOriginalAttributes,
            originalPartialAttributes: modalState.structuredEditOriginalPartialAttributes,
            onSave: { result in
                saveStructuredMetadata(result)
                modalState.closeStructuredMetadataEdit()
            },
            onCancel: {
                modalState.closeStructuredMetadataEdit()
            }
        )
    }

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
                providers: memoSuggestionProviders(),
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

        // 一括メタデータ編集モーダル
        if modalState.showBatchMetadataEdit {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    modalState.closeBatchMetadataEdit()
                }

            BatchMetadataEditPopover(
                itemCount: modalState.batchMetadataTargets.count,
                metadataText: $modalState.batchMetadataText,
                providers: memoSuggestionProviders(),
                onSave: {
                    saveBatchMetadata()
                    modalState.closeBatchMetadataEdit()
                },
                onCancel: {
                    modalState.closeBatchMetadataEdit()
                }
            )
        }

        // 構造化メタデータ編集モーダル
        if modalState.showStructuredMetadataEdit {
            structuredMetadataEditOverlay
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
                        self.focusMainView()
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
                        self.focusMainView()
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
        historyState.showHistory = appSettings.shouldShowHistoryOnLaunch

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

        // ファイルを開く（共通経路を使用）
        let url = URL(fileURLWithPath: fileOpen.filePath)
        openFilesInCurrentWindow(urls: [url])
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
        // ウィンドウスイッチャーに表示されないように設定
        alert.window.collectionBehavior = [.transient, .ignoresCycle]
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

            switch self.interactionMode {
            case .modal:
                // モーダルダイアログ表示中は全キーをSwiftUIに委譲
                return event

            case .searchField:
                // ↓キー: サジェスト非表示時はリストへフォーカス移動
                if event.keyCode == 125 && self.canNavigateHistory && !self.historyState.isShowingSuggestions {
                    self.exitSearchField()
                    return nil
                }
                // その他はSwiftUIに委譲（テキスト編集、サジェスト操作優先）
                return event

            case .historyList:
                // ↑↓PageUp/Down/Returnで履歴操作
                let isShift = event.modifierFlags.contains(.shift)
                let isCmd = event.modifierFlags.contains(.command)
                switch event.keyCode {
                case 126: // ↑
                    if isCmd {
                        self.handleHistoryCursorMove(offset: -1)
                    } else {
                        self.handleHistoryUpArrow(extend: isShift)
                    }
                    return nil
                case 125: // ↓
                    if isCmd {
                        self.handleHistoryCursorMove(offset: 1)
                    } else {
                        self.handleHistoryDownArrow(extend: isShift)
                    }
                    return nil
                case 49 where event.modifierFlags.contains(.control): // Ctrl+Space: カーソル位置のトグル
                    if let current = self.historyState.selectedItem {
                        self.historyState.toggleSelectionKeepingCursor(current)
                    }
                    return nil
                case 116: // PageUp
                    self.historyState.selectItem(byOffset: -self.pageScrollCount, extend: isShift)
                    return nil
                case 121: // PageDown
                    self.historyState.selectItem(byOffset: self.pageScrollCount, extend: isShift)
                    return nil
                case 36: // Return
                    self.handleHistoryReturn(isShift: event.modifierFlags.contains(.shift))
                    return nil
                default:
                    break
                }
                // 共通キー処理（Escape等）
                return self.handleCommonKeys(event, viewModel: viewModel)

            case .viewing:
                // CustomShortcutManager（デフォルト+カスタムバインディング）
                if let action = CustomShortcutManager.shared.findAction(for: event) {
                    DebugLogger.log("🔑 Shortcut: \(action.rawValue)", level: .normal)
                    if self.executeShortcutAction(action, viewModel: viewModel) {
                        return nil
                    }
                }
                // 矢印キー（読み方向連動）
                if self.handleArrowKeys(event, viewModel: viewModel) {
                    return nil
                }
                // 共通キー処理（Escape等）
                return self.handleCommonKeys(event, viewModel: viewModel)

            case .initial:
                // 共通キー処理（Escape、M、Return）
                return self.handleCommonKeys(event, viewModel: viewModel)
            }
        }
    }

    /// トラックパッドスワイプ用の状態
    private enum TrackpadSwipeState {
        case idle       // 待機中
        case tracking   // 追跡中（まだ発火していない）
        case triggered  // 発火済み（ジェスチャー終了まで待機）
    }
    private static var trackpadSwipeState: TrackpadSwipeState = .idle
    private static var trackpadAccumulatedDeltaX: CGFloat = 0
    private static let trackpadSwipeThreshold: CGFloat = 50.0

    private func setupScrollWheelMonitor() {
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak viewModel] event in
            // 自分のウィンドウか確認
            guard self.myWindowNumber == NSApp.keyWindow?.windowNumber else {
                return event
            }

            // ファイルが開いているか確認
            guard viewModel?.hasOpenFile == true else {
                return event
            }

            // Command+ホイール → ズーム
            if event.modifierFlags.contains(.command) {
                let delta = event.scrollingDeltaY
                let zoomFactor: CGFloat = 1.0 + (delta * 0.01)
                if let currentZoom = viewModel?.zoomLevel {
                    viewModel?.setZoom(currentZoom * zoomFactor)
                }
                return nil
            }

            // トラックパッドのみページめくり（マウスホイールは無視）
            guard event.hasPreciseScrollingDeltas else {
                return event
            }

            // 履歴表示中はイベントを通す（履歴リストのスクロール用）
            if self.historyState.showHistory {
                return event
            }

            // ズーム中または縦横フィット時はスクロール用イベントを通す
            if let zoomLevel = viewModel?.zoomLevel, zoomLevel > 1.0 {
                return event
            }
            if let fittingMode = viewModel?.fittingMode, fittingMode == .height || fittingMode == .width {
                return event
            }

            // 慣性スクロールは無視
            if event.momentumPhase != [] {
                return nil
            }

            // 縦スクロールが優勢な場合は通常のスクロールとして扱う
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) * 2 {
                return event
            }

            // 新しいジェスチャーが開始されたらリセット
            if event.phase == .began {
                ContentView.trackpadSwipeState = .idle
                ContentView.trackpadAccumulatedDeltaX = 0
            }

            switch ContentView.trackpadSwipeState {
            case .idle:
                if event.phase == .began || event.phase == .changed {
                    ContentView.trackpadSwipeState = .tracking
                    ContentView.trackpadAccumulatedDeltaX = event.scrollingDeltaX
                }

            case .tracking:
                if event.phase == .ended || event.phase == .cancelled {
                    ContentView.trackpadSwipeState = .idle
                    ContentView.trackpadAccumulatedDeltaX = 0
                    return nil
                }

                ContentView.trackpadAccumulatedDeltaX += event.scrollingDeltaX

                if abs(ContentView.trackpadAccumulatedDeltaX) > ContentView.trackpadSwipeThreshold {
                    ContentView.trackpadSwipeState = .triggered
                    viewModel?.nextNavigationIsSwipe = true
                    let isRTL = viewModel?.readingDirection == .rightToLeft
                    if ContentView.trackpadAccumulatedDeltaX > 0 {
                        if isRTL { viewModel?.nextPage() } else { viewModel?.previousPage() }
                    } else {
                        if isRTL { viewModel?.previousPage() } else { viewModel?.nextPage() }
                    }
                }

            case .triggered:
                if event.phase == .ended || event.phase == .cancelled {
                    ContentView.trackpadSwipeState = .idle
                    ContentView.trackpadAccumulatedDeltaX = 0
                }
            }

            return nil
        }
    }


    /// ショートカットアクションを実行
    /// - Returns: アクションが実行された場合はtrue
    private func executeShortcutAction(_ action: ShortcutAction, viewModel: BookViewModel?) -> Bool {
        guard let viewModel = viewModel else { return false }

        // ファイルが開いていない場合はアクション不可
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
        case .shiftPageForward:
            viewModel.shiftPage(forward: true)
        case .shiftPageBackward:
            viewModel.shiftPage(forward: false)
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
        // ファイルを閉じて画像ソースを解放（ビュー再評価による不要なZIP展開を防止）
        viewModel.closeFile()

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

    // MARK: - Focus Management

    /// モーダル表示変更時のフォーカス管理
    private func handleModalFocusChange(isShowing: Bool) {
        if isShowing {
            isHistorySearchFocused = false
            isMainViewFocused = false
        } else {
            DispatchQueue.main.async {
                self.focusMainView()
            }
        }
    }

    /// メインビューにフォーカスを移す
    private func focusMainView(selectFirstHistoryItem: Bool = false) {
        // モーダル表示中はフォーカスを奪わない
        guard interactionMode != .modal else { return }
        isMainViewFocused = true
        if selectFirstHistoryItem, historyState.selectedItem == nil,
           let first = historyState.visibleItems.first {
            historyState.select(first)
        }
    }

    /// 検索フィールドにフォーカスを移す
    private func focusSearchField() {
        historyState.clearSelection()
        isHistorySearchFocused = true
    }

    /// 検索フィールドからフォーカスを外す（リスト移動時）
    private func exitSearchField() {
        isHistorySearchFocused = false
        focusMainView(selectFirstHistoryItem: true)
    }

    // MARK: - Key Handlers

    /// キーイベントの処理モードを表す列挙型
    /// setupKeyDownMonitor() で switch ベースのディスパッチに使用
    private enum InteractionMode {
        case modal       // モーダルダイアログ表示中 → 全キーをSwiftUIに委譲
        case searchField // 検索フィールドフォーカス中 → テキスト編集優先
        case historyList // 履歴リストナビゲーション中 → ↑↓PageUp/Down/Return
        case viewing     // 画像閲覧中 → ショートカット、矢印キー
        case initial     // 初期画面 → メモ編集、履歴操作
    }

    /// 現在のインタラクションモードを既存の状態から計算
    private var interactionMode: InteractionMode {
        // モーダル（5種全て: メモ編集、一括メタデータ編集、画像情報、パスワード、ファイル同一性）
        if modalState.showMemoEdit || modalState.showBatchMetadataEdit || modalState.showImageInfo
            || modalState.showStructuredMetadataEdit
            || viewModel.showPasswordDialog || viewModel.showFileIdentityDialog {
            return .modal
        }
        if isHistorySearchFocused { return .searchField }
        if canNavigateHistoryList { return .historyList }
        if viewModel.hasOpenFile { return .viewing }
        return .initial
    }

    /// 履歴ナビゲーションが可能な状態か（履歴表示中かつ履歴あり）
    private var canNavigateHistory: Bool {
        historyState.canNavigateHistory
    }

    /// 履歴リストのキーボードナビゲーションが可能な状態か（候補表示中・検索フォーカス中を除く）
    private var canNavigateHistoryList: Bool {
        historyState.canNavigateHistoryList && !isHistorySearchFocused
    }

    /// PageUp/PageDownで移動するアイテム数
    private let pageScrollCount = 10

    // MARK: - 履歴リストUI操作ハンドラ（NSEventモニタから呼び出し）

    /// Ctrl+矢印: カーソルだけ移動（選択は変えない）
    private func handleHistoryCursorMove(offset: Int) {
        if let current = historyState.selectedItem,
           let currentIndex = historyState.visibleItems.firstIndex(where: { $0.id == current.id }) {
            let newIndex = max(0, min(historyState.visibleItems.count - 1, currentIndex + offset))
            historyState.selectedItem = historyState.visibleItems[newIndex]
        } else if let first = historyState.visibleItems.first {
            historyState.selectedItem = first
        }
    }

    private func handleHistoryUpArrow(extend: Bool = false) {
        if let current = historyState.selectedItem,
           let currentIndex = historyState.visibleItems.firstIndex(where: { $0.id == current.id }) {
            if currentIndex > 0 {
                let item = historyState.visibleItems[currentIndex - 1]
                if extend {
                    historyState.extendSelection(to: item)
                } else {
                    historyState.select(item)
                }
            } else if !extend {
                // 先頭にいる場合は検索フィールドにフォーカス
                focusSearchField()
            }
        } else if let last = historyState.visibleItems.last {
            historyState.select(last)
        }
    }

    private func handleHistoryDownArrow(extend: Bool = false) {
        if let current = historyState.selectedItem,
           let currentIndex = historyState.visibleItems.firstIndex(where: { $0.id == current.id }) {
            if currentIndex < historyState.visibleItems.count - 1 {
                let item = historyState.visibleItems[currentIndex + 1]
                if extend {
                    historyState.extendSelection(to: item)
                } else {
                    historyState.select(item)
                }
            }
        } else if let first = historyState.visibleItems.first {
            historyState.select(first)
        }
    }

    private func handleHistoryReturn(isShift: Bool) {
        let items = historyState.selectedItems
        guard !items.isEmpty else { return }

        // 複数選択時は全て新しいウィンドウで開く
        if items.count > 1 {
            for item in items {
                openItemInNewWindow(item)
            }
            return
        }

        // 単一選択
        guard let selected = items.first else { return }

        switch selected {
        case .archive(_, let filePath):
            if isShift { openInNewWindow(path: filePath) }
            else { openHistoryFile(path: filePath) }
        case .standaloneImage(_, let filePath):
            if isShift { openInNewWindow(path: filePath) }
            else { openImageCatalogFile(path: filePath, relativePath: nil) }
        case .archivedImage(_, let parentPath, let relativePath):
            if isShift { openInNewWindow(path: parentPath) }
            else { openImageCatalogFile(path: parentPath, relativePath: relativePath.isEmpty ? nil : relativePath) }
        case .session(let sessionId):
            if let session = sessionGroupManager.sessionGroups.first(where: { $0.id == sessionId }) {
                sessionGroupManager.updateLastAccessed(id: session.id)
                sessionManager.restoreSessionGroup(session)
            }
        }
    }

    /// アイテムを新しいウィンドウで開く
    private func openItemInNewWindow(_ item: SelectableHistoryItem) {
        switch item {
        case .archive(_, let filePath):
            openInNewWindow(path: filePath)
        case .standaloneImage(_, let filePath):
            openInNewWindow(path: filePath)
        case .archivedImage(_, let parentPath, _):
            openInNewWindow(path: parentPath)
        case .session(let sessionId):
            if let session = sessionGroupManager.sessionGroups.first(where: { $0.id == sessionId }) {
                sessionGroupManager.updateLastAccessed(id: session.id)
                sessionManager.restoreSessionGroup(session)
            }
        }
    }

    private func handleMemoEdit(selected: SelectableHistoryItem) {
        switch selected {
        case .archive(let id, _):
            if let entry = historyManager.history.first(where: { $0.id == id }) {
                modalState.openMemoEditForHistory(fileKey: entry.id, memo: entry.memo)
            }
        case .standaloneImage(let id, _), .archivedImage(let id, _, _):
            if let entry = imageCatalogManager.catalog.first(where: { $0.id == id }) {
                modalState.openMemoEditForCatalog(catalogId: id, memo: entry.memo)
            }
        case .session:
            break
        }
    }

    /// 単一選択時の構造化メモ編集を開く
    private func handleStructuredMemoEdit(selected: SelectableHistoryItem) {
        switch selected {
        case .archive(let id, _):
            if let entry = historyManager.history.first(where: { $0.id == id }) {
                modalState.openStructuredEditForSingle(fileKey: entry.id, catalogId: nil, memo: entry.memo)
            }
        case .standaloneImage(let id, _), .archivedImage(let id, _, _):
            if let entry = imageCatalogManager.catalog.first(where: { $0.id == id }) {
                modalState.openStructuredEditForSingle(fileKey: nil, catalogId: id, memo: entry.memo)
            }
        case .session:
            break
        }
    }

    /// 複数選択時の構造化一括メタデータ編集を開く
    private func openStructuredBatchMetadataEdit() {
        let items = historyState.selectedItems
        guard items.count > 1 else { return }

        var memos: [String?] = []
        var targets: [(historyId: String?, catalogId: String?)] = []

        for item in items {
            switch item {
            case .archive(let id, _):
                let memo = historyManager.history.first(where: { $0.id == id })?.memo
                memos.append(memo)
                targets.append((historyId: id, catalogId: nil))
            case .standaloneImage(let id, _), .archivedImage(let id, _, _):
                let memo = imageCatalogManager.catalog.first(where: { $0.id == id })?.memo
                memos.append(memo)
                targets.append((historyId: nil, catalogId: id))
            case .session:
                break
            }
        }

        guard !targets.isEmpty else { return }

        // 各メモのタグ・属性を抽出
        let parsedList = memos.map { MemoMetadataParser.parse($0) }

        // 共通タグ（全アイテムに存在）
        var commonTags = parsedList.first?.tags ?? []
        for parsed in parsedList.dropFirst() {
            commonTags = commonTags.intersection(parsed.tags)
        }

        // 部分タグ（一部のアイテムにのみ存在）
        var allTags = Set<String>()
        for parsed in parsedList {
            allTags.formUnion(parsed.tags)
        }
        let partialTags = allTags.subtracting(commonTags)

        // 共通属性（全アイテムで同キー同値）
        var commonAttrs = parsedList.first?.attributes ?? [:]
        for parsed in parsedList.dropFirst() {
            commonAttrs = commonAttrs.filter { parsed.attributes[$0.key] == $0.value }
        }

        // 部分属性（一部のアイテムにのみ存在、または値が異なる）
        // 各キーについて最頻値を代表値として表示する
        var allAttrKeys = Set<String>()
        for parsed in parsedList {
            allAttrKeys.formUnion(parsed.attributes.keys)
        }
        let partialAttrKeys = allAttrKeys.subtracting(commonAttrs.keys)
        var partialAttrs: [(key: String, value: String)] = []
        for key in partialAttrKeys.sorted() {
            // 最頻値を代表値として選ぶ
            var valueCounts: [String: Int] = [:]
            for parsed in parsedList {
                if let value = parsed.attributes[key] {
                    valueCounts[value, default: 0] += 1
                }
            }
            let representativeValue = valueCounts.max(by: { $0.value < $1.value })?.key ?? ""
            partialAttrs.append((key: key, value: representativeValue))
        }

        modalState.openStructuredEditForBatch(
            commonTags: commonTags,
            partialTags: partialTags,
            commonAttrs: commonAttrs,
            partialAttrs: partialAttrs,
            targets: targets
        )
    }

    /// メタデータインデックスを取得（サジェスト用）
    private func currentMetadataIndex() -> MemoMetadataParser.MetadataIndex {
        MemoMetadataParser.collectIndex(
            from: historyManager.history.map(\.memo) + imageCatalogManager.catalog.map(\.memo)
        )
    }

    /// 構造化メタデータ編集の結果を保存
    private func saveStructuredMetadata(_ result: MetadataEditResult) {
        if modalState.isStructuredEditBatch {
            // 一括: 差分を各アイテムに適用
            for target in modalState.structuredEditTargets {
                if let historyId = target.historyId {
                    let currentMemo = historyManager.history.first(where: { $0.id == historyId })?.memo
                    let newMemo = MemoMetadataParser.applyMetadataChanges(
                        to: currentMemo, tagsToAdd: result.tagsToAdd, tagsToRemove: result.tagsToRemove,
                        attrsToAdd: result.attrsToAdd, attrsToRemove: result.attrsToRemove)
                    historyManager.updateMemo(for: historyId, memo: newMemo)
                }
                if let catalogId = target.catalogId {
                    let currentMemo = imageCatalogManager.catalog.first(where: { $0.id == catalogId })?.memo
                    let newMemo = MemoMetadataParser.applyMetadataChanges(
                        to: currentMemo, tagsToAdd: result.tagsToAdd, tagsToRemove: result.tagsToRemove,
                        attrsToAdd: result.attrsToAdd, attrsToRemove: result.attrsToRemove)
                    imageCatalogManager.updateMemo(for: catalogId, memo: newMemo)
                }
            }
        } else {
            // 単一: 再構築されたメモを保存
            if let fileKey = modalState.structuredEditFileKey {
                historyManager.updateMemo(for: fileKey, memo: result.memo)
            } else if let catalogId = modalState.structuredEditCatalogId {
                imageCatalogManager.updateMemo(for: catalogId, memo: result.memo)
            }
        }
    }

    /// 複数選択時の一括メタデータ編集を開く（rawテキスト）
    private func openBatchMetadataEdit() {
        let items = historyState.selectedItems
        guard items.count > 1 else { return }

        // 各アイテムのメモとターゲット情報を収集
        var memos: [String?] = []
        var targets: [(historyId: String?, catalogId: String?)] = []

        for item in items {
            switch item {
            case .archive(let id, _):
                let memo = historyManager.history.first(where: { $0.id == id })?.memo
                memos.append(memo)
                targets.append((historyId: id, catalogId: nil))
            case .standaloneImage(let id, _), .archivedImage(let id, _, _):
                let memo = imageCatalogManager.catalog.first(where: { $0.id == id })?.memo
                memos.append(memo)
                targets.append((historyId: nil, catalogId: id))
            case .session:
                break
            }
        }

        guard !targets.isEmpty else { return }

        // 各メモのタグ・属性を抽出して共通部分（積集合）を計算
        let parsedList = memos.map { MemoMetadataParser.parse($0) }
        var commonTags = parsedList.first?.tags ?? []
        var commonAttrs = parsedList.first?.attributes ?? [:]

        for parsed in parsedList.dropFirst() {
            commonTags = commonTags.intersection(parsed.tags)
            commonAttrs = commonAttrs.filter { parsed.attributes[$0.key] == $0.value }
        }

        // 共通部分をテキスト形式に変換
        var parts: [String] = []
        for tag in commonTags.sorted() {
            parts.append("#\(tag)")
        }
        for (key, value) in commonAttrs.sorted(by: { $0.key < $1.key }) {
            parts.append("@\(key):\(value)")
        }
        let commonText = parts.joined(separator: " ")

        modalState.openBatchMetadataEdit(commonMetadataText: commonText, targets: targets)
    }

    /// 一括メタデータ編集の差分を各アイテムに適用
    /// メモ編集用のサジェストプロバイダーを構築（コロン区切り）
    private func memoSuggestionProviders() -> [any SearchSuggestionProvider] {
        let metadataIndex = MemoMetadataParser.collectIndex(
            from: historyManager.history.map(\.memo) + imageCatalogManager.catalog.map(\.memo)
        )
        return [
            TagSuggestionProvider(availableTags: metadataIndex.tags),
        ]
        + metadataIndex.values.map { key, values in
            MemoMetadataValueSuggestionProvider(key: key, availableValues: values)
                as any SearchSuggestionProvider
        }
        + [
            MemoMetadataKeySuggestionProvider(availableKeys: metadataIndex.keys),
        ]
    }

    private func saveBatchMetadata() {
        let original = MemoMetadataParser.parse(
            modalState.batchMetadataOriginal.isEmpty ? nil : modalState.batchMetadataOriginal)
        let edited = MemoMetadataParser.parse(
            modalState.batchMetadataText.isEmpty ? nil : modalState.batchMetadataText)

        let tagsToAdd = edited.tags.subtracting(original.tags)
        let tagsToRemove = original.tags.subtracting(edited.tags)
        let attrsToAdd = edited.attributes.filter { original.attributes[$0.key] != $0.value }
        let attrsToRemove = Set(original.attributes.keys).subtracting(edited.attributes.keys)

        for target in modalState.batchMetadataTargets {
            if let historyId = target.historyId {
                let currentMemo = historyManager.history.first(where: { $0.id == historyId })?.memo
                let newMemo = MemoMetadataParser.applyMetadataChanges(
                    to: currentMemo, tagsToAdd: tagsToAdd, tagsToRemove: tagsToRemove,
                    attrsToAdd: attrsToAdd, attrsToRemove: attrsToRemove)
                historyManager.updateMemo(for: historyId, memo: newMemo)
            }
            if let catalogId = target.catalogId {
                let currentMemo = imageCatalogManager.catalog.first(where: { $0.id == catalogId })?.memo
                let newMemo = MemoMetadataParser.applyMetadataChanges(
                    to: currentMemo, tagsToAdd: tagsToAdd, tagsToRemove: tagsToRemove,
                    attrsToAdd: attrsToAdd, attrsToRemove: attrsToRemove)
                imageCatalogManager.updateMemo(for: catalogId, memo: newMemo)
            }
        }
    }

    /// 矢印キーのページ遷移処理（viewingモード専用）
    /// - Returns: キーが処理された場合はtrue
    private func handleArrowKeys(_ event: NSEvent, viewModel: BookViewModel?) -> Bool {
        guard viewModel?.hasOpenFile == true else { return false }
        switch event.keyCode {
        case 123: // ←
            let isRTL = viewModel?.readingDirection == .rightToLeft
            if event.modifierFlags.contains(.shift) {
                viewModel?.shiftPage(forward: isRTL == true)
            } else {
                if isRTL == true { viewModel?.nextPage() } else { viewModel?.previousPage() }
            }
            return true
        case 124: // →
            let isRTL = viewModel?.readingDirection == .rightToLeft
            if event.modifierFlags.contains(.shift) {
                viewModel?.shiftPage(forward: isRTL != true)
            } else {
                if isRTL == true { viewModel?.previousPage() } else { viewModel?.nextPage() }
            }
            return true
        default:
            return false
        }
    }

    /// Escape（履歴閉じ）、M（メモ編集）、Return（履歴オープン）、Delete（一括削除）、⌘A（全選択）の共通処理
    /// historyList/viewing/initialで共有
    private func handleCommonKeys(_ event: NSEvent, viewModel: BookViewModel?) -> NSEvent? {
        // Escape: 履歴を閉じる
        if event.keyCode == 53 && historyState.showHistory {
            historyState.closeHistory()
            isHistorySearchFocused = false
            focusMainView()
            return nil
        }

        // ⌘A: 全選択（履歴表示中のみ）
        if event.keyCode == 0 && event.modifierFlags.contains(.command)
            && historyState.showHistory && !isHistorySearchFocused {
            historyState.selectAll()
            return nil
        }

        // Delete/Backspace: 選択アイテムを一括削除（履歴表示中のみ）
        if event.keyCode == 51 && historyState.showHistory && !isHistorySearchFocused
            && !historyState.selectedItems.isEmpty {
            deleteSelectedItems()
            return nil
        }

        // M: メモ編集（履歴アイテム選択時）
        // M（修飾キーなし）→ 構造化UI、Option+M → rawテキスト編集
        if event.keyCode == 46 && !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.control) {
            let isOption = event.modifierFlags.contains(.option)
            if historyState.selectedItems.count > 1 {
                if isOption {
                    openBatchMetadataEdit()
                } else {
                    openStructuredBatchMetadataEdit()
                }
                return nil
            } else if historyState.selectedItems.count == 1, let selected = historyState.selectedItems.first {
                if isOption {
                    handleMemoEdit(selected: selected)
                } else {
                    handleStructuredMemoEdit(selected: selected)
                }
                return nil
            }
        }

        // Return: 履歴アイテムを開く（履歴表示中のみ）
        if event.keyCode == 36 && historyState.showHistory && !isHistorySearchFocused {
            if !historyState.selectedItems.isEmpty {
                handleHistoryReturn(isShift: event.modifierFlags.contains(.shift))
                return nil
            }
        }

        return event
    }

    /// 選択中のアイテムを一括削除
    private func deleteSelectedItems() {
        let items = historyState.selectedItems
        guard !items.isEmpty else { return }

        let archiveIds = items.compactMap { item -> String? in
            if case .archive(let id, _) = item { return id }
            return nil
        }
        let imageIds = items.compactMap { item -> String? in
            if case .standaloneImage(let id, _) = item { return id }
            if case .archivedImage(let id, _, _) = item { return id }
            return nil
        }
        let sessionIds = items.compactMap { item -> UUID? in
            if case .session(let id) = item { return id }
            return nil
        }

        if !archiveIds.isEmpty { historyManager.removeEntries(withIds: archiveIds) }
        if !imageIds.isEmpty { imageCatalogManager.removeEntries(withIds: imageIds) }
        for id in sessionIds { sessionGroupManager.deleteSessionGroup(id: id) }
        historyState.clearSelection()
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

    /// 選択中のアイテムを全て新しいウィンドウで開く（複数選択対応）
    private func openSelectedInNewWindow(path: String) {
        let items = historyState.selectedItems
        if items.count > 1 {
            for item in items {
                openItemInNewWindow(item)
            }
        } else {
            openInNewWindow(path: path)
        }
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
                    self.focusMainView()

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

/// @FocusStateとHistoryUIState.isSearchFocusedを同期するViewModifier
struct FocusSyncModifier: ViewModifier {
    @FocusState.Binding var isHistorySearchFocused: Bool
    let historyState: HistoryUIState
    /// 検索フィールドからフォーカスが外れた時のコールバック（履歴リストへの移動時のみ）
    var onSearchFocusLost: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: isHistorySearchFocused) { _, newValue in
                historyState.isSearchFocused = newValue
                // フォーカスが外れた時、遅延して履歴が表示中か確認
                // （履歴を閉じる操作の場合は呼ばない）
                if !newValue {
                    DispatchQueue.main.async {
                        // 遅延後も履歴が表示中なら、リストへの移動とみなす
                        if historyState.showHistory {
                            onSearchFocusLost?()
                        }
                    }
                }
            }
            .onChange(of: historyState.isSearchFocused) { _, newValue in
                if isHistorySearchFocused != newValue {
                    isHistorySearchFocused = newValue
                }
            }
    }
}
