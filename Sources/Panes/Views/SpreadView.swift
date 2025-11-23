import SwiftUI
import AppKit

/// 見開き表示用のView
struct SpreadView: View {
    let readingDirection: ReadingDirection
    let firstPageImage: NSImage   // currentPage
    let secondPageImage: NSImage? // currentPage + 1
    let singlePageAlignment: SinglePageAlignment // 単ページ表示時の配置

    var body: some View {
        HStack(spacing: 0) {
            if let secondPageImage = secondPageImage {
                // 見開き表示（2ページ）
                switch readingDirection {
                case .rightToLeft:
                    // 右→左読み: 先に読むページ(first)が右側
                    Image(nsImage: secondPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    Image(nsImage: firstPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                case .leftToRight:
                    // 左→右読み: 先に読むページ(first)が左側
                    Image(nsImage: firstPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    Image(nsImage: secondPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                // 単ページ表示（見開きモード中）
                switch singlePageAlignment {
                case .right:
                    // 右側表示
                    Color.clear
                    Image(nsImage: firstPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                case .left:
                    // 左側表示
                    Image(nsImage: firstPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    Color.clear

                case .center:
                    // センタリング（ウィンドウフィッティング）
                    Image(nsImage: firstPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
    }
}
