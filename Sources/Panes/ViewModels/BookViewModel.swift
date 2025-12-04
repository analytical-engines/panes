import Foundation
import SwiftUI
import AppKit

/// 表示モード
enum ViewMode {
    case single  // 単ページ
    case spread  // 見開き
}

/// 読み方向
enum ReadingDirection {
    case rightToLeft  // 右→左（漫画）
    case leftToRight  // 左→右（洋書）
}

/// ページの表示状態
enum PageDisplay: Equatable {
    case single(Int)           // 単ページ表示: [n]
    case spread(Int, Int)      // 見開き表示: [left, right] (RTL: left > right)

    /// 表示されているページのインデックス配列
    var indices: [Int] {
        switch self {
        case .single(let page): return [page]
        case .spread(let left, let right): return [left, right]
        }
    }

    /// 表示されている最大インデックス
    var maxIndex: Int {
        switch self {
        case .single(let page): return page
        case .spread(let left, _): return left  // RTL: leftが大きい
        }
    }

    /// 表示されている最小インデックス
    var minIndex: Int {
        switch self {
        case .single(let page): return page
        case .spread(_, let right): return right  // RTL: rightが小さい
        }
    }

    /// 見開き表示かどうか
    var isSpread: Bool {
        if case .spread = self { return true }
        return false
    }

    /// 指定ページが表示に含まれているか
    func contains(_ page: Int) -> Bool {
        return indices.contains(page)
    }
}

/// 書籍（画像アーカイブ）の表示状態を管理するViewModel
@MainActor
@Observable
class BookViewModel {

    // 横長画像判定のアスペクト比閾値（幅/高さ）
    private var landscapeAspectRatioThreshold: CGFloat = 1.2

    // 閾値変更通知のオブザーバー
    private var thresholdChangeTask: Task<Void, Never>?

    // アプリ全体設定への参照
    var appSettings: AppSettings? {
        didSet {
            applyDefaultSettings()
        }
    }

    // 画像ソース
    private var imageSource: ImageSource?

    // UserDefaultsのキー
    private let viewModeKey = "viewMode"
    private let currentPageKey = "currentPage"
    private let readingDirectionKey = "readingDirection"

    // 履歴管理（外部から注入される）
    var historyManager: FileHistoryManager?

    // ページ表示設定
    private var pageDisplaySettings: PageDisplaySettings = PageDisplaySettings()

    // 現在表示中の画像（単ページモード用）
    var currentImage: NSImage?

    // 見開き表示用：最初のページ（currentPage）
    var firstPageImage: NSImage?

    // 見開き表示用：2番目のページ（currentPage + 1）
    var secondPageImage: NSImage?

    // 現在のページ番号（0始まり）
    var currentPage: Int = 0

    // 現在の表示状態
    private(set) var currentDisplay: PageDisplay = .single(0)

    // 総ページ数（元の画像数）
    var totalPages: Int = 0

    // 表示可能ページ数（非表示を除く）
    var visiblePageCount: Int {
        return totalPages - pageDisplaySettings.hiddenPageCount
    }

    // ソース名（ファイル名など）
    var sourceName: String = ""

    // エラーメッセージ
    var errorMessage: String?

    // 表示モード
    var viewMode: ViewMode = .single

    // 読み方向
    var readingDirection: ReadingDirection = .rightToLeft

    // ステータスバー表示
    var showStatusBar: Bool = true

    // 現在開いているファイルのパス
    private(set) var currentFilePath: String?

    /// 現在開いているファイルのキー（セッション保存用）
    var currentFileKey: String? {
        imageSource?.generateFileKey()
    }

    /// デバッグ出力（レベル指定）
    private func debugLog(_ message: String, level: DebugLevel = .normal) {
        DebugLogger.log("DEBUG: \(message)", level: level)
    }

    /// 指定されたページが横長かどうかを判定して、必要なら単ページ属性を設定
    /// @return 判定した結果、単ページ属性を持つかどうか
    private func checkAndSetLandscapeAttribute(for index: Int) -> Bool {
        guard let source = imageSource else { return false }

        // ユーザーが手動で設定している場合はそれを優先
        if pageDisplaySettings.isUserForcedSinglePage(index) {
            return true
        }

        // まだ判定していないページなら判定する（回転を考慮）
        if !pageDisplaySettings.isPageChecked(index) {
            debugLog("Checking page \(index) for landscape aspect ratio", level: .verbose)
            if let size = source.imageSize(at: index) {
                // 回転を考慮した実効アスペクト比を計算
                let rotation = pageDisplaySettings.rotation(for: index)
                let effectiveWidth: CGFloat
                let effectiveHeight: CGFloat

                if rotation.swapsAspectRatio {
                    // 90度または270度回転の場合、幅と高さを入れ替え
                    effectiveWidth = size.height
                    effectiveHeight = size.width
                } else {
                    effectiveWidth = size.width
                    effectiveHeight = size.height
                }

                let aspectRatio = effectiveWidth / effectiveHeight
                debugLog("Page \(index) size: \(size.width)x\(size.height), rotation: \(rotation.rawValue)°, effective aspect ratio: \(String(format: "%.2f", aspectRatio))", level: .verbose)

                if aspectRatio >= landscapeAspectRatioThreshold {
                    pageDisplaySettings.setAutoDetectedLandscape(index)
                    debugLog("Page \(index) auto-detected as landscape", level: .verbose)
                }
            } else {
                debugLog("Failed to get image size for page \(index)", level: .verbose)
            }
            // 判定済みとしてマーク
            pageDisplaySettings.markAsChecked(index)
        }

        return pageDisplaySettings.isForcedSinglePage(index)
    }

