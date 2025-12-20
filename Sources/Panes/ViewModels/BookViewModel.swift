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

    // 画像キャッシュ（sourceIndexをキーにNSImageを保存）
    private let imageCache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 10  // 最大10枚まで保持
        return cache
    }()

    // プリフェッチ範囲（現在ページ ± prefetchRange）
    private let prefetchRange = 3

    // ページデータ配列（表示順に並んでいる）
    // 例: pages[0].sourceIndex == 2 なら表示0ページ目はソース2番目の画像
    private var pages: [PageData] = []

    // 現在のソート方法
    var sortMethod: ImageSortMethod = .name

    // ソートを逆順にするか
    var isSortReversed: Bool = false

    /// 表示ページ番号からソースインデックスに変換
    private func sourceIndex(for displayPage: Int) -> Int {
        guard displayPage >= 0 && displayPage < pages.count else {
            return displayPage // フォールバック
        }
        // 逆順の場合はインデックスを反転
        let effectivePage = isSortReversed ? (pages.count - 1 - displayPage) : displayPage
        return pages[effectivePage].sourceIndex
    }

    /// ソースインデックスから表示ページ番号に変換
    private func displayPage(for sourceIndex: Int) -> Int? {
        guard let index = pages.firstIndex(where: { $0.sourceIndex == sourceIndex }) else {
            return nil
        }
        // 逆順の場合はインデックスを反転
        return isSortReversed ? (pages.count - 1 - index) : index
    }

    /// ページ配列を初期化（ソートなし = identity mapping）
    private func initializePages(count: Int) {
        pages = (0..<count).map { PageData(sourceIndex: $0) }
        sortMethod = .name  // デフォルトのソート方法にリセット
        isSortReversed = false
        debugLog("Pages initialized: \(pages.count) pages, sortMethod reset to .name", level: .verbose)
    }

    /// ソートを適用して表示順序を更新
    func applySort(_ method: ImageSortMethod) {
        guard let source = imageSource, !pages.isEmpty else { return }

        // 現在表示中の画像のソースインデックスを記憶
        let currentSourceIndex = sourceIndex(for: currentPage)

        // ソート方法に応じて pages を再生成
        sortMethod = method
        let indices = Array(0..<source.imageCount)

        let sortedIndices: [Int]
        switch method {
        case .name:
            // 名前順（localizedStandardCompare）
            sortedIndices = indices.sorted { i1, i2 in
                let name1 = source.fileName(at: i1) ?? ""
                let name2 = source.fileName(at: i2) ?? ""
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }

        case .natural:
            // 自然順（数字を数値として比較）
            sortedIndices = indices.sorted { i1, i2 in
                let name1 = source.fileName(at: i1) ?? ""
                let name2 = source.fileName(at: i2) ?? ""
                return name1.localizedStandardCompare(name2) == .orderedAscending
            }

        case .date:
            // 日付順（古い順）- 事前にキャッシュしてからソート
            let dates = indices.map { source.fileDate(at: $0) ?? Date.distantPast }
            sortedIndices = indices.sorted { i1, i2 in
                dates[i1] < dates[i2]
            }

        case .random:
            // ランダム順
            sortedIndices = indices.shuffled()

        case .custom:
            // カスタム順: 保存された順序があればそれを使用、なければ現在の順序を維持
            if pageDisplaySettings.hasCustomDisplayOrder {
                sortedIndices = pageDisplaySettings.customDisplayOrder
            } else {
                // 現在の表示順序をカスタム順序として保存
                sortedIndices = pages.map { $0.sourceIndex }
                pageDisplaySettings.setCustomDisplayOrder(sortedIndices)
            }
        }

        // ソート結果をpages配列に変換
        pages = sortedIndices.map { PageData(sourceIndex: $0) }

        debugLog("Sort applied: \(method.rawValue), pages: \(pages.prefix(10).map { $0.sourceIndex })...", level: .normal)

        // 元の画像を表示し続けるようにcurrentPageを更新
        if let newDisplayPage = displayPage(for: currentSourceIndex) {
            currentPage = newDisplayPage
        } else {
            currentPage = 0
        }

        // 表示を更新
        loadCurrentPage()
    }

    /// ソートの逆順設定をトグル
    func toggleSortReverse() {
        guard sortMethod.supportsReverse else { return }

        // 現在表示中の画像のソースインデックスを記憶
        let currentSourceIndex = sourceIndex(for: currentPage)

        isSortReversed.toggle()

        // 元の画像を表示し続けるようにcurrentPageを更新
        if let newDisplayPage = displayPage(for: currentSourceIndex) {
            currentPage = newDisplayPage
        }

        debugLog("Sort reverse toggled: \(isSortReversed)", level: .normal)

        // 表示を更新
        loadCurrentPage()
        saveViewState()
    }

    // MARK: - カスタム表示順序の操作

    /// 指定した表示ページを別の表示ページの次（後ろ）に移動
    func movePageAfter(sourceDisplayPage: Int, targetDisplayPage: Int) {
        guard sourceDisplayPage >= 0 && sourceDisplayPage < pages.count else { return }
        guard targetDisplayPage >= 0 && targetDisplayPage < pages.count else { return }
        guard sourceDisplayPage != targetDisplayPage else { return }

        // 対象ページを取り出し
        let targetPage = pages.remove(at: sourceDisplayPage)

        // 挿入位置を計算（removeにより位置がずれる可能性を考慮）
        let insertIndex: Int
        if sourceDisplayPage < targetDisplayPage {
            // 元の位置より後に移動する場合、removeによりtargetDisplayPageは1つ前にずれている
            insertIndex = targetDisplayPage
        } else {
            // 元の位置より前に移動する場合、targetDisplayPageはそのまま
            insertIndex = targetDisplayPage + 1
        }

        pages.insert(targetPage, at: insertIndex)

        // カスタム順序を保存
        updateCustomDisplayOrder()

        // 表示ページを更新（移動先の位置へ）
        currentPage = insertIndex
        loadCurrentPage()
        saveViewState()

        debugLog("Moved page \(sourceDisplayPage) after \(targetDisplayPage) (now at \(insertIndex))", level: .normal)
    }

    /// 指定した表示ページを別の表示ページの前に移動
    func movePageBefore(sourceDisplayPage: Int, targetDisplayPage: Int) {
        guard sourceDisplayPage >= 0 && sourceDisplayPage < pages.count else { return }
        guard targetDisplayPage >= 0 && targetDisplayPage < pages.count else { return }
        guard sourceDisplayPage != targetDisplayPage else { return }

        // 対象ページを取り出し
        let targetPage = pages.remove(at: sourceDisplayPage)

        // 挿入位置を計算（removeにより位置がずれる可能性を考慮）
        let insertIndex: Int
        if sourceDisplayPage < targetDisplayPage {
            // 元の位置より後に移動する場合、removeによりtargetDisplayPageは1つ前にずれている
            insertIndex = targetDisplayPage - 1
        } else {
            // 元の位置より前に移動する場合、targetDisplayPageはそのまま
            insertIndex = targetDisplayPage
        }

        pages.insert(targetPage, at: insertIndex)

        // カスタム順序を保存
        updateCustomDisplayOrder()

        // 表示ページを更新（移動先の位置へ）
        currentPage = insertIndex
        loadCurrentPage()
        saveViewState()

        debugLog("Moved page \(sourceDisplayPage) before \(targetDisplayPage) (now at \(insertIndex))", level: .normal)
    }

    /// pages配列からカスタム表示順序を更新
    private func updateCustomDisplayOrder() {
        pageDisplaySettings.setCustomDisplayOrder(pages.map { $0.sourceIndex })
    }

    /// カスタムソートモードに切り替え（現在の表示順序を保持）
    func ensureCustomSortMode() {
        if sortMethod != .custom {
            // 現在の表示順序をカスタム順序として保存してカスタムモードに切り替え
            pageDisplaySettings.setCustomDisplayOrder(pages.map { $0.sourceIndex })
            sortMethod = .custom
            saveViewState()
        }
    }

    /// カスタム表示順序をリセットして名前順に戻す
    func resetCustomDisplayOrder() {
        // カスタム順序をクリア
        pageDisplaySettings.clearCustomDisplayOrder()

        // 名前順に戻す
        sortMethod = .name
        isSortReversed = false
        applySort(.name)
    }

    // UserDefaultsのキー
    private let viewModeKey = "viewMode"
    private let currentPageKey = "currentPage"
    private let readingDirectionKey = "readingDirection"
    private let sortMethodKey = "sortMethod"
    private let sortReversedKey = "sortReversed"

    // 履歴管理（外部から注入される）
    var historyManager: FileHistoryManager?

    // 画像カタログ管理（外部から注入される）
    var imageCatalogManager: ImageCatalogManager?

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

    // 読み込み中のフェーズ（ローディング画面に表示）
    var loadingPhase: String?

    // 表示モード
    var viewMode: ViewMode = .single

    // フィッティングモード
    var fittingMode: FittingMode = .window

    // ズームレベル（1.0 = 100%、2.0 = 200%）
    var zoomLevel: CGFloat = 1.0

    // ズームの最小・最大値
    private let minZoomLevel: CGFloat = 0.25
    private let maxZoomLevel: CGFloat = 8.0
    private let zoomStep: CGFloat = 1.25  // 25%刻み（乗算）

    // 読み方向
    var readingDirection: ReadingDirection = .rightToLeft

    // ステータスバー表示
    var showStatusBar: Bool = true

    // 現在開いているファイルのパス
    private(set) var currentFilePath: String?

    // MARK: - File Identity Dialog

    /// ファイル同一性確認ダイアログを表示するかどうか
    var showFileIdentityDialog: Bool = false

    /// ファイル同一性確認ダイアログ用の情報
    struct FileIdentityDialogInfo {
        let newFileName: String
        let existingEntry: FileHistoryEntry
        let fileKey: String
        let filePath: String
        let pendingSource: ImageSource
    }

    /// ダイアログに表示する情報（ダイアログ表示中のみ有効）
    var fileIdentityDialogInfo: FileIdentityDialogInfo?

    /// 現在開いているファイルのキー（セッション保存用）
    var currentFileKey: String? {
        imageSource?.generateFileKey()
    }

    /// デバッグ出力（レベル指定）
    private func debugLog(_ message: String, level: DebugLevel = .normal) {
        DebugLogger.log("DEBUG: \(message)", level: level)
    }

    /// 指定されたページが横長かどうかを判定して、必要なら単ページ属性を設定
    /// @param displayPage 表示上のページ番号
    /// @return 判定した結果、単ページ属性を持つかどうか
    private func checkAndSetLandscapeAttribute(for displayPage: Int) -> Bool {
        guard let source = imageSource else { return false }

        let srcIndex = sourceIndex(for: displayPage)

        // ユーザーが手動で設定している場合はそれを優先
        if pageDisplaySettings.isUserForcedSinglePage(srcIndex) {
            return true
        }

        // まだ判定していないページなら判定する（回転を考慮）
        if !pageDisplaySettings.isPageChecked(srcIndex) {
            debugLog("Checking display page \(displayPage) (source: \(srcIndex)) for landscape aspect ratio", level: .verbose)
            if let size = source.imageSize(at: srcIndex) {
                // 回転を考慮した実効アスペクト比を計算
                let rotation = pageDisplaySettings.rotation(for: srcIndex)
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
                debugLog("Display page \(displayPage) (source: \(srcIndex)) size: \(size.width)x\(size.height), rotation: \(rotation.rawValue)°, effective aspect ratio: \(String(format: "%.2f", aspectRatio))", level: .verbose)

                if aspectRatio >= landscapeAspectRatioThreshold {
                    pageDisplaySettings.setAutoDetectedLandscape(srcIndex)
                    debugLog("Display page \(displayPage) (source: \(srcIndex)) auto-detected as landscape", level: .verbose)
                }
            } else {
                debugLog("Failed to get image size for display page \(displayPage) (source: \(srcIndex))", level: .verbose)
            }
            // 判定済みとしてマーク
            pageDisplaySettings.markAsChecked(srcIndex)
        }

        return pageDisplaySettings.isForcedSinglePage(srcIndex)
    }

    /// ファイルを閉じて初期画面に戻る
    func closeFile() {
        // 現在の表示状態を保存
        saveViewState()

        // キャッシュをクリア
        imageCache.removeAllObjects()

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

    /// 現在表示中が書庫/フォルダ内の画像かどうか（個別画像ファイルでない）
    var isViewingArchiveContent: Bool {
        guard let source = imageSource else { return false }
        return !source.isStandaloneImageSource
    }

    /// 現在のファイル（書庫/フォルダ）のメモを取得
    func getCurrentMemo() -> String? {
        guard let fileKey = currentFileKey else { return nil }
        return historyManager?.history.first(where: { $0.fileKey == fileKey })?.memo
    }

    /// 現在のファイル（書庫/フォルダ）のメモを更新
    func updateCurrentMemo(_ memo: String?) {
        guard let fileKey = currentFileKey,
              let entry = historyManager?.history.first(where: { $0.fileKey == fileKey }) else { return }
        historyManager?.updateMemo(for: entry.id, memo: memo)
    }

    /// 現在表示中の画像のメモを取得（ImageCatalogから）
    /// - Parameter pageIndex: 表示ページインデックス（nilなら現在のページ）
    func getCurrentImageMemo(at pageIndex: Int? = nil) -> String? {
        guard let source = imageSource,
              let catalogManager = imageCatalogManager else { return nil }

        let targetPage = pageIndex ?? currentPage
        let srcIndex = sourceIndex(for: targetPage)

        guard let fileKey = source.generateImageFileKey(at: srcIndex) else { return nil }

        // ImageCatalogからエントリを検索
        return catalogManager.catalog.first(where: { $0.fileKey == fileKey })?.memo
    }

    /// 現在表示中の画像のメモを更新（ImageCatalogに保存）
    /// - Parameters:
    ///   - memo: 新しいメモ（nilで削除）
    ///   - pageIndex: 表示ページインデックス（nilなら現在のページ）
    func updateCurrentImageMemo(_ memo: String?, at pageIndex: Int? = nil) {
        guard let source = imageSource,
              let catalogManager = imageCatalogManager else { return }

        let targetPage = pageIndex ?? currentPage
        let srcIndex = sourceIndex(for: targetPage)

        guard let fileKey = source.generateImageFileKey(at: srcIndex) else { return }

        // ImageCatalogからエントリを検索してメモを更新
        if let entry = catalogManager.catalog.first(where: { $0.fileKey == fileKey }) {
            catalogManager.updateMemo(for: entry.id, memo: memo)
        }
    }

    /// 現在表示中の画像がImageCatalogに登録されているか
    /// - Parameter pageIndex: 表示ページインデックス（nilなら現在のページ）
    func hasCurrentImageInCatalog(at pageIndex: Int? = nil) -> Bool {
        guard let source = imageSource,
              let catalogManager = imageCatalogManager else { return false }

        let targetPage = pageIndex ?? currentPage
        let srcIndex = sourceIndex(for: targetPage)

        guard let fileKey = source.generateImageFileKey(at: srcIndex) else { return false }

        return catalogManager.catalog.contains(where: { $0.fileKey == fileKey })
    }

    /// 現在表示中の画像のImageCatalog IDを取得
    /// - Parameter pageIndex: 表示ページインデックス（nilなら現在のページ）
    func getCurrentImageCatalogId(at pageIndex: Int? = nil) -> String? {
        guard let source = imageSource,
              let catalogManager = imageCatalogManager else { return nil }

        let targetPage = pageIndex ?? currentPage
        let srcIndex = sourceIndex(for: targetPage)

        guard let fileKey = source.generateImageFileKey(at: srcIndex) else { return nil }

        return catalogManager.catalog.first(where: { $0.fileKey == fileKey })?.id
    }

    /// 画像ソースを開く（zipまたは画像ファイル）
    /// - Parameters:
    ///   - source: 画像ソース
    ///   - recordToHistory: 書庫履歴に記録するかどうか（デフォルト: true）
    func openSource(_ source: ImageSource, recordToHistory: Bool = true) {
        let openSourceStart = CFAbsoluteTimeGetCurrent()

        guard source.imageCount > 0 else {
            // 暗号化されたアーカイブかどうかをチェック
            if let archiveSource = source as? ArchiveImageSource,
               archiveSource.hasEncryptedEntries {
                errorMessage = L("error_password_protected")
            } else {
                errorMessage = L("error_no_images_found")
            }
            return
        }

        // 個別画像ファイルの場合はファイル同一性チェックをスキップ（書庫履歴に記録しないため）
        if source.isStandaloneImageSource {
            completeOpenSource(source, recordAccess: true)
            return
        }

        // 書庫履歴に記録しない場合はファイル同一性チェックもスキップ
        if !recordToHistory {
            completeOpenSource(source, recordAccess: false)
            return
        }

        // ファイル同一性チェック（書庫/フォルダのみ）
        let fileKeyStart = CFAbsoluteTimeGetCurrent()
        let fileKey = source.generateFileKey()
        let fileKeyTime = (CFAbsoluteTimeGetCurrent() - fileKeyStart) * 1000
        DebugLogger.log("⏱️ openSource: generateFileKey: \(String(format: "%.1f", fileKeyTime))ms", level: .normal)

        if let fileKey = fileKey,
           let url = source.sourceURL,
           let manager = historyManager {
            let checkStart = CFAbsoluteTimeGetCurrent()
            let checkResult = manager.checkFileIdentity(fileKey: fileKey, fileName: source.sourceName)
            let checkTime = (CFAbsoluteTimeGetCurrent() - checkStart) * 1000
            DebugLogger.log("⏱️ openSource: checkFileIdentity: \(String(format: "%.1f", checkTime))ms", level: .normal)

            switch checkResult {
            case .exactMatch, .newFile:
                // 完全一致または新規ファイル: そのまま開く
                completeOpenSource(source, recordAccess: true)

            case .differentName(let existingEntry):
                // ファイル名が異なる: ダイアログを表示
                fileIdentityDialogInfo = FileIdentityDialogInfo(
                    newFileName: source.sourceName,
                    existingEntry: existingEntry,
                    fileKey: fileKey,
                    filePath: url.path,
                    pendingSource: source
                )
                showFileIdentityDialog = true
            }
        } else {
            // 履歴マネージャーがない場合やfileKeyが取得できない場合はそのまま開く
            completeOpenSource(source, recordAccess: false)
        }

        let openSourceTime = (CFAbsoluteTimeGetCurrent() - openSourceStart) * 1000
        DebugLogger.log("⏱️ openSource total: \(String(format: "%.1f", openSourceTime))ms", level: .normal)
    }

    /// ファイル同一性ダイアログでユーザーが選択した後に呼ばれる
    /// - Parameter choice: ユーザーの選択（nil = キャンセル）
    func handleFileIdentityChoice(_ choice: FileIdentityChoice?) {
        // ダイアログを閉じる
        showFileIdentityDialog = false

        guard let info = fileIdentityDialogInfo else { return }

        if let choice = choice {
            // 選択に基づいて履歴を記録
            historyManager?.recordAccessWithChoice(
                fileKey: info.fileKey,
                filePath: info.filePath,
                fileName: info.newFileName,
                existingEntry: info.existingEntry,
                choice: choice
            )

            // 「別のファイルとして扱う」の場合、デフォルト設定を保存してフォールバックを防ぐ
            if choice == .treatAsDifferent {
                let entryId = FileHistoryEntry.generateId(fileName: info.newFileName, fileKey: info.fileKey)
                // デフォルト値でマーカーを保存（restoreViewStateでのフォールバックを防ぐ）
                let defaultMode = appSettings?.defaultViewMode ?? .spread
                let modeString = defaultMode == .spread ? "spread" : "single"
                UserDefaults.standard.set(modeString, forKey: "\(viewModeKey)-\(entryId)")
                UserDefaults.standard.set(0, forKey: "\(currentPageKey)-\(entryId)")
                let defaultDirection = appSettings?.defaultReadingDirection ?? .rightToLeft
                let directionString = defaultDirection == .rightToLeft ? "rightToLeft" : "leftToRight"
                UserDefaults.standard.set(directionString, forKey: "\(readingDirectionKey)-\(entryId)")
            }

            // ソースを開く（履歴は既に記録済み）
            completeOpenSource(info.pendingSource, recordAccess: false)
        }
        // キャンセルの場合は何もしない（ファイルを開かない）

        // 情報をクリア
        fileIdentityDialogInfo = nil
    }

    /// ソースを開く処理の完了（共通部分）
    private func completeOpenSource(_ source: ImageSource, recordAccess: Bool) {
        let totalStart = CFAbsoluteTimeGetCurrent()

        // 前のソースのキャッシュをクリア
        imageCache.removeAllObjects()
        debugLog("🗑️ Image cache cleared for new source", level: .verbose)

        self.imageSource = source
        self.sourceName = source.sourceName
        self.totalPages = source.imageCount
        self.currentPage = 0
        self.errorMessage = nil
        self.currentFilePath = source.sourceURL?.path

        // 表示順序を初期化
        initializePages(count: source.imageCount)

        // 書庫履歴に記録（書庫/フォルダの場合のみ、個別画像ファイルは画像カタログのみに記録）
        let recordStart = CFAbsoluteTimeGetCurrent()
        if recordAccess,
           !source.isStandaloneImageSource,
           let fileKey = source.generateFileKey(),
           let url = source.sourceURL {
            historyManager?.recordAccess(
                fileKey: fileKey,
                filePath: url.path,
                fileName: source.sourceName
            )
        }
        let recordTime = (CFAbsoluteTimeGetCurrent() - recordStart) * 1000
        DebugLogger.log("⏱️ completeOpenSource: recordAccess: \(String(format: "%.1f", recordTime))ms", level: .normal)

        // フェーズ3: 表示状態を復元
        loadingPhase = L("loading_phase_restoring_state")

        // 保存された表示状態を復元
        let restoreStart = CFAbsoluteTimeGetCurrent()
        restoreViewState()
        let restoreTime = (CFAbsoluteTimeGetCurrent() - restoreStart) * 1000
        DebugLogger.log("⏱️ completeOpenSource: restoreViewState: \(String(format: "%.1f", restoreTime))ms", level: .normal)

        // フェーズ4: 画像を読み込む
        loadingPhase = L("loading_phase_loading_image")

        // 画像を読み込む（復元されたページ）
        let loadStart = CFAbsoluteTimeGetCurrent()
        loadCurrentPage()
        let loadTime = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        DebugLogger.log("⏱️ completeOpenSource: loadCurrentPage: \(String(format: "%.1f", loadTime))ms", level: .normal)

        // 読み込み完了
        loadingPhase = nil

        let totalTime = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        DebugLogger.log("⏱️ completeOpenSource total: \(String(format: "%.1f", totalTime))ms", level: .normal)
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
    func openFiles(urls: [URL], recordToHistory: Bool = true) {
        guard !urls.isEmpty else {
            errorMessage = L("error_no_file_selected")
            return
        }

        // バックグラウンドで読み込み、完了後にUI更新
        Task {
            // 進捗報告用コールバック
            let onPhaseChange: @Sendable (String) async -> Void = { [weak self] phase in
                await MainActor.run {
                    self?.loadingPhase = phase
                }
            }

            // エラー報告用コールバック（MainActorで直接errorMessageに設定）
            let onError: @Sendable (String) async -> Void = { [weak self] error in
                await MainActor.run {
                    self?.loadingPhase = nil
                    self?.errorMessage = error
                }
            }

            let source = await Self.loadImageSource(from: urls, onPhaseChange: onPhaseChange, onError: onError)
            if let source = source {
                // フェーズ: ソースを処理
                loadingPhase = L("loading_phase_processing")
                await Task.yield()

                self.openSource(source, recordToHistory: recordToHistory)
            } else {
                loadingPhase = nil
                // エラーコールバックで設定されていない場合のみ汎用エラーを設定
                if self.errorMessage == nil {
                    self.errorMessage = L("error_cannot_open_file")
                }
            }
        }
    }

    /// バックグラウンドでImageSourceを読み込む（進捗報告付き）
    private nonisolated static func loadImageSource(
        from urls: [URL],
        onPhaseChange: (@Sendable (String) async -> Void)? = nil,
        onError: (@Sendable (String) async -> Void)? = nil
    ) async -> ImageSource? {
        // アーカイブファイルの場合
        if urls.count == 1 {
            let ext = urls[0].pathExtension.lowercased()
            if ext == "zip" || ext == "cbz" {
                return await ArchiveImageSource.create(url: urls[0], onPhaseChange: onPhaseChange)
            } else if ext == "rar" || ext == "cbr" {
                return await RarImageSource.create(url: urls[0], onPhaseChange: onPhaseChange)
            } else if ext == "7z" {
                print("📦 BookViewModel: Detected 7z file, calling SevenZipImageSource.create")
                return await SevenZipImageSource.create(url: urls[0], onPhaseChange: onPhaseChange, onError: onError)
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
        while pairPage < totalPages && pageDisplaySettings.isHidden(sourceIndex(for: pairPage)) {
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
            while firstVisiblePage < totalPages && pageDisplaySettings.isHidden(sourceIndex(for: firstVisiblePage)) {
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
    /// @param page 表示上のページ番号
    func goToPage(_ page: Int) {
        guard imageSource != nil else { return }
        var targetPage = max(0, min(page, totalPages - 1))

        // 見開きモードで非表示ページを指定した場合は次の表示可能なページを探す
        if viewMode == .spread && pageDisplaySettings.isHidden(sourceIndex(for: targetPage)) {
            // 前方に表示可能なページを探す
            var nextVisible = targetPage + 1
            while nextVisible < totalPages && pageDisplaySettings.isHidden(sourceIndex(for: nextVisible)) {
                nextVisible += 1
            }
            if nextVisible < totalPages {
                targetPage = nextVisible
            } else {
                // 前方にない場合は後方を探す
                var prevVisible = targetPage - 1
                while prevVisible >= 0 && pageDisplaySettings.isHidden(sourceIndex(for: prevVisible)) {
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

    /// 相対パスでページに移動（画像カタログから開く際に使用）
    func goToPageByRelativePath(_ relativePath: String) {
        guard let source = imageSource else { return }

        // 相対パスに一致するページを探す（ソースインデックスで検索）
        for srcIndex in 0..<source.imageCount {
            if let pageRelativePath = source.imageRelativePath(at: srcIndex),
               pageRelativePath == relativePath {
                // ソースインデックスから表示ページに変換
                if let displayPageNum = displayPage(for: srcIndex) {
                    DebugLogger.log("📖 Found page by relativePath: \(relativePath) -> srcIndex \(srcIndex) -> displayPage \(displayPageNum)", level: .normal)
                    goToPage(displayPageNum)
                    return
                }
            }
        }

        // 完全一致しない場合はファイル名で検索
        let targetFileName = URL(fileURLWithPath: relativePath).lastPathComponent
        for srcIndex in 0..<source.imageCount {
            if let fileName = source.fileName(at: srcIndex),
               fileName == targetFileName {
                // ソースインデックスから表示ページに変換
                if let displayPageNum = displayPage(for: srcIndex) {
                    DebugLogger.log("📖 Found page by fileName: \(targetFileName) -> srcIndex \(srcIndex) -> displayPage \(displayPageNum)", level: .normal)
                    goToPage(displayPageNum)
                    return
                }
            }
        }

        DebugLogger.log("⚠️ Page not found for relativePath: \(relativePath)", level: .normal)
    }

    /// 1ページシフト（見開きのズレ調整用）
    func shiftPage(forward: Bool) {
        guard let source = imageSource else { return }

        // 非表示ページをスキップして次/前の表示可能なページを探す
        var newPage = forward ? currentPage + 1 : currentPage - 1
        if forward {
            while newPage < source.imageCount && pageDisplaySettings.isHidden(sourceIndex(for: newPage)) {
                newPage += 1
            }
        } else {
            while newPage >= 0 && pageDisplaySettings.isHidden(sourceIndex(for: newPage)) {
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

        // 単ページモードの場合は常に最後の画像を表示
        if viewMode == .single {
            currentPage = source.imageCount - 1
            loadCurrentPage()
            saveViewState()
            return
        }

        // 見開きモードの場合：calculateDisplayForLastPageを使用
        let display = calculateDisplayForLastPage()
        currentDisplay = display
        currentPage = display.minIndex
        loadImages(for: display)
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
        while m < totalPages && pageDisplaySettings.isHidden(sourceIndex(for: m)) {
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
        while m1 < totalPages && pageDisplaySettings.isHidden(sourceIndex(for: m1)) {
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
        while m >= 0 && pageDisplaySettings.isHidden(sourceIndex(for: m)) {
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
        while m1 >= 0 && pageDisplaySettings.isHidden(sourceIndex(for: m1)) {
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

    /// キャッシュを使って画像を読み込む（sourceIndexで指定）
    private func loadCachedImage(at sourceIndex: Int) -> NSImage? {
        let key = NSNumber(value: sourceIndex)

        // キャッシュヒット
        if let cached = imageCache.object(forKey: key) {
            debugLog("🎯 Cache hit for sourceIndex \(sourceIndex)", level: .verbose)
            return cached
        }

        // キャッシュミス → ソースから読み込み
        guard let source = imageSource,
              let image = source.loadImage(at: sourceIndex) else {
            return nil
        }

        imageCache.setObject(image, forKey: key)
        debugLog("💾 Cached image for sourceIndex \(sourceIndex)", level: .verbose)
        return image
    }

    /// 指定ページ周辺をプリフェッチ
    private func prefetchImages(around displayPage: Int) {
        guard let source = imageSource else { return }

        // プリフェッチ対象のsourceIndexリストを事前に計算
        var indicesToPrefetch: [Int] = []
        for offset in 1...prefetchRange {
            let forwardPage = displayPage + offset
            if forwardPage < totalPages {
                indicesToPrefetch.append(sourceIndex(for: forwardPage))
            }
            let backwardPage = displayPage - offset
            if backwardPage >= 0 {
                indicesToPrefetch.append(sourceIndex(for: backwardPage))
            }
        }

        // MainActor上で非同期プリフェッチ（UIをブロックしない）
        Task {
            for srcIndex in indicesToPrefetch {
                let key = NSNumber(value: srcIndex)
                // 既にキャッシュにあればスキップ
                if self.imageCache.object(forKey: key) != nil {
                    continue
                }
                // 画像を読み込んでキャッシュに追加
                if let image = source.loadImage(at: srcIndex) {
                    self.imageCache.setObject(image, forKey: key)
                }
                // 他のタスクに実行機会を与える
                await Task.yield()
            }
        }
    }

    /// 表示状態に基づいて画像をロード
    /// displayにはdisplayPage（表示上のページ番号）が含まれる
    private func loadImages(for display: PageDisplay) {
        guard imageSource != nil else { return }

        switch display {
        case .single(let displayPage):
            let srcIndex = sourceIndex(for: displayPage)
            if viewMode == .single {
                self.currentImage = loadCachedImage(at: srcIndex)
            } else {
                self.firstPageImage = loadCachedImage(at: srcIndex)
                self.secondPageImage = nil
            }
            // 画像カタログに記録
            recordImageToCatalog(at: srcIndex)
            // プリフェッチ開始
            prefetchImages(around: displayPage)

        case .spread(let leftDisplay, let rightDisplay):
            // RTL: first=right側（小さいdisplayPage）, second=left側（大きいdisplayPage）
            let rightSrcIndex = sourceIndex(for: rightDisplay)
            let leftSrcIndex = sourceIndex(for: leftDisplay)
            self.firstPageImage = loadCachedImage(at: rightSrcIndex)
            self.secondPageImage = loadCachedImage(at: leftSrcIndex)
            // 画像カタログに記録
            recordImageToCatalog(at: rightSrcIndex)
            recordImageToCatalog(at: leftSrcIndex)
            // プリフェッチ開始（右側ページを基準）
            prefetchImages(around: rightDisplay)
        }

        self.errorMessage = nil
    }

    /// 画像をカタログに記録（すべてのImageSourceに対応）
    private func recordImageToCatalog(at index: Int) {
        guard let source = imageSource,
              let catalogManager = imageCatalogManager else {
            DebugLogger.log("⚠️ recordImageToCatalog skipped: source or catalogManager is nil", level: .normal)
            return
        }
        guard let fileKey = source.generateImageFileKey(at: index) else {
            DebugLogger.log("⚠️ recordImageToCatalog skipped: could not get fileKey for index \(index)", level: .normal)
            return
        }

        let fileName = source.fileName(at: index) ?? "unknown"
        let size = source.imageSize(at: index)
        let fileSize = source.fileSize(at: index)
        let format = source.imageFormat(at: index)

        if source.isStandaloneImageSource {
            // 個別画像ファイルとして記録
            guard let fileSource = source as? FileImageSource,
                  let imageURL = fileSource.imageURL(at: index) else {
                DebugLogger.log("⚠️ recordImageToCatalog skipped: could not get imageURL for standalone", level: .normal)
                return
            }
            catalogManager.recordStandaloneImageAccess(
                fileKey: fileKey,
                filePath: imageURL.path,
                fileName: fileName,
                width: size.map { Int($0.width) },
                height: size.map { Int($0.height) },
                fileSize: fileSize,
                format: format
            )
        } else {
            // 書庫/フォルダ内画像として記録
            guard let parentPath = source.sourceURL?.path,
                  let relativePath = source.imageRelativePath(at: index) else {
                DebugLogger.log("⚠️ recordImageToCatalog skipped: could not get paths for index \(index)", level: .normal)
                return
            }
            catalogManager.recordArchiveContentAccess(
                fileKey: fileKey,
                parentPath: parentPath,
                relativePath: relativePath,
                fileName: fileName,
                width: size.map { Int($0.width) },
                height: size.map { Int($0.height) },
                fileSize: fileSize,
                format: format
            )
        }
    }

    /// 表示状態からcurrentPageを更新
    private func updateCurrentPage(for display: PageDisplay) {
        currentPage = display.minIndex
        currentDisplay = display
    }

    /// ページが単ページ属性かをチェック（統合版）
    /// @param page 表示上のページ番号
    private func isPageSingle(_ page: Int) -> Bool {
        let srcIndex = sourceIndex(for: page)
        return checkAndSetLandscapeAttribute(for: page) ||
               pageDisplaySettings.isForcedSinglePage(srcIndex)
    }

    /// 表示モードを切り替え
    func toggleViewMode() {
        let previousMode = viewMode
        viewMode = viewMode == .single ? .spread : .single

        // 単ページモード → 見開きモードに切り替える場合
        if previousMode == .single && viewMode == .spread {
            // 等倍表示は見開きでは未対応なのでウィンドウフィットに変更
            if fittingMode == .originalSize {
                fittingMode = .window
            }
            // adjustCurrentPageForSpreadModeで正しい表示状態を計算し、画像を読み込む
            adjustCurrentPageForSpreadMode()
            loadImages(for: currentDisplay)
        } else {
            loadCurrentPage()
        }

        // 設定を保存
        saveViewState()
    }

    /// 単ページモードから見開きモードに切り替える際の正しい表示状態を計算
    /// 先頭または終端からページめくりをシミュレートして、currentPageを含む正しい表示状態を求める
    private func adjustCurrentPageForSpreadMode() {
        guard imageSource != nil else { return }

        let targetPage = currentPage
        let pageCount = totalPages  // pages配列の件数 = 表示ページ数

        let isSinglePage: (Int) -> Bool = { [weak self] p in
            self?.isPageSingle(p) ?? false
        }

        // currentPageが先頭寄りか終端寄りかで、より効率的な方向を選択
        if targetPage <= pageCount / 2 {
            // 先頭から順方向にシミュレート
            var display = calculateDisplayForPage(0)
            while !display.contains(targetPage) && display.maxIndex < targetPage {
                guard let next = calculateNextDisplay(from: display, isSinglePage: isSinglePage) else {
                    break
                }
                display = next
            }
            currentDisplay = display
            currentPage = display.minIndex
        } else {
            // 終端から逆方向にシミュレート
            // まず最終ページの表示状態を計算
            var display = calculateDisplayForLastPage()
            while !display.contains(targetPage) && display.minIndex > targetPage {
                guard let prev = calculatePreviousDisplay(from: display, isSinglePage: isSinglePage) else {
                    break
                }
                display = prev
            }
            currentDisplay = display
            currentPage = display.minIndex
        }
    }

    /// 最終ページを起点とした表示状態を計算（逆方向ロジック）
    private func calculateDisplayForLastPage() -> PageDisplay {
        guard imageSource != nil else { return .single(0) }

        let lastIndex = totalPages - 1

        // 最後の表示可能なページを探す（非表示ページはスキップ）
        var lastVisibleIndex = lastIndex
        while lastVisibleIndex >= 0 && pageDisplaySettings.isHidden(sourceIndex(for: lastVisibleIndex)) {
            lastVisibleIndex -= 1
        }
        if lastVisibleIndex < 0 {
            return .single(0)
        }

        // 最後のページが単ページ属性なら単ページ表示
        if isPageSingle(lastVisibleIndex) {
            return .single(lastVisibleIndex)
        }

        // ペア候補を探す（非表示ページはスキップ）
        var prevVisibleIndex = lastVisibleIndex - 1
        while prevVisibleIndex >= 0 && pageDisplaySettings.isHidden(sourceIndex(for: prevVisibleIndex)) {
            prevVisibleIndex -= 1
        }

        // ペアが存在しない場合は単ページ表示
        if prevVisibleIndex < 0 {
            return .single(lastVisibleIndex)
        }

        // ペアが単ページ属性の場合は単ページ表示
        if isPageSingle(prevVisibleIndex) {
            return .single(lastVisibleIndex)
        }

        // 両方見開き可能 → ペアで表示
        return .spread(lastVisibleIndex, prevVisibleIndex)
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

    // MARK: - ズーム操作

    /// ズームイン
    func zoomIn() {
        let newZoom = zoomLevel * zoomStep
        zoomLevel = min(newZoom, maxZoomLevel)
    }

    /// ズームアウト
    func zoomOut() {
        let newZoom = zoomLevel / zoomStep
        zoomLevel = max(newZoom, minZoomLevel)
    }

    /// ズームをリセット（100%に戻す）
    func resetZoom() {
        zoomLevel = 1.0
    }

    /// ズームレベルを設定（範囲制限付き）
    func setZoom(_ level: CGFloat) {
        zoomLevel = max(minZoomLevel, min(level, maxZoomLevel))
    }

    /// ズームレベルのパーセント表示
    var zoomPercentage: Int {
        return Int(zoomLevel * 100)
    }

    /// 現在のページの単ページ表示属性を切り替え
    func toggleCurrentPageSingleDisplay() {
        toggleSingleDisplay(at: currentPage)
    }

    /// 指定ページの単ページ表示属性を切り替え
    /// @param pageIndex 表示上のページ番号
    func toggleSingleDisplay(at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        pageDisplaySettings.toggleForceSinglePage(at: srcIndex)
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
        let srcIndex = sourceIndex(for: currentPage)
        return pageDisplaySettings.isUserForcedSinglePage(srcIndex)
    }

    /// 指定ページが単ページ表示属性を持つか（ユーザー設定または自動検出）
    /// @param pageIndex 表示上のページ番号
    func isForcedSingle(at pageIndex: Int) -> Bool {
        let srcIndex = sourceIndex(for: pageIndex)
        return pageDisplaySettings.isForcedSinglePage(srcIndex)
    }

    // MARK: - 非表示設定

    /// 現在のページの非表示設定を切り替え
    func toggleCurrentPageHidden() {
        toggleHidden(at: currentPage)
    }

    /// 指定ページの非表示設定を切り替え
    /// @param pageIndex 表示上のページ番号
    func toggleHidden(at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        pageDisplaySettings.toggleHidden(at: srcIndex)
        saveViewState()
        // 非表示にした場合は表示を再計算
        if pageDisplaySettings.isHidden(srcIndex) && viewMode == .spread {
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

            if let other = otherPage, !pageDisplaySettings.isHidden(sourceIndex(for: other)) {
                // 相方が表示可能ならそこを起点に再計算
                currentPage = other
                loadCurrentPage()
            } else {
                // 相方がいないか非表示の場合、次の表示可能なページを探す
                var nextVisiblePage = pageIndex + 1
                while nextVisiblePage < totalPages && pageDisplaySettings.isHidden(sourceIndex(for: nextVisiblePage)) {
                    nextVisiblePage += 1
                }
                if nextVisiblePage < totalPages {
                    currentPage = nextVisiblePage
                    loadCurrentPage()
                } else {
                    // 後ろにない場合は前を探す
                    var prevVisiblePage = pageIndex - 1
                    while prevVisiblePage >= 0 && pageDisplaySettings.isHidden(sourceIndex(for: prevVisiblePage)) {
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
        let srcIndex = sourceIndex(for: currentPage)
        return pageDisplaySettings.isHidden(srcIndex)
    }

    /// 指定ページが非表示かどうか
    /// @param pageIndex 表示上のページ番号
    func isHidden(at pageIndex: Int) -> Bool {
        let srcIndex = sourceIndex(for: pageIndex)
        return pageDisplaySettings.isHidden(srcIndex)
    }

    /// 現在のページの配置を取得（デフォルトロジックを含む）
    func getCurrentPageAlignment() -> SinglePageAlignment {
        return getAlignment(at: currentPage)
    }

    /// 指定ページの配置を取得（デフォルトロジックを含む）
    /// @param pageIndex 表示上のページ番号
    func getAlignment(at pageIndex: Int) -> SinglePageAlignment {
        let srcIndex = sourceIndex(for: pageIndex)

        // 既に設定されている場合はそれを返す
        if let savedAlignment = pageDisplaySettings.alignment(for: srcIndex) {
            return savedAlignment
        }

        // デフォルトロジック:
        // - 横向き画像（実効アスペクト比 >= 1.2）: センタリング
        // - それ以外:
        //   - 右→左表示: 右側
        //   - 左→右表示: 左側
        guard let source = imageSource,
              let size = source.imageSize(at: srcIndex) else {
            return .center
        }

        // 回転を考慮した実効アスペクト比を計算
        let rotation = pageDisplaySettings.rotation(for: srcIndex)
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
    /// 配置を設定すると自動的に単ページ表示属性も付与される
    /// @param pageIndex 表示上のページ番号
    func setAlignment(_ alignment: SinglePageAlignment, at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        // 単ページ表示属性がなければ自動的に付与
        if !pageDisplaySettings.isForcedSinglePage(srcIndex) {
            pageDisplaySettings.setForceSinglePage(at: srcIndex, forced: true)
        }
        pageDisplaySettings.setAlignment(alignment, for: srcIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 現在のページの配置（メニュー表示用）
    var currentPageAlignment: SinglePageAlignment {
        return getCurrentPageAlignment()
    }

    // MARK: - 回転設定

    /// 指定ページの回転設定を取得
    /// @param pageIndex 表示上のページ番号
    func getRotation(at pageIndex: Int) -> ImageRotation {
        let srcIndex = sourceIndex(for: pageIndex)
        return pageDisplaySettings.rotation(for: srcIndex)
    }

    /// 指定ページを時計回りに90度回転
    /// @param pageIndex 表示上のページ番号
    func rotateClockwise(at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        pageDisplaySettings.rotateClockwise(at: srcIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 指定ページを反時計回りに90度回転
    /// @param pageIndex 表示上のページ番号
    func rotateCounterClockwise(at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        pageDisplaySettings.rotateCounterClockwise(at: srcIndex)
        saveViewState()
        loadCurrentPage()
    }

    /// 指定ページを180度回転
    /// @param pageIndex 表示上のページ番号
    func rotate180(at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        pageDisplaySettings.rotate180(at: srcIndex)
        saveViewState()
        loadCurrentPage()
    }

    // MARK: - 反転設定

    /// 指定ページの反転設定を取得
    /// @param pageIndex 表示上のページ番号
    func getFlip(at pageIndex: Int) -> ImageFlip {
        let srcIndex = sourceIndex(for: pageIndex)
        return pageDisplaySettings.flip(for: srcIndex)
    }

    /// 指定ページの水平反転を切り替え
    /// @param pageIndex 表示上のページ番号
    /// ±90°回転時は垂直反転として操作（画面表示に対する反転として動作させるため）
    func toggleHorizontalFlip(at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        let rotation = pageDisplaySettings.rotation(for: srcIndex)
        if rotation.swapsAspectRatio {
            // ±90°回転時は左右反転の操作を上下反転として適用
            pageDisplaySettings.toggleVerticalFlip(at: srcIndex)
        } else {
            pageDisplaySettings.toggleHorizontalFlip(at: srcIndex)
        }
        saveViewState()
        loadCurrentPage()
    }

    /// 指定ページの垂直反転を切り替え
    /// @param pageIndex 表示上のページ番号
    /// ±90°回転時は水平反転として操作（画面表示に対する反転として動作させるため）
    func toggleVerticalFlip(at pageIndex: Int) {
        let srcIndex = sourceIndex(for: pageIndex)
        let rotation = pageDisplaySettings.rotation(for: srcIndex)
        if rotation.swapsAspectRatio {
            // ±90°回転時は上下反転の操作を左右反転として適用
            pageDisplaySettings.toggleHorizontalFlip(at: srcIndex)
        } else {
            pageDisplaySettings.toggleVerticalFlip(at: srcIndex)
        }
        saveViewState()
        loadCurrentPage()
    }

    /// 表示状態を保存（モード、ページ番号、読み方向、ページ表示設定）
    private func saveViewState() {
        guard let source = imageSource,
              let fileKey = source.generateFileKey() else {
            debugLog("💾 saveViewState: SKIPPED - no source or fileKey", level: .normal)
            return
        }

        debugLog("💾 saveViewState: \(source.sourceName), fileKey=\(fileKey.prefix(20))...", level: .normal)

        // エントリIDを取得（contentKey互換性のため、実際のエントリを検索）
        let entryId: String
        if let entry = historyManager?.findEntry(fileName: source.sourceName, fileKey: fileKey) {
            entryId = entry.id
            debugLog("💾 saveViewState: found existing entry id=\(entryId)", level: .verbose)
        } else {
            entryId = FileHistoryEntry.generateId(fileName: source.sourceName, fileKey: fileKey)
            debugLog("💾 saveViewState: generated new entry id=\(entryId)", level: .verbose)
        }

        // 表示モードを保存（エントリIDベース）
        let modeString = viewMode == .spread ? "spread" : "single"
        UserDefaults.standard.set(modeString, forKey: "\(viewModeKey)-\(entryId)")

        // 現在のページ番号を保存（ソースインデックスで保存、エントリIDベース）
        let currentSourceIndex = sourceIndex(for: currentPage)
        UserDefaults.standard.set(currentSourceIndex, forKey: "\(currentPageKey)-\(entryId)")

        // 読み方向を保存（エントリIDベース）
        let directionString = readingDirection == .rightToLeft ? "rightToLeft" : "leftToRight"
        UserDefaults.standard.set(directionString, forKey: "\(readingDirectionKey)-\(entryId)")

        // ソート方法を保存（エントリIDベース）
        UserDefaults.standard.set(sortMethod.rawValue, forKey: "\(sortMethodKey)-\(entryId)")
        UserDefaults.standard.set(isSortReversed, forKey: "\(sortReversedKey)-\(entryId)")

        // ページ表示設定を保存（ファイル名も考慮してエントリを特定）
        historyManager?.savePageDisplaySettings(pageDisplaySettings, forFileName: source.sourceName, fileKey: fileKey)
    }

    /// 表示状態を復元（モード、ページ番号、読み方向、ページ表示設定）
    private func restoreViewState() {
        guard let source = imageSource,
              let fileKey = source.generateFileKey() else {
            debugLog("📂 restoreViewState: SKIPPED - no source or fileKey", level: .normal)
            return
        }

        debugLog("📂 restoreViewState: \(source.sourceName), fileKey=\(fileKey.prefix(20))...", level: .normal)

        // エントリIDを取得（contentKey互換性のため、実際のエントリを検索）
        // 旧フォーマットのfileKeyで保存されたエントリにも対応
        let entryId: String
        if let entry = historyManager?.findEntry(fileName: source.sourceName, fileKey: fileKey) {
            entryId = entry.id
            debugLog("📂 restoreViewState: found existing entry id=\(entryId)", level: .verbose)
        } else {
            // エントリが見つからない場合は新規生成
            entryId = FileHistoryEntry.generateId(fileName: source.sourceName, fileKey: fileKey)
            debugLog("📂 restoreViewState: generated new entry id=\(entryId)", level: .verbose)
        }

        // ページ表示設定を復元（カスタムソート順序もここに含まれるため、ソート復元より先に行う）
        if let settings = historyManager?.loadPageDisplaySettings(forFileName: source.sourceName, fileKey: fileKey) {
            pageDisplaySettings = settings
            debugLog("📂 restoreViewState: loaded page settings - singlePages=\(settings.userForcedSinglePageIndices.count), hidden=\(settings.hiddenPageIndices.count)", level: .normal)
        } else {
            // 設定が存在しない場合は空の設定で初期化
            pageDisplaySettings = PageDisplaySettings()
            debugLog("📂 restoreViewState: no page settings found, using defaults", level: .normal)
        }

        // 表示モードを復元（エントリIDベースのみ）
        if let modeString = UserDefaults.standard.string(forKey: "\(viewModeKey)-\(entryId)") {
            viewMode = modeString == "spread" ? .spread : .single
        }
        // なければデフォルトのまま

        // 読み方向を復元（エントリIDベースのみ）
        if let directionString = UserDefaults.standard.string(forKey: "\(readingDirectionKey)-\(entryId)") {
            readingDirection = directionString == "rightToLeft" ? .rightToLeft : .leftToRight
        }
        // なければデフォルトのまま

        // ソート方法を復元（pages配列を先に更新する必要があるため、ページ復元より先に行う）
        if let sortString = UserDefaults.standard.string(forKey: "\(sortMethodKey)-\(entryId)") {
            // 旧形式からの互換性対応（nameReverse, dateAscending, dateDescending）
            let (restoredMethod, restoredReversed) = ImageSortMethod.fromLegacy(sortString)
            sortMethod = restoredMethod

            // 逆順設定を復元（新形式で保存されていればそちらを優先）
            if UserDefaults.standard.object(forKey: "\(sortReversedKey)-\(entryId)") != nil {
                isSortReversed = UserDefaults.standard.bool(forKey: "\(sortReversedKey)-\(entryId)")
            } else {
                isSortReversed = restoredReversed
            }

            // ソートを適用（pages配列を更新、ただしページ読み込みはスキップ）
            let indices = Array(0..<totalPages)
            let sortedIndices: [Int]
            switch restoredMethod {
            case .name:
                sortedIndices = indices.sorted { i1, i2 in
                    let name1 = imageSource?.fileName(at: i1) ?? ""
                    let name2 = imageSource?.fileName(at: i2) ?? ""
                    return name1.localizedStandardCompare(name2) == .orderedAscending
                }
            case .natural:
                sortedIndices = indices.sorted { i1, i2 in
                    let name1 = imageSource?.fileName(at: i1) ?? ""
                    let name2 = imageSource?.fileName(at: i2) ?? ""
                    return name1.localizedStandardCompare(name2) == .orderedAscending
                }
            case .date:
                // 事前にキャッシュしてからソート
                let dates = indices.map { imageSource?.fileDate(at: $0) ?? Date.distantPast }
                sortedIndices = indices.sorted { i1, i2 in
                    dates[i1] < dates[i2]
                }
            case .random:
                sortedIndices = indices.shuffled()
            case .custom:
                // カスタム順: 保存された順序を使用
                if pageDisplaySettings.hasCustomDisplayOrder {
                    sortedIndices = pageDisplaySettings.customDisplayOrder
                } else {
                    // 保存順序がない場合は現在のまま（name順）
                    sortedIndices = indices.sorted { i1, i2 in
                        let name1 = imageSource?.fileName(at: i1) ?? ""
                        let name2 = imageSource?.fileName(at: i2) ?? ""
                        return name1.localizedStandardCompare(name2) == .orderedAscending
                    }
                }
            }
            pages = sortedIndices.map { PageData(sourceIndex: $0) }
        }
        // なければデフォルト（.name）のまま

        // ページ番号を復元（ソースインデックスとして保存されている、エントリIDベースのみ）
        let savedSourceIndex = UserDefaults.standard.integer(forKey: "\(currentPageKey)-\(entryId)")
        if savedSourceIndex > 0 && savedSourceIndex < totalPages {
            // ソースインデックスを表示ページに変換
            if let restoredDisplayPage = displayPage(for: savedSourceIndex) {
                currentPage = restoredDisplayPage
            } else {
                currentPage = savedSourceIndex  // フォールバック
            }
        }
        // なければ0（先頭）のまま
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
            return source.fileName(at: sourceIndex(for: page)) ?? ""

        case .spread(let left, let right):
            let leftFileName = source.fileName(at: sourceIndex(for: left)) ?? ""
            let rightFileName = source.fileName(at: sourceIndex(for: right)) ?? ""

            // 画面表示順（左→右）でファイル名を表示
            return "\(leftFileName)  \(rightFileName)"
        }
    }

    /// 2ページ目がユーザー設定の単ページ属性かどうか（見開き表示時のみ有効、自動検出は含まない）
    var isSecondPageUserForcedSingle: Bool {
        guard imageSource != nil else { return false }
        let secondPage = currentPage + 1
        guard secondPage < totalPages else { return false }
        let srcIndex = sourceIndex(for: secondPage)
        return pageDisplaySettings.isUserForcedSinglePage(srcIndex)
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
                return source.fileName(at: sourceIndex(for: page)) ?? "Panes"
            } else {
                // 見開きモード中の単ページ: アーカイブ名 / ファイル名
                let fileName = source.fileName(at: sourceIndex(for: page)) ?? ""
                return "\(archiveName) / \(fileName)"
            }

        case .spread(let left, let right):
            // 見開き: アーカイブ名 / ファイル1 - ファイル2
            let leftFileName = source.fileName(at: sourceIndex(for: left)) ?? ""
            let rightFileName = source.fileName(at: sourceIndex(for: right)) ?? ""
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
    /// @param displayPage 表示上のページ番号
    func getImageInfo(at displayPage: Int) -> ImageInfo? {
        guard let source = imageSource,
              displayPage >= 0 && displayPage < totalPages else {
            return nil
        }

        let srcIndex = sourceIndex(for: displayPage)
        let fileName = source.fileName(at: srcIndex) ?? "Unknown"
        let size = source.imageSize(at: srcIndex) ?? CGSize.zero
        let fileSize = source.fileSize(at: srcIndex) ?? 0
        let format = source.imageFormat(at: srcIndex) ?? "Unknown"

        return ImageInfo(
            fileName: fileName,
            width: Int(size.width),
            height: Int(size.height),
            fileSize: fileSize,
            format: format,
            pageIndex: displayPage
        )
    }

    /// 指定ページの画像を取得
    /// @param displayPage 表示上のページ番号
    func getImage(at displayPage: Int) -> NSImage? {
        return imageSource?.loadImage(at: sourceIndex(for: displayPage))
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
            totalPages: totalPages,
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
