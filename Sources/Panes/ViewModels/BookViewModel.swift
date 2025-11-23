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

/// デバッグレベル
enum DebugLevel: Int {
    case off = 0      // デバッグ出力なし
    case minimal = 1  // 最小限（エラーのみ）
    case normal = 2   // 通常（主要な処理）
    case verbose = 3  // 詳細（すべて）
}

/// 書籍（画像アーカイブ）の表示状態を管理するViewModel
@Observable
class BookViewModel {
    // デバッグレベル（環境変数 DEBUG_LEVEL で設定可能、デフォルトは off）
    private static let debugLevel: DebugLevel = {
        if let levelStr = ProcessInfo.processInfo.environment["DEBUG_LEVEL"],
           let levelInt = Int(levelStr),
           let level = DebugLevel(rawValue: levelInt) {
            return level
        }
        return .off
    }()

    // 横長画像判定のアスペクト比閾値（幅/高さ）
    // TODO: 後でアプリ設定で変更可能にする
    private let landscapeAspectRatioThreshold: CGFloat = 1.2

    // 画像ソース
    private var imageSource: ImageSource?

    // UserDefaultsのキー
    private let viewModeKey = "viewMode"
    private let currentPageKey = "currentPage"
    private let readingDirectionKey = "readingDirection"
    private let pageDisplaySettingsKey = "pageDisplaySettings"

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

    // 総ページ数
    var totalPages: Int = 0

    // ソース名（ファイル名など）
    var sourceName: String = ""

    // エラーメッセージ
    var errorMessage: String?

    // 表示モード
    var viewMode: ViewMode = .single

    // 読み方向
    var readingDirection: ReadingDirection = .rightToLeft

    /// デバッグ出力（レベル指定）
    private func debugLog(_ message: String, level: DebugLevel = .normal) {
        guard Self.debugLevel.rawValue >= level.rawValue else { return }
        print("DEBUG: \(message)")
    }