    /// ファイルを閉じて初期画面に戻る
    func closeFile() {
        // 現在の表示状態を保存
        saveViewState()

        // 状態をリセット
        imageSource = nil
        sourceName = ""
        totalPages = 0
        currentPage = 0
        currentImage = nil
        firstPageImage = nil
        secondPageImage = nil
        errorMessage = nil
        pageDisplaySettings = PageDisplaySettings()
        currentFilePath = nil
    }

    /// ファイルが開いているかどうか
    var hasOpenFile: Bool {
        return imageSource != nil
    }

    /// 画像ソースを開く（zipまたは画像ファイル）
    func openSource(_ source: ImageSource) {
        guard source.imageCount > 0 else {
            errorMessage = L("error_no_images_found")
            return
        }

        self.imageSource = source
        self.sourceName = source.sourceName
        self.totalPages = source.imageCount
        self.currentPage = 0
        self.errorMessage = nil
        self.currentFilePath = source.sourceURL?.path

        // 履歴に記録
        if let fileKey = source.generateFileKey(),
           let url = source.sourceURL {
            historyManager?.recordAccess(
                fileKey: fileKey,
                filePath: url.path,
                fileName: source.sourceName
            )
        }

        // 保存された表示状態を復元
        restoreViewState()

        // 画像を読み込む（復元されたページ）
        loadCurrentPage()
    }

    /// zipファイルを開く（互換性のため残す）
    func openArchive(url: URL) {
        if let source = ArchiveImageSource(url: url) {
            openSource(source)
        } else {
            errorMessage = L("error_cannot_open_zip")
        }
    }

    /// 画像ファイル（単一・複数）を開く
    func openImageFiles(urls: [URL]) {
        if let source = FileImageSource(urls: urls) {
            openSource(source)
        } else {
            errorMessage = L("error_cannot_open_images")
        }
    }

    /// URLから適切なソースを自動判定して開く（バックグラウンドで読み込み）
    func openFiles(urls: [URL]) {
        guard !urls.isEmpty else {
            errorMessage = L("error_no_file_selected")
            return
        }

        // バックグラウンドで読み込み、完了後にUI更新
        Task {
            let source = await Self.loadImageSource(from: urls)
            if let source = source {
                self.openSource(source)
            } else {
                self.errorMessage = L("error_cannot_open_file")
            }
        }
    }

    /// バックグラウンドでImageSourceを読み込む
    private nonisolated static func loadImageSource(from urls: [URL]) async -> ImageSource? {
        // アーカイブファイルの場合
        if urls.count == 1 {
            let ext = urls[0].pathExtension.lowercased()
            if ext == "zip" || ext == "cbz" {
                return ArchiveImageSource(url: urls[0])
            } else if ext == "rar" || ext == "cbr" {
                return RarImageSource(url: urls[0])
            } else {
                // 画像ファイルの場合
                return FileImageSource(urls: urls)
            }
        } else {
            // 複数ファイルの場合
            return FileImageSource(urls: urls)
        }
    }

    /// 現在のページの画像を読み込む（ジャンプ操作用、順方向ロジックを使用）
    private func loadCurrentPage() {
        guard imageSource != nil else {
            debugLog("loadCurrentPage - imageSource is nil", level: .minimal)
            return
        }

        debugLog("loadCurrentPage - viewMode: \(viewMode), currentPage: \(currentPage)", level: .verbose)

        // currentPageを起点に表示状態を計算（順方向ロジック）
        let display = calculateDisplayForPage(currentPage)
        currentDisplay = display
        loadImages(for: display)

        debugLog("loadCurrentPage result: \(display)", level: .verbose)
    }

    /// 指定ページを起点とした表示状態を計算（順方向ロジック：currentPageとcurrentPage+1をチェック）
    private func calculateDisplayForPage(_ page: Int) -> PageDisplay {
        // 単ページモードの場合
        if viewMode == .single {
            return .single(page)
        }

        // 見開きモードの場合
        // pageが単ページ属性 → [page]
        if isPageSingle(page) {
            return .single(page)
        }

        // ペア候補を探す（非表示ページはスキップ）
        var pairPage = page + 1
        while pairPage < totalPages && pageDisplaySettings.isHidden(pairPage) {
            pairPage += 1
        }

        // ペア候補が存在しない → [page]
        if pairPage >= totalPages {
            return .single(page)
        }

        // ペア候補が単ページ属性 → [page]
        if isPageSingle(pairPage) {
            return .single(page)
        }

        // 両方とも見開き可能 → [pairPage|page]
        return .spread(pairPage, page)
    }

