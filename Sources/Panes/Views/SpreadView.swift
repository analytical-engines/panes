import SwiftUI
import AppKit

/// 見開き表示用のView（右ページ | 左ページ）
struct SpreadView: View {
    let rightImage: NSImage?
    let leftImage: NSImage

    var body: some View {
        HStack(spacing: 0) {
            // 右ページ
            if let rightImage = rightImage {
                Image(nsImage: rightImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // 右ページがない場合は空白
                Color.clear
            }

            // 左ページ
            Image(nsImage: leftImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
