import SwiftUI
import AppKit

/// 見開き表示用のView
struct SpreadView<ContextMenu: View>: View {
    let readingDirection: ReadingDirection
    let firstPageImage: NSImage   // currentPage
    let firstPageIndex: Int
    let secondPageImage: NSImage? // currentPage + 1
    let secondPageIndex: Int
    let singlePageAlignment: SinglePageAlignment // 単ページ表示時の配置
    let firstPageRotation: ImageRotation
    let firstPageFlip: ImageFlip
    let secondPageRotation: ImageRotation
    let secondPageFlip: ImageFlip
    let contextMenuBuilder: (Int) -> ContextMenu

    var body: some View {
        let _ = DebugLogger.log("📖 SpreadView body: firstPageIndex=\(firstPageIndex), secondPageIndex=\(secondPageIndex), direction=\(readingDirection)", level: .verbose)
        GeometryReader { geometry in
            if let secondPageImage = secondPageImage {
                // 見開き表示（2ページ）
                HStack(alignment: .center, spacing: 0) {
                    switch readingDirection {
                    case .rightToLeft:
                        // 右→左読み: 先に読むページ(first)が右側
                        // LEFT side = secondPage, RIGHT side = firstPage
                        Image(nsImage: secondPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .imageTransform(rotation: secondPageRotation, flip: secondPageFlip)
                            .frame(height: geometry.size.height)
                            .contextMenu {
                                let _ = DebugLogger.log("🖼️ LEFT image context menu: secondPageIndex=\(secondPageIndex)", level: .verbose)
                                contextMenuBuilder(secondPageIndex)
                            }
                        Image(nsImage: firstPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .imageTransform(rotation: firstPageRotation, flip: firstPageFlip)
                            .frame(height: geometry.size.height)
                            .contextMenu {
                                let _ = DebugLogger.log("🖼️ RIGHT image context menu: firstPageIndex=\(firstPageIndex)", level: .verbose)
                                contextMenuBuilder(firstPageIndex)
                            }

                    case .leftToRight:
                        // 左→右読み: 先に読むページ(first)が左側
                        // LEFT side = firstPage, RIGHT side = secondPage
                        Image(nsImage: firstPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .imageTransform(rotation: firstPageRotation, flip: firstPageFlip)
                            .frame(height: geometry.size.height)
                            .contextMenu {
                                let _ = DebugLogger.log("🖼️ LEFT image context menu: firstPageIndex=\(firstPageIndex)", level: .verbose)
                                contextMenuBuilder(firstPageIndex)
                            }
                        Image(nsImage: secondPageImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .imageTransform(rotation: secondPageRotation, flip: secondPageFlip)
                            .frame(height: geometry.size.height)
                            .contextMenu {
                                let _ = DebugLogger.log("🖼️ RIGHT image context menu: secondPageIndex=\(secondPageIndex)", level: .verbose)
                                contextMenuBuilder(secondPageIndex)
                            }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                // 単ページ表示（見開きモード中）
                let halfWidth = geometry.size.width / 2

                switch singlePageAlignment {
                case .right:
                    // 右側表示（中央線の右側に配置）- 回転対応
                    HStack(spacing: 0) {
                        Spacer()
                            .frame(width: halfWidth)
                        RotationAwareImageView(
                            image: firstPageImage,
                            rotation: firstPageRotation,
                            flip: firstPageFlip,
                            containerWidth: halfWidth,
                            containerHeight: geometry.size.height
                        )
                        .frame(maxWidth: halfWidth, alignment: .leading)
                        .contextMenu { contextMenuBuilder(firstPageIndex) }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)

                case .left:
                    // 左側表示（中央線の左側に配置）- 回転対応
                    HStack(spacing: 0) {
                        RotationAwareImageView(
                            image: firstPageImage,
                            rotation: firstPageRotation,
                            flip: firstPageFlip,
                            containerWidth: halfWidth,
                            containerHeight: geometry.size.height
                        )
                        .frame(maxWidth: halfWidth, alignment: .trailing)
                        .contextMenu { contextMenuBuilder(firstPageIndex) }
                        Spacer()
                            .frame(width: halfWidth)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)

                case .center:
                    // センタリング（ウィンドウフィッティング）- 回転対応
                    RotationAwareImageView(
                        image: firstPageImage,
                        rotation: firstPageRotation,
                        flip: firstPageFlip,
                        containerWidth: geometry.size.width,
                        containerHeight: geometry.size.height
                    )
                    .contextMenu { contextMenuBuilder(firstPageIndex) }
                }
            }
        }
    }
}