    /// 次のページへ
    func nextPage() {
        guard imageSource != nil else { return }

        // 現在の表示状態から次の表示状態を計算
        guard let nextDisplay = calculateNextDisplay(
            from: currentDisplay,
            isSinglePage: { self.isPageSingle($0) }
        ) else { return }

        // 表示を更新
        updateCurrentPage(for: nextDisplay)
        loadImages(for: nextDisplay)
        saveViewState()

        debugLog("nextPage: \(currentDisplay) -> currentPage=\(currentPage)", level: .verbose)
    }

    /// 前のページへ
    func previousPage() {
        guard imageSource != nil else { return }

        // 現在の表示状態から前の表示状態を計算
        guard let prevDisplay = calculatePreviousDisplay(
            from: currentDisplay,
            isSinglePage: { self.isPageSingle($0) }
        ) else { return }

        // 表示を更新
        updateCurrentPage(for: prevDisplay)
        loadImages(for: prevDisplay)
        saveViewState()

        debugLog("previousPage: \(currentDisplay) -> currentPage=\(currentPage)", level: .verbose)
    }

    /// 先頭ページへ移動
    func goToFirstPage() {
        guard imageSource != nil else { return }

        // 見開きモードの場合は最初の表示可能なページを探す
        var firstVisiblePage = 0
        if viewMode == .spread {
            while firstVisiblePage < totalPages && pageDisplaySettings.isHidden(firstVisiblePage) {
                firstVisiblePage += 1
            }
            if firstVisiblePage >= totalPages {
                return // 全ページ非表示の場合は何もしない
            }
        }

        currentPage = firstVisiblePage
        loadCurrentPage()
        saveViewState()
    }

    /// 指定ページへ移動（単ページ属性を考慮して正しい表示状態に到達）
    func goToPage(_ page: Int) {
        guard let source = imageSource else { return }
        var targetPage = max(0, min(page, source.imageCount - 1))

        // 見開きモードで非表示ページを指定した場合は次の表示可能なページを探す
        if viewMode == .spread && pageDisplaySettings.isHidden(targetPage) {
            // 前方に表示可能なページを探す
            var nextVisible = targetPage + 1
            while nextVisible < totalPages && pageDisplaySettings.isHidden(nextVisible) {
                nextVisible += 1
            }
            if nextVisible < totalPages {
                targetPage = nextVisible
            } else {
                // 前方にない場合は後方を探す
                var prevVisible = targetPage - 1
                while prevVisible >= 0 && pageDisplaySettings.isHidden(prevVisible) {
                    prevVisible -= 1
                }
                if prevVisible >= 0 {
                    targetPage = prevVisible
                } else {
                    return // 全ページ非表示の場合は何もしない
                }
            }
        }

        // 現在の表示に目標ページが含まれている場合は何もしない
        if currentDisplay.contains(targetPage) {
            return
        }

        let isSinglePage: (Int) -> Bool = { [weak self] p in
            self?.isPageSingle(p) ?? false
        }

        var display = currentDisplay

        if targetPage > currentDisplay.maxIndex {
            // 順方向に進む
            while display.maxIndex < targetPage {
                guard let next = calculateNextDisplay(from: display, isSinglePage: isSinglePage) else {
                    break
                }
                display = next
            }
        } else {
            // 逆方向に戻る
            while display.minIndex > targetPage {
                guard let prev = calculatePreviousDisplay(from: display, isSinglePage: isSinglePage) else {
                    break
                }
                display = prev
            }
        }

        // 表示を更新
        if display != currentDisplay {
            updateCurrentPage(for: display)
            loadImages(for: display)
            saveViewState()
        }
    }

    /// 1ページシフト（見開きのズレ調整用）
    func shiftPage(forward: Bool) {
        guard let source = imageSource else { return }

        // 非表示ページをスキップして次/前の表示可能なページを探す
        var newPage = forward ? currentPage + 1 : currentPage - 1
        if forward {
            while newPage < source.imageCount && pageDisplaySettings.isHidden(newPage) {
                newPage += 1
            }
        } else {
            while newPage >= 0 && pageDisplaySettings.isHidden(newPage) {
                newPage -= 1
            }
        }

        if newPage >= 0 && newPage < source.imageCount {
            currentPage = newPage
            loadCurrentPage()
            saveViewState()
        }
    }

    /// 最終ページへ移動
    func goToLastPage() {
        guard let source = imageSource else { return }
        let lastIndex = source.imageCount - 1

        // 単ページモードの場合は常に最後の画像を表示
        if viewMode == .single {
            currentPage = lastIndex
            loadCurrentPage()
            saveViewState()
            return
        }

        // 見開きモードの場合：最後の表示可能なページを探す
        var lastVisibleIndex = lastIndex
        while lastVisibleIndex >= 0 && pageDisplaySettings.isHidden(lastVisibleIndex) {
            lastVisibleIndex -= 1
        }
        if lastVisibleIndex < 0 {
            return // 全ページ非表示の場合は何もしない
        }

        // 最後の表示可能な画像の横長判定を先に行う
        let lastIsSingle = checkAndSetLandscapeAttribute(for: lastVisibleIndex)

        // 最後の表示可能な画像が単ページ属性つきなら単ページで表示
        if lastIsSingle {
            currentPage = lastVisibleIndex
            loadCurrentPage()
            saveViewState()
            return
        }

        // ペア候補を探す（非表示ページはスキップ）
        var prevVisibleIndex = lastVisibleIndex - 1
        while prevVisibleIndex >= 0 && pageDisplaySettings.isHidden(prevVisibleIndex) {
            prevVisibleIndex -= 1
        }

        // ペアが存在しない、またはペアが単ページ属性の場合は単ページ表示
        if prevVisibleIndex < 0 {
            currentPage = lastVisibleIndex
            loadCurrentPage()
            saveViewState()
            return
        }

        let prevIsSingle = checkAndSetLandscapeAttribute(for: prevVisibleIndex)
        if prevIsSingle {
            currentPage = lastVisibleIndex
            loadCurrentPage()
            saveViewState()
            return
        }

        // 両方見開き可能 → ペアで表示
        currentPage = prevVisibleIndex
        loadCurrentPage()
        saveViewState()
    }

