import Foundation
import SwiftUI
import AppKit

/// 書籍（画像アーカイブ）の表示状態を管理するViewModel
@Observable
class BookViewModel {
    // 画像ソース
    private var imageSource: ImageSource?

    // 現在表示中の画像
    var currentImage: NSImage?

    // 現在のページ番号（0始まり）
    var currentPage: Int = 0

    // 総ページ数
    var totalPages: Int = 0

    // ソース名（ファイル名など）
    var sourceName: String = ""

    // エラーメッセージ
    var errorMessage: String?

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

        // 最初の画像を読み込む
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
        guard let source = imageSource else { return }

        if let image = source.loadImage(at: currentPage) {
            self.currentImage = image
            self.errorMessage = nil  // エラーをクリア
        } else {
            let fileName = source.fileName(at: currentPage) ?? "不明"
            self.errorMessage = "画像の読み込みに失敗しました\nファイル: \(fileName)\nページ: \(currentPage + 1)/\(totalPages)"
            print("ERROR: Failed to load image at index \(currentPage), file: \(fileName)")
        }
    }

    /// 次のページへ
    func nextPage() {
        guard let source = imageSource else { return }
        if currentPage < source.imageCount - 1 {
            currentPage += 1
            loadCurrentPage()
        }
    }

    /// 前のページへ
    func previousPage() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        loadCurrentPage()
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
