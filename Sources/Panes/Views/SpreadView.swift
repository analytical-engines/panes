import SwiftUI
import AppKit

/// 見開き表示用のView
struct SpreadView: View {
    let readingDirection: ReadingDirection
    let firstPageImage: NSImage   // currentPage
    let secondPageImage: NSImage? // currentPage + 1

    var body: some View {
        HStack(spacing: 0) {
            switch readingDirection {
            case .rightToLeft:
                // 右→左読み: 先に読むページ(first)が右側
                if let secondPageImage = secondPageImage {
                    Image(nsImage: secondPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
                Image(nsImage: firstPageImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

            case .leftToRight:
                // 左→右読み: 先に読むページ(first)が左側
                Image(nsImage: firstPageImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                if let secondPageImage = secondPageImage {
                    Image(nsImage: secondPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
        }
    }
}