    /// 指定した回数だけページをめくって進む
    func skipForward(pages: Int = 5) {
        guard imageSource != nil else { return }

        let isSinglePage: (Int) -> Bool = { [weak self] page in
            self?.isPageSingle(page) ?? false
        }

        var display = currentDisplay
        for _ in 0..<pages {
            guard let next = calculateNextDisplay(from: display, isSinglePage: isSinglePage) else {
                // 終端に到達
                break
            }
            display = next
        }

        // 表示を更新
        if display != currentDisplay {
            updateCurrentPage(for: display)
            loadImages(for: display)
            saveViewState()
        }
    }

    /// 指定した回数だけページをめくって戻る
    func skipBackward(pages: Int = 5) {
        guard imageSource != nil else { return }

        let isSinglePage: (Int) -> Bool = { [weak self] page in
            self?.isPageSingle(page) ?? false
        }

        var display = currentDisplay
        for _ in 0..<pages {
            guard let prev = calculatePreviousDisplay(from: display, isSinglePage: isSinglePage) else {
                // 先端に到達
                break
            }
            display = prev
        }

        // 表示を更新
        if display != currentDisplay {
            updateCurrentPage(for: display)
            loadImages(for: display)
            saveViewState()
        }
    }

    // MARK: - ナビゲーション計算関数

    /// 順方向ナビゲーション: 次の表示状態を計算
    /// - Parameters:
    ///   - current: 現在の表示状態
    ///   - isSinglePage: 指定ページが単ページ属性かを判定する関数
    /// - Returns: 次の表示状態 (終端の場合はnil)
    private func calculateNextDisplay(
        from current: PageDisplay,
        isSinglePage: (Int) -> Bool
    ) -> PageDisplay? {
        // 単ページモードの場合（非表示設定を無視）
        if viewMode == .single {
            let m = current.maxIndex + 1
            if m >= totalPages {
                return nil
            }
            return .single(m)
        }

        // 見開きモードの場合（非表示ページはスキップ）
        // m = 現在表示の最大Index + 1 (非表示ページはスキップ)
        var m = current.maxIndex + 1
        while m < totalPages && pageDisplaySettings.isHidden(m) {
            m += 1
        }

        // 終端チェック
        if m >= totalPages {
            return nil
        }

        // mが単ページ属性 → [m]
        if isSinglePage(m) {
            return .single(m)
        }

        // m+1を探す（非表示ページはスキップ）
        var m1 = m + 1
        while m1 < totalPages && pageDisplaySettings.isHidden(m1) {
            m1 += 1
        }

        // m+1が存在しない → [m]
        if m1 >= totalPages {
            return .single(m)
        }

        // m+1が単ページ属性 → [m]
        if isSinglePage(m1) {
            return .single(m)
        }

        // 両方とも見開き可能 → [m1|m]
        return .spread(m1, m)
    }

    /// 逆方向ナビゲーション: 前の表示状態を計算
    /// - Parameters:
    ///   - current: 現在の表示状態
    ///   - isSinglePage: 指定ページが単ページ属性かを判定する関数
    /// - Returns: 前の表示状態 (先端の場合はnil)
    private func calculatePreviousDisplay(
        from current: PageDisplay,
        isSinglePage: (Int) -> Bool
    ) -> PageDisplay? {
        // 単ページモードの場合（非表示設定を無視）
        if viewMode == .single {
            let m = current.minIndex - 1
            if m < 0 {
                return nil
            }
            return .single(m)
        }

        // 見開きモードの場合（非表示ページはスキップ）
        // m = 現在表示の最小Index - 1 (非表示ページはスキップ)
        var m = current.minIndex - 1
        while m >= 0 && pageDisplaySettings.isHidden(m) {
            m -= 1
        }

        // 先端チェック
        if m < 0 {
            return nil
        }

        // mが単ページ属性 → [m]
        if isSinglePage(m) {
            return .single(m)
        }

        // m-1を探す（非表示ページはスキップ）
        var m1 = m - 1
        while m1 >= 0 && pageDisplaySettings.isHidden(m1) {
            m1 -= 1
        }

        // m-1が存在しない → [m]
        if m1 < 0 {
            return .single(m)
        }

        // m-1が単ページ属性 → [m]
        if isSinglePage(m1) {
            return .single(m)
        }

        // 両方とも見開き可能 → [m|m-1]
        return .spread(m, m1)
    }

