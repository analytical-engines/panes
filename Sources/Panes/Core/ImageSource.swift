import Foundation
import AppKit

/// 画像ソースのプロトコル（zipアーカイブ、通常ファイルなど）
protocol ImageSource {
    /// ソース名（ファイル名など）
    var sourceName: String { get }

    /// 画像の総数
    var imageCount: Int { get }

    /// 指定されたインデックスの画像を読み込む
    func loadImage(at index: Int) -> NSImage?

    /// 指定されたインデックスのファイル名
    func fileName(at index: Int) -> String?
}
