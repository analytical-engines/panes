import SwiftUI
import AppKit

/// 見開き表示用のView
struct SpreadView: View {
    let readingDirection: ReadingDirection
    let firstPageImage: NSImage   // currentPage
    let secondPageImage: NSImage? // currentPage + 1
    let singlePageAlignment: SinglePageAlignment // 単ページ表示時の配置

    var body: some View {
        GeometryReader { geometry in
            if let secondPageImage = secondPageImage {
                // 見開き表示（2ページ）
                HStack(alignment: .center, spacing: 0) {
                    switch readingDirection {
                    case .rightToLeft:
                        // 右→左読み: 先に読むページ(first)が右側
                        Image(nsImage: secondPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: geometry.size.height)
                        Image(nsImage: firstPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: geometry.size.height)

                    case .leftToRight:
                        // 左→右読み: 先に読むページ(first)が左側
                        Image(nsImage: firstPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: geometry.size.height)
                        Image(nsImage: secondPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: geometry.size.height)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                // 単ページ表示（見開きモード中）
                let halfWidth = geometry.size.width / 2

                switch singlePageAlignment {
                case .right:
                    // 右側表示（中央線の右側に配置）
                    HStack(spacing: 0) {
                        Spacer()
                            .frame(width: halfWidth)
                        Image(nsImage: firstPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: halfWidth, maxHeight: geometry.size.height, alignment: .leading)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)

                case .left:
                    // 左側表示（中央線の左側に配置）
                    HStack(spacing: 0) {
                        Image(nsImage: firstPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: halfWidth, maxHeight: geometry.size.height, alignment: .trailing)
                        Spacer()
                            .frame(width: halfWidth)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)

                case .center:
                    // センタリング（ウィンドウフィッティング）
                    Image(nsImage: firstPageImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }
}