    /// 表示状態に基づいて画像をロード
    private func loadImages(for display: PageDisplay) {
        guard let source = imageSource else { return }

        switch display {
        case .single(let page):
            if viewMode == .single {
                self.currentImage = source.loadImage(at: page)
            } else {
                self.firstPageImage = source.loadImage(at: page)
                self.secondPageImage = nil
            }

        case .spread(let left, let right):
            // RTL: first=right側（小さいindex）, second=left側（大きいindex）
            self.firstPageImage = source.loadImage(at: right)
            self.secondPageImage = source.loadImage(at: left)
        }

        self.errorMessage = nil
    }

    /// 表示状態からcurrentPageを更新
    private func updateCurrentPage(for display: PageDisplay) {
        currentPage = display.minIndex
        currentDisplay = display
    }

    /// ページが単ページ属性かをチェック（統合版）
    private func isPageSingle(_ page: Int) -> Bool {
        return checkAndSetLandscapeAttribute(for: page) ||
               pageDisplaySettings.isForcedSinglePage(page)
    }

    /// 表示モードを切り替え
    func toggleViewMode() {
        let previousMode = viewMode
        viewMode = viewMode == .single ? .spread : .single

        // 単ページモード → 見開きモードに切り替える場合、適切な見開き位置に調整
        if previousMode == .single && viewMode == .spread {
            adjustCurrentPageForSpreadMode()
        }

        loadCurrentPage()

        // 設定を保存
        saveViewState()
    }

    /// 単ページモードから見開きモードに切り替える際の currentPage 調整
    private func adjustCurrentPageForSpreadMode() {
        guard let source = imageSource else { return }

        // currentPage が単ページ属性なら調整不要（単ページ表示される）
        if pageDisplaySettings.isForcedSinglePage(currentPage) {
            return
        }

        // currentPage+1 が存在しない場合は調整不要（単ページ表示される）
        if currentPage + 1 >= source.imageCount {
            return
        }

        // currentPage+1 が単ページ属性の場合、ペアにできない
        if pageDisplaySettings.isForcedSinglePage(currentPage + 1) {
            // currentPage-1 を調べる
            if currentPage > 0 && !pageDisplaySettings.isForcedSinglePage(currentPage - 1) {
                // currentPage-1 が単ページ属性でないなら、1つ前にずらして見開き表示
                currentPage = currentPage - 1
            }
            // currentPage-1 が単ページ属性、または存在しない場合は調整不要（currentPage を単ページ表示）
        }
        // currentPage+1 が単ページ属性でない場合は調整不要（currentPage と currentPage+1 で見開き表示）
    }

    /// 読み方向を切り替え
    func toggleReadingDirection() {
        readingDirection = readingDirection == .rightToLeft ? .leftToRight : .rightToLeft
        // 見開きモードの場合は再読み込み
        if viewMode == .spread {
            loadCurrentPage()
        }
        // 設定を保存
        saveViewState()
    }

    /// ステータスバー表示を切り替え
    func toggleStatusBar() {
        showStatusBar.toggle()
    }

    /// 現在のページの単ページ表示属性を切り替え
    func toggleCurrentPageSingleDisplay() {
        toggleSingleDisplay(at: currentPage)
    }

    /// 指定ページの単ページ表示属性を切り替え
    func toggleSingleDisplay(at pageIndex: Int) {
        pageDisplaySettings.toggleForceSinglePage(at: pageIndex)
        // 設定を保存
        saveViewState()
        // 画像を再読み込み（表示を更新）
        loadCurrentPage()
    }

    /// 現在のページが単ページ表示属性を持つか（ユーザー設定または自動検出）
    var isCurrentPageForcedSingle: Bool {
        return isForcedSingle(at: currentPage)
    }

    /// 現在のページがユーザーによって単ページ表示に設定されているか（自動検出は含まない）
    var isCurrentPageUserForcedSingle: Bool {
        return pageDisplaySettings.isUserForcedSinglePage(currentPage)
    }

    /// 指定ページが単ページ表示属性を持つか（ユーザー設定または自動検出）
    func isForcedSingle(at pageIndex: Int) -> Bool {
        return pageDisplaySettings.isForcedSinglePage(pageIndex)
    }

    // MARK: - 非表示設定

    /// 現在のページの非表示設定を切り替え
    func toggleCurrentPageHidden() {
        toggleHidden(at: currentPage)
    }