    /// 指定されたページが横長かどうかを判定して、必要なら単ページ属性を設定
    /// @return 判定した結果、単ページ属性を持つかどうか
    private func checkAndSetLandscapeAttribute(for index: Int) -> Bool {
        guard let source = imageSource else { return false }

        // 既に手動で設定されている場合はそのまま
        if pageDisplaySettings.isForcedSinglePage(index) {
            return true
        }

        // まだ判定していないページなら判定する
        if !pageDisplaySettings.isPageChecked(index) {
            debugLog("Checking page \(index) for landscape aspect ratio", level: .verbose)
            if let size = source.imageSize(at: index) {
                let aspectRatio = size.width / size.height
                debugLog("Page \(index) size: \(size.width)x\(size.height), aspect ratio: \(String(format: "%.2f", aspectRatio))", level: .verbose)

                if aspectRatio >= landscapeAspectRatioThreshold {
                    pageDisplaySettings.forceSinglePageIndices.insert(index)
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

    /// 画像ソースを開く（zipまたは画像ファイル）
    func openSource(_ source: ImageSource) {
        guard source.imageCount > 0 else {
            errorMessage = "画像が見つかりませんでした"
            return
        }

        self.imageSource = source
        self.sourceName = source.sourceName
        self.totalPages = source.imageCount
        self.currentPage = 0
        self.errorMessage = nil

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
            errorMessage = "zipファイルを開けませんでした"
        }
    }

    /// 画像ファイル（単一・複数）を開く
    func openImageFiles(urls: [URL]) {
        if let source = FileImageSource(urls: urls) {
            openSource(source)
        } else {
            errorMessage = "画像ファイルを開けませんでした"
        }
    }

    /// URLから適切なソースを自動判定して開く
    func openFiles(urls: [URL]) {
        guard !urls.isEmpty else {
            errorMessage = "ファイルが選択されていません"
            return
        }

        // zipファイルの場合
        if urls.count == 1 && urls[0].pathExtension.lowercased() == "zip" {
            openArchive(url: urls[0])
        } else {
            // 画像ファイルの場合
            openImageFiles(urls: urls)
        }
    }

    /// 現在のページの画像を読み込む
    private func loadCurrentPage() {
        guard imageSource != nil else {
            debugLog("loadCurrentPage - imageSource is nil", level: .minimal)
            return
        }

        debugLog("loadCurrentPage - viewMode: \(viewMode), currentPage: \(currentPage)", level: .verbose)

        switch viewMode {
        case .single:
            loadSinglePage()
        case .spread:
            // 見開きモードでも単ページ表示すべきか判定
            let shouldShowSinglePage = shouldShowCurrentPageAsSingle()
            debugLog("shouldShowCurrentPageAsSingle: \(shouldShowSinglePage)", level: .verbose)

            if shouldShowSinglePage {
                loadSinglePage()
            } else {
                loadSpreadPages()
            }
        }
    }

    /// 見開きモードで現在のページを単独表示すべきか判定
    private func shouldShowCurrentPageAsSingle() -> Bool {
        guard let source = imageSource else { return false }

        // currentPage のアスペクト比を判定（未判定なら自動判定）
        let currentIsSingle = checkAndSetLandscapeAttribute(for: currentPage)
        if currentIsSingle {
            return true
        }

        // 次のページ（currentPage+1）も判定
        // 見開きで表示する予定のページが横長なら、currentPageも単ページ表示にする
        if currentPage + 1 < source.imageCount {
            let nextIsSingle = checkAndSetLandscapeAttribute(for: currentPage + 1)
            if nextIsSingle {
                return true
            }
        }

        return false
    }

    /// 単ページモードの画像読み込み
    private func loadSinglePage() {
        guard let source = imageSource else { return }

        if let image = source.loadImage(at: currentPage) {
            if viewMode == .single {
                // 単ページモードの場合
                self.currentImage = image
            } else {
                // 見開きモード中の単ページ表示の場合
                self.firstPageImage = image
                self.secondPageImage = nil
            }
            self.errorMessage = nil
        } else {
            let fileName = source.fileName(at: currentPage) ?? "不明"
            self.errorMessage = "画像の読み込みに失敗しました\nファイル: \(fileName)\nページ: \(currentPage + 1)/\(totalPages)"
            debugLog("Failed to load image at index \(currentPage), file: \(fileName)", level: .minimal)
        }
    }

    /// 見開きモードの画像読み込み
    private func loadSpreadPages() {
        switch readingDirection {
        case .rightToLeft:
            loadSpreadPages_RightToLeft()
        case .leftToRight:
            loadSpreadPages_LeftToRight()
        }
    }

    /// 見開きモードの画像読み込み（右→左読み：漫画）
    private func loadSpreadPages_RightToLeft() {
        guard let source = imageSource else { return }

        // シフト判定: currentPageまでの単ページ属性の累積が奇数か
        let isOddShift = pageDisplaySettings.hasOddSinglePagesUpTo(currentPage)

        if isOddShift {
            // シフトあり: currentPage が右側、currentPage+1 が左側
            self.firstPageImage = source.loadImage(at: currentPage)
            if currentPage + 1 < source.imageCount {
                self.secondPageImage = source.loadImage(at: currentPage + 1)
            } else {
                self.secondPageImage = nil
            }
        } else {
            // シフトなし: currentPage が右側、currentPage+1 が左側
            self.firstPageImage = source.loadImage(at: currentPage)
            if currentPage + 1 < source.imageCount {
                self.secondPageImage = source.loadImage(at: currentPage + 1)
            } else {
                self.secondPageImage = nil
            }
        }

        self.errorMessage = nil
    }

    /// 見開きモードの画像読み込み（左→右読み：洋書）
    private func loadSpreadPages_LeftToRight() {
        guard let source = imageSource else { return }

        // 左→右モード: currentPage が常に左側、currentPage+1 が右側
        // (単ページ属性があれば shouldShowCurrentPageAsSingle で判定済み)
        self.firstPageImage = source.loadImage(at: currentPage)
        if currentPage + 1 < source.imageCount {
            self.secondPageImage = source.loadImage(at: currentPage + 1)
        } else {
            self.secondPageImage = nil
        }

        self.errorMessage = nil
    }

    /// 次のページへ
    func nextPage() {
        guard let source = imageSource else { return }

        // ページめくりのステップ数を計算
        let step = calculateNextPageStep()
        let newPage = currentPage + step

        if newPage < source.imageCount {
            currentPage = newPage
            loadCurrentPage()
            saveViewState()
        }
    }

    /// 前のページへ
    func previousPage() {
        // ページめくりのステップ数を計算
        let step = calculatePreviousPageStep()
        let newPage = currentPage - step

        if newPage >= 0 {
            currentPage = newPage
            loadCurrentPage()
            saveViewState()
        }
    }

    /// 先頭ページへ移動
    func goToFirstPage() {
        guard imageSource != nil else { return }
        currentPage = 0
        loadCurrentPage()
        saveViewState()
    }

    /// 最終ページへ移動
    func goToLastPage() {
        guard let source = imageSource else { return }
        currentPage = source.imageCount - 1
        loadCurrentPage()
        saveViewState()
    }

    /// 次のページへのステップ数を計算
    private func calculateNextPageStep() -> Int {
        if viewMode == .single {
            return 1
        }

        // 見開きモードの場合
        // 現在のページが単ページ表示なら1ページ進む
        if shouldShowCurrentPageAsSingle() {
            return 1
        }

        // 見開き表示なら2ページ進む
        return 2
    }

    /// 前のページへのステップ数を計算
    private func calculatePreviousPageStep() -> Int {
        if viewMode == .single {
            return 1
        }

        // 見開きモードの場合
        // 1ページ戻った位置が単ページ表示なら1ページ戻る
        if currentPage > 0 {
            let prevPage = currentPage - 1
            if pageDisplaySettings.isForcedSinglePage(prevPage) {
                return 1
            }
        }

        // 見開き表示なら2ページ戻る
        return 2
    }

    /// 表示モードを切り替え
    func toggleViewMode() {
        viewMode = viewMode == .single ? .spread : .single
        // モード切り替え時は偶数ページに調整（見開きの最初のページ）
        if viewMode == .spread && currentPage % 2 != 0 {
            currentPage = max(0, currentPage - 1)
        }
        loadCurrentPage()

        // 設定を保存
        saveViewState()
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

    /// 現在のページの単ページ表示属性を切り替え
    func toggleCurrentPageSingleDisplay() {
        pageDisplaySettings.toggleForceSinglePage(at: currentPage)
        // 設定を保存
        saveViewState()
        // 画像を再読み込み（表示を更新）
        loadCurrentPage()
    }

    /// 現在のページが単ページ表示属性を持つか
    var isCurrentPageForcedSingle: Bool {
        return pageDisplaySettings.isForcedSinglePage(currentPage)
    }

    /// 現在のページの配置を取得（デフォルトロジックを含む）
    func getCurrentPageAlignment() -> SinglePageAlignment {
        // 既に設定されている場合はそれを返す
        if let savedAlignment = pageDisplaySettings.alignment(for: currentPage) {
            return savedAlignment
        }

        // デフォルトロジック:
        // - 横向き画像（アスペクト比 >= 1.2）: センタリング
        // - それ以外:
        //   - 右→左表示: 右側
        //   - 左→右表示: 左側
        guard let source = imageSource,
              let size = source.imageSize(at: currentPage) else {
            return .center
        }

        let aspectRatio = size.width / size.height
        if aspectRatio >= landscapeAspectRatioThreshold {
            // 横向き画像はセンタリング
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
        pageDisplaySettings.setAlignment(alignment, for: currentPage)
        saveViewState()
        loadCurrentPage()
    }

    /// 現在のページの配置（メニュー表示用）
    var currentPageAlignment: SinglePageAlignment {
        return getCurrentPageAlignment()
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
        if let encoded = try? JSONEncoder().encode(pageDisplaySettings) {
            UserDefaults.standard.set(encoded, forKey: "\(pageDisplaySettingsKey)-\(fileKey)")
        }
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
        if let data = UserDefaults.standard.data(forKey: "\(pageDisplaySettingsKey)-\(fileKey)") {
            do {
                pageDisplaySettings = try JSONDecoder().decode(PageDisplaySettings.self, from: data)
            } catch {
                debugLog("Failed to decode PageDisplaySettings: \(error)", level: .minimal)
                // デコード失敗時は空の設定で初期化
                pageDisplaySettings = PageDisplaySettings()
            }
        } else {
            // 設定が存在しない場合は空の設定で初期化
            pageDisplaySettings = PageDisplaySettings()
        }
    }

    /// 現在のページ情報（表示用）
    var pageInfo: String {
        guard totalPages > 0 else { return "" }

        switch viewMode {
        case .single:
            return "\(currentPage + 1) / \(totalPages)"
        case .spread:
            let firstPage = currentPage + 1
            let secondPage = currentPage + 2

            // 2ページ目が存在する場合
            if secondPage <= totalPages {
                switch readingDirection {
                case .rightToLeft:
                    // 右→左: first secondの順（右側が先）
                    return "\(firstPage) \(secondPage) / \(totalPages)"
                case .leftToRight:
                    // 左→右: first secondの順（左側が先）
                    return "\(firstPage) \(secondPage) / \(totalPages)"
                }
            } else {
                // 最後のページが1ページだけの場合
                return "\(firstPage) / \(totalPages)"
            }
        }
    }

    /// 現在のファイル名
    var currentFileName: String {
        guard let source = imageSource else { return "" }

        switch viewMode {
        case .single:
            return source.fileName(at: currentPage) ?? ""
        case .spread:
            // 単ページ表示の場合
            if shouldShowCurrentPageAsSingle() {
                return source.fileName(at: currentPage) ?? ""
            }

            // 見開き表示の場合
            let firstFileName = source.fileName(at: currentPage) ?? ""

            // 2ページ目が存在する場合
            if currentPage + 1 < source.imageCount {
                let secondFileName = source.fileName(at: currentPage + 1) ?? ""

                // 読み方向に応じて、画面表示順（左→右）でファイル名を表示
                switch readingDirection {
                case .rightToLeft:
                    // 右→左: 画面上は [second(左) | first(右)]
                    return "\(secondFileName)  \(firstFileName)"
                case .leftToRight:
                    // 左→右: 画面上は [first(左) | second(右)]
                    return "\(firstFileName)  \(secondFileName)"
                }
            } else {
                // 1ページのみの場合
                return firstFileName
            }
        }
    }

    // 下位互換のためにarchiveFileNameをsourceNameのエイリアスとして定義
    var archiveFileName: String {
        return sourceName
    }
}
