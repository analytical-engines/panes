import Foundation
import SwiftUI
import AppKit

/// 表示モード
enum ViewMode {
    case single  // 単ページ
    case spread  // 見開き
}

/// 書籍（画像アーカイブ）の表示状態を管理するViewModel
@Observable
class BookViewModel {
    // 画像ソース
    private var imageSource: ImageSource?

    // UserDefaultsのキー
    private let viewModeKey = "viewMode"
    private let currentPageKey = "currentPage"

    // 現在表示中の画像
    var currentImage: NSImage?

    // 見開き表示用：右ページの画像
    var rightImage: NSImage?

    // 見開き表示用：左ページの画像
    var leftImage: NSImage?

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
        guard imageSource != nil else { return }

        switch viewMode {
        case .single:
            loadSinglePage()
        case .spread:
            loadSpreadPages()
        }
    }

    /// 単ページモードの画像読み込み
    private func loadSinglePage() {
        guard let source = imageSource else { return }

        if let image = source.loadImage(at: currentPage) {
            self.currentImage = image
            self.errorMessage = nil
        } else {
            let fileName = source.fileName(at: currentPage) ?? "不明"
            self.errorMessage = "画像の読み込みに失敗しました\nファイル: \(fileName)\nページ: \(currentPage + 1)/\(totalPages)"
            print("ERROR: Failed to load image at index \(currentPage), file: \(fileName)")
        }
    }

    /// 見開きモードの画像読み込み（右ページ | 左ページ）
    private func loadSpreadPages() {
        guard let source = imageSource else { return }

        // 右ページ（偶数インデックス = currentPage + 1）
        if currentPage + 1 < source.imageCount {
            self.rightImage = source.loadImage(at: currentPage + 1)
        } else {
            self.rightImage = nil
        }

        // 左ページ（奇数インデックス = currentPage）
        self.leftImage = source.loadImage(at: currentPage)

        self.errorMessage = nil
    }

    /// 次のページへ
    func nextPage() {
        guard let source = imageSource else { return }

        let step = viewMode == .spread ? 2 : 1
        let newPage = currentPage + step

        if newPage < source.imageCount {
            currentPage = newPage
            loadCurrentPage()
            saveViewState()
        }
    }

    /// 前のページへ
    func previousPage() {
        let step = viewMode == .spread ? 2 : 1
        let newPage = currentPage - step

        if newPage >= 0 {
            currentPage = newPage
            loadCurrentPage()
            saveViewState()
        }
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

    /// 表示状態を保存（モードとページ番号）
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
    }

    /// 表示状態を復元（モードとページ番号）
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
    }

    /// 現在のページ情報（表示用）
    var pageInfo: String {
        guard totalPages > 0 else { return "" }
        return "\(currentPage + 1) / \(totalPages)"
    }

    /// 現在のファイル名
    var currentFileName: String {
        guard let source = imageSource else { return "" }
        return source.fileName(at: currentPage) ?? ""
    }

    // 下位互換のためにarchiveFileNameをsourceNameのエイリアスとして定義
    var archiveFileName: String {
        return sourceName
    }
}