    /// 指定ページの非表示設定を切り替え
    func toggleHidden(at pageIndex: Int) {
        pageDisplaySettings.toggleHidden(at: pageIndex)
        saveViewState()
        // 非表示にした場合は表示を再計算
        if pageDisplaySettings.isHidden(pageIndex) && viewMode == .spread {
            // 現在の表示のもう一方のページがあればそこを起点にする
            let otherPage: Int?
            switch currentDisplay {
            case .single(let p):
                otherPage = (p == pageIndex) ? nil : p
            case .spread(let left, let right):
                if left == pageIndex {
                    otherPage = right
                } else if right == pageIndex {
                    otherPage = left
                } else {
                    otherPage = nil
                }
            }

            if let other = otherPage, !pageDisplaySettings.isHidden(other) {
                // 相方が表示可能ならそこを起点に再計算
                currentPage = other
                loadCurrentPage()
            } else {
                // 相方がいないか非表示の場合、次の表示可能なページを探す
                var nextVisiblePage = pageIndex + 1
                while nextVisiblePage < totalPages && pageDisplaySettings.isHidden(nextVisiblePage) {
                    nextVisiblePage += 1
                }
                if nextVisiblePage < totalPages {
                    currentPage = nextVisiblePage
                    loadCurrentPage()
                } else {
                    // 後ろにない場合は前を探す
                    var prevVisiblePage = pageIndex - 1
                    while prevVisiblePage >= 0 && pageDisplaySettings.isHidden(prevVisiblePage) {
                        prevVisiblePage -= 1
                    }
                    if prevVisiblePage >= 0 {
                        currentPage = prevVisiblePage
                        loadCurrentPage()
                    }
                }
            }
        }
    }

    /// 現在のページが非表示かどうか
    var isCurrentPageHidden: Bool {
        return pageDisplaySettings.isHidden(currentPage)
    }

    /// 指定ページが非表示かどうか
    func isHidden(at pageIndex: Int) -> Bool {
        return pageDisplaySettings.isHidden(pageIndex)
    }

    /// 現在のページの配置を取得（デフォルトロジックを含む）
    func getCurrentPageAlignment() -> SinglePageAlignment {
        return getAlignment(at: currentPage)
    }

    /// 指定ページの配置を取得（デフォルトロジックを含む）
    func getAlignment(at pageIndex: Int) -> SinglePageAlignment {
        // 既に設定されている場合はそれを返す
        if let savedAlignment = pageDisplaySettings.alignment(for: pageIndex) {
            return savedAlignment
        }

        // デフォルトロジック:
        // - 横向き画像（実効アスペクト比 >= 1.2）: センタリング
        // - それ以外:
        //   - 右→左表示: 右側
        //   - 左→右表示: 左側
        guard let source = imageSource,
              let size = source.imageSize(at: pageIndex) else {
            return .center
        }

        // 回転を考慮した実効アスペクト比を計算
        let rotation = pageDisplaySettings.rotation(for: pageIndex)
        let effectiveWidth: CGFloat
        let effectiveHeight: CGFloat

        if rotation.swapsAspectRatio {
            // 90度または270度回転の場合、幅と高さを入れ替え
            effectiveWidth = size.height
            effectiveHeight = size.width
        } else {
            effectiveWidth = size.width
            effectiveHeight = size.height
        }

        let aspectRatio = effectiveWidth / effectiveHeight
        if aspectRatio >= landscapeAspectRatioThreshold {
            // 横向き画像（回転後）はセンタリング
            return .center
        } else {
            // 縦向き/正方形画像は読み方向に応じて配置
            switch readingDirection {
            case .rightToLeft:
                return .right
            case .leftToRight:
                return .left
            }
        }
    }

    /// 現在のページの配置を設定
    func setCurrentPageAlignment(_ alignment: SinglePageAlignment) {
        setAlignment(alignment, at: currentPage)
    }

    /// 指定ページの配置を設定
    func setAlignment(_ alignment: SinglePageAlignment, at pageIndex: Int) {
        pageDisplaySettings.setAlignment(alignment, for: pageIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 現在のページの配置（メニュー表示用）
    var currentPageAlignment: SinglePageAlignment {
        return getCurrentPageAlignment()
    }

    // MARK: - 回転設定

    /// 指定ページの回転設定を取得
    func getRotation(at pageIndex: Int) -> ImageRotation {
        return pageDisplaySettings.rotation(for: pageIndex)
    }

    /// 指定ページを時計回りに90度回転
    func rotateClockwise(at pageIndex: Int) {
        pageDisplaySettings.rotateClockwise(at: pageIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 指定ページを反時計回りに90度回転
    func rotateCounterClockwise(at pageIndex: Int) {
        pageDisplaySettings.rotateCounterClockwise(at: pageIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 指定ページを180度回転
    func rotate180(at pageIndex: Int) {
        pageDisplaySettings.rotate180(at: pageIndex)
        saveViewState()
        loadCurrentPage()
    }

    // MARK: - 反転設定

    /// 指定ページの反転設定を取得
    func getFlip(at pageIndex: Int) -> ImageFlip {
        return pageDisplaySettings.flip(for: pageIndex)
    }

    /// 指定ページの水平反転を切り替え
    func toggleHorizontalFlip(at pageIndex: Int) {
        pageDisplaySettings.toggleHorizontalFlip(at: pageIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 指定ページの垂直反転を切り替え
    func toggleVerticalFlip(at pageIndex: Int) {
        pageDisplaySettings.toggleVerticalFlip(at: pageIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 表示状態を保存（モード、ページ番号、読み方向、ページ表示設定）
    private func saveViewState() {
        guard let source = imageSource,
              let fileKey = source.generateFileKey() else {
            return
        }

        // 表示モードを保存
        let modeString = viewMode == .spread ? "spread" : "single"
        UserDefaults.standard.set(modeString, forKey: "\(viewModeKey)-\(fileKey)")

        // 現在のページ番号を保存
        UserDefaults.standard.set(currentPage, forKey: "\(currentPageKey)-\(fileKey)")

        // 読み方向を保存
        let directionString = readingDirection == .rightToLeft ? "rightToLeft" : "leftToRight"
        UserDefaults.standard.set(directionString, forKey: "\(readingDirectionKey)-\(fileKey)")

        // ページ表示設定を保存
        historyManager?.savePageDisplaySettings(pageDisplaySettings, for: fileKey)
    }

    /// 表示状態を復元（モード、ページ番号、読み方向、ページ表示設定）
    private func restoreViewState() {
        guard let source = imageSource,
              let fileKey = source.generateFileKey() else {
            return
        }

        // 表示モードを復元
        if let modeString = UserDefaults.standard.string(forKey: "\(viewModeKey)-\(fileKey)") {
            viewMode = modeString == "spread" ? .spread : .single
        }

        // ページ番号を復元
        let savedPage = UserDefaults.standard.integer(forKey: "\(currentPageKey)-\(fileKey)")
        if savedPage > 0 && savedPage < totalPages {
            currentPage = savedPage
        }

        // 読み方向を復元
        if let directionString = UserDefaults.standard.string(forKey: "\(readingDirectionKey)-\(fileKey)") {
            readingDirection = directionString == "rightToLeft" ? .rightToLeft : .leftToRight
        }

        // ページ表示設定を復元
        if let settings = historyManager?.loadPageDisplaySettings(for: fileKey) {
            pageDisplaySettings = settings
        } else {
            // 設定が存在しない場合は空の設定で初期化
            pageDisplaySettings = PageDisplaySettings()
        }
    }

    /// 単ページ表示属性インジケーター（表示用）
    var singlePageIndicator: String {
        return singlePageIndicator(at: currentPage)
    }

    /// 指定ページの単ページ表示属性インジケーター
    func singlePageIndicator(at pageIndex: Int) -> String {
        if isForcedSingle(at: pageIndex) {
            return L("single_page_indicator")
        }
        return ""
    }

    /// 現在のページ情報（表示用）
    var pageInfo: String {
        guard totalPages > 0 else { return "" }

        switch currentDisplay {
        case .single(let page):
            return "\(page + 1) / \(totalPages)"

        case .spread(let left, let right):
            // 見開き表示: right+1, left+1 の順（右→左読みなら右側が先）
            switch readingDirection {
            case .rightToLeft:
                return "\(right + 1) \(left + 1) / \(totalPages)"
            case .leftToRight:
                return "\(left + 1) \(right + 1) / \(totalPages)"
            }
        }
    }

    /// 現在のファイル名
    var currentFileName: String {
        guard let source = imageSource else { return "" }

        switch currentDisplay {
        case .single(let page):
            return source.fileName(at: page) ?? ""

        case .spread(let left, let right):
            let leftFileName = source.fileName(at: left) ?? ""
            let rightFileName = source.fileName(at: right) ?? ""

            // 画面表示順（左→右）でファイル名を表示
            return "\(leftFileName)  \(rightFileName)"
        }
    }

    /// 2ページ目がユーザー設定の単ページ属性かどうか（見開き表示時のみ有効、自動検出は含まない）
    var isSecondPageUserForcedSingle: Bool {
        guard let source = imageSource else { return false }
        let secondPage = currentPage + 1
        guard secondPage < source.imageCount else { return false }
        return pageDisplaySettings.isUserForcedSinglePage(secondPage)
    }

    // 下位互換のためにarchiveFileNameをsourceNameのエイリアスとして定義
    var archiveFileName: String {
        return sourceName
    }

    /// ウィンドウタイトル
    var windowTitle: String {
        guard let source = imageSource else { return "Panes" }

        // アーカイブ名（zipファイル名 or 画像フォルダの親/フォルダ名）
        let archiveName: String
        if source is ArchiveImageSource {
            // zipファイル: ファイル名のみ
            archiveName = sourceName
        } else {
            // 画像ファイル: 親フォルダ/フォルダ名
            let pathComponents = sourceName.split(separator: "/")
            if pathComponents.count >= 2 {
                // 最後の2要素を取得
                archiveName = pathComponents.suffix(2).joined(separator: "/")
            } else {
                archiveName = sourceName
            }
        }

        switch currentDisplay {
        case .single(let page):
            if viewMode == .single {
                // 単ページモード: ファイル名のみ
                return source.fileName(at: page) ?? "Panes"
            } else {
                // 見開きモード中の単ページ: アーカイブ名 / ファイル名
                let fileName = source.fileName(at: page) ?? ""
                return "\(archiveName) / \(fileName)"
            }

        case .spread(let left, let right):
            // 見開き: アーカイブ名 / ファイル1 - ファイル2
            let leftFileName = source.fileName(at: left) ?? ""
            let rightFileName = source.fileName(at: right) ?? ""
            return "\(archiveName) / \(rightFileName) - \(leftFileName)"
        }
    }

    /// AppSettingsからデフォルト値を適用（ファイルが読み込まれていない場合のみ）
    private func applyDefaultSettings() {
        guard let settings = appSettings else { return }

        // ファイルが読み込まれていない場合のみデフォルト値を適用
        if imageSource == nil {
            viewMode = settings.defaultViewMode
            readingDirection = settings.defaultReadingDirection
            showStatusBar = settings.defaultShowStatusBar
        }

        // 横長判定閾値は常に最新の設定値を使用
        landscapeAspectRatioThreshold = settings.defaultLandscapeThreshold

        // 閾値変更通知のオブザーバーを設定
        setupThresholdChangeObserver()
    }

    /// 閾値変更通知のオブザーバーを設定
    private func setupThresholdChangeObserver() {
        // 既存のタスクをキャンセル
        thresholdChangeTask?.cancel()

        // 新しいオブザーバーを設定（async sequence使用）
        thresholdChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .landscapeThresholdDidChange) {
                guard !Task.isCancelled else { break }
                self?.handleThresholdChange()
            }
        }
    }

    /// 閾値変更時の処理
    private func handleThresholdChange() {
        guard let settings = appSettings else { return }

        // 新しい閾値を適用
        landscapeAspectRatioThreshold = settings.defaultLandscapeThreshold

        // ファイルが開かれている場合のみ自動判定をクリアして再読み込み
        if imageSource != nil {
            debugLog("Threshold changed to \(landscapeAspectRatioThreshold), clearing auto-detection", level: .normal)
            pageDisplaySettings.clearAllAutoDetection()
            loadCurrentPage()
        }
    }

    // MARK: - 画像情報取得

    /// 指定ページの画像情報を取得
    func getImageInfo(at index: Int) -> ImageInfo? {
        guard let source = imageSource,
              index >= 0 && index < source.imageCount else {
            return nil
        }

        let fileName = source.fileName(at: index) ?? "Unknown"
        let size = source.imageSize(at: index) ?? CGSize.zero
        let fileSize = source.fileSize(at: index) ?? 0
        let format = source.imageFormat(at: index) ?? "Unknown"

        return ImageInfo(
            fileName: fileName,
            width: Int(size.width),
            height: Int(size.height),
            fileSize: fileSize,
            format: format,
            pageIndex: index
        )
    }

    /// 指定ページの画像を取得
    func getImage(at index: Int) -> NSImage? {
        return imageSource?.loadImage(at: index)
    }

    /// 指定ページの画像をクリップボードにコピー
    func copyImageToClipboard(at index: Int) {
        guard let image = getImage(at: index) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    /// 現在表示中のページの画像情報を取得
    func getCurrentImageInfos() -> [ImageInfo] {
        var infos: [ImageInfo] = []

        switch currentDisplay {
        case .single(let index):
            if let info = getImageInfo(at: index) {
                infos.append(info)
            }
        case .spread(let left, let right):
            // 右→左表示の場合、右ページ（右側表示）が先、左ページ（左側表示）が後
            if let rightInfo = getImageInfo(at: right) {
                infos.append(rightInfo)
            }
            if let leftInfo = getImageInfo(at: left) {
                infos.append(leftInfo)
            }
        }

        return infos
    }

    // MARK: - ページ表示設定のExport/Import

    /// Export用のデータ構造
    struct PageSettingsExport: Codable {
        let archiveName: String
        let totalPages: Int
        let exportDate: Date
        let settings: PageDisplaySettings
    }

    /// ページ表示設定をExport可能か
    var canExportPageSettings: Bool {
        return imageSource != nil
    }

    /// ページ表示設定をJSONデータとしてExport
    func exportPageSettings() -> Data? {
        guard let source = imageSource else { return nil }

        let exportData = PageSettingsExport(
            archiveName: source.sourceName,
            totalPages: source.imageCount,
            exportDate: Date(),
            settings: pageDisplaySettings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            return try encoder.encode(exportData)
        } catch {
            debugLog("Failed to encode page settings: \(error)", level: .minimal)
            return nil
        }
    }

    /// Export用のデフォルトファイル名
    var exportFileName: String {
        guard let source = imageSource else { return "page_settings.json" }
        let baseName = (source.sourceName as NSString).deletingPathExtension
        return "\(baseName)_page_settings.json"
    }

    /// JSONデータからページ表示設定をImport
    func importPageSettings(from data: Data) -> (success: Bool, message: String) {
        guard imageSource != nil else {
            return (false, L("import_error_no_file"))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let importData = try decoder.decode(PageSettingsExport.self, from: data)

            // 設定を適用
            pageDisplaySettings = importData.settings

            // UserDefaultsにも保存
            saveViewState()

            // 表示を更新
            loadCurrentPage()

            let message = String(format: L("import_success_format"),
                                 importData.archiveName,
                                 importData.settings.userForcedSinglePageIndices.count)
            return (true, message)
        } catch {
            debugLog("Failed to decode page settings: \(error)", level: .minimal)
            return (false, L("import_error_invalid_format"))
        }
    }

    /// ページ表示設定を初期化
    func resetPageSettings() {
        guard imageSource != nil else { return }

        // 設定を初期化
        pageDisplaySettings = PageDisplaySettings()

        // UserDefaultsにも保存
        saveViewState()

        // 表示を更新
        loadCurrentPage()
    }
}
