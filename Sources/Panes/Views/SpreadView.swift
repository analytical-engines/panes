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
    var fittingMode: FittingMode = .window
    /// ScrollView内で使用する場合に外部から渡すビューポートサイズ
    var viewportSize: CGSize? = nil
    /// ズームレベル（1.0 = 100%）
    var zoomLevel: CGFloat = 1.0
    /// 補間アルゴリズム
    var interpolation: InterpolationMode = .highQuality
    /// コンテキストメニュー状態（移動元マーク等）- Equatableで比較してメニュー更新を検出
    var copiedPageIndex: Int? = nil
    let contextMenuBuilder: (Int) -> ContextMenu

    var body: some View {
        let _ = DebugLogger.log("📖 SpreadView body: firstPageIndex=\(firstPageIndex), secondPageIndex=\(secondPageIndex), direction=\(readingDirection)", level: .verbose)
        if let viewport = viewportSize {
            // ビューポートサイズが指定されている場合（ScrollView内）
            spreadContent(size: viewport)
        } else {
            // 通常の場合（GeometryReaderでサイズ取得）
            GeometryReader { geometry in
                spreadContent(size: geometry.size)
            }
        }
    }

    @ViewBuilder
    private func spreadContent(size: CGSize) -> some View {
        if let secondPageImage = secondPageImage {
            // 見開き表示（2ページ）
            // 各ページを halfWidth のコンテナ内に配置し、中央線に寄せる
            let halfWidth = size.width / 2
            HStack(spacing: 0) {
                switch readingDirection {
                case .rightToLeft:
                    // 右→左読み: 先に読むページ(first)が右側
                    // LEFT side = secondPage (trailing alignment), RIGHT side = firstPage (leading alignment)
                    RotationAwareImageView(
                        image: secondPageImage,
                        rotation: secondPageRotation,
                        flip: secondPageFlip,
                        containerWidth: halfWidth,
                        containerHeight: size.height,
                        alignment: .trailing,
                        fittingMode: fittingMode,
                        zoomLevel: zoomLevel,
                        interpolation: interpolation
                    )
                    .contextMenu {
                        let _ = DebugLogger.log("🖼️ LEFT image context menu: secondPageIndex=\(secondPageIndex)", level: .verbose)
                        contextMenuBuilder(secondPageIndex)
                    }
                    RotationAwareImageView(
                        image: firstPageImage,
                        rotation: firstPageRotation,
                        flip: firstPageFlip,
                        containerWidth: halfWidth,
                        containerHeight: size.height,
                        alignment: .leading,
                        fittingMode: fittingMode,
                        zoomLevel: zoomLevel,
                        interpolation: interpolation
                    )
                    .contextMenu {
                        let _ = DebugLogger.log("🖼️ RIGHT image context menu: firstPageIndex=\(firstPageIndex)", level: .verbose)
                        contextMenuBuilder(firstPageIndex)
                    }

                case .leftToRight:
                    // 左→右読み: 先に読むページ(first)が左側
                    // LEFT side = firstPage (trailing alignment), RIGHT side = secondPage (leading alignment)
                    RotationAwareImageView(
                        image: firstPageImage,
                        rotation: firstPageRotation,
                        flip: firstPageFlip,
                        containerWidth: halfWidth,
                        containerHeight: size.height,
                        alignment: .trailing,
                        fittingMode: fittingMode,
                        zoomLevel: zoomLevel,
                        interpolation: interpolation
                    )
                    .contextMenu {
                        let _ = DebugLogger.log("🖼️ LEFT image context menu: firstPageIndex=\(firstPageIndex)", level: .verbose)
                        contextMenuBuilder(firstPageIndex)
                    }
                    RotationAwareImageView(
                        image: secondPageImage,
                        rotation: secondPageRotation,
                        flip: secondPageFlip,
                        containerWidth: halfWidth,
                        containerHeight: size.height,
                        alignment: .leading,
                        fittingMode: fittingMode,
                        zoomLevel: zoomLevel,
                        interpolation: interpolation
                    )
                    .contextMenu {
                        let _ = DebugLogger.log("🖼️ RIGHT image context menu: secondPageIndex=\(secondPageIndex)", level: .verbose)
                        contextMenuBuilder(secondPageIndex)
                    }
                }
            }
            .frame(
                minWidth: fittingMode == .height ? nil : size.width,
                maxWidth: fittingMode == .height ? .infinity : size.width,
                minHeight: fittingMode == .width ? nil : size.height,
                maxHeight: fittingMode == .width ? .infinity : size.height
            )
        } else {
            // 単ページ表示（見開きモード中）
            let halfWidth = size.width / 2

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
                        containerHeight: size.height,
                        alignment: .leading,
                        fittingMode: fittingMode,
                        zoomLevel: zoomLevel,
                        interpolation: interpolation
                    )
                    .contextMenu { contextMenuBuilder(firstPageIndex) }
                }
                .frame(
                    minWidth: fittingMode == .height ? nil : size.width,
                    maxWidth: fittingMode == .height ? .infinity : size.width,
                    minHeight: fittingMode == .width ? nil : size.height,
                    maxHeight: fittingMode == .width ? .infinity : size.height,
                    alignment: .leading
                )

            case .left:
                // 左側表示（中央線の左側に配置）- 回転対応
                HStack(spacing: 0) {
                    RotationAwareImageView(
                        image: firstPageImage,
                        rotation: firstPageRotation,
                        flip: firstPageFlip,
                        containerWidth: halfWidth,
                        containerHeight: size.height,
                        alignment: .trailing,
                        fittingMode: fittingMode,
                        zoomLevel: zoomLevel,
                        interpolation: interpolation
                    )
                    .contextMenu { contextMenuBuilder(firstPageIndex) }
                    Spacer()
                        .frame(width: halfWidth)
                }
                .frame(
                    minWidth: fittingMode == .height ? nil : size.width,
                    maxWidth: fittingMode == .height ? .infinity : size.width,
                    minHeight: fittingMode == .width ? nil : size.height,
                    maxHeight: fittingMode == .width ? .infinity : size.height,
                    alignment: .leading
                )

            case .center:
                // センタリング（ウィンドウフィッティング）- 回転対応
                RotationAwareImageView(
                    image: firstPageImage,
                    rotation: firstPageRotation,
                    flip: firstPageFlip,
                    containerWidth: size.width,
                    containerHeight: size.height,
                    fittingMode: fittingMode,
                    zoomLevel: zoomLevel,
                    interpolation: interpolation
                )
                .contextMenu { contextMenuBuilder(firstPageIndex) }
            }
        }
    }
}

// MARK: - Equatable
// クロージャ（contextMenuBuilder）を除外して比較することで、
// フォーカス変更時の不要なbody再評価をスキップできる
extension SpreadView: Equatable {
    nonisolated static func == (lhs: SpreadView, rhs: SpreadView) -> Bool {
        // 画像はページインデックスで判断（同じインデックスなら同じ画像）
        // NSImageは並行処理の問題があるため比較しない
        // ただしsecondPageImageの有無は比較する（単ページ切り替え検出用）
        lhs.firstPageIndex == rhs.firstPageIndex &&
        lhs.secondPageIndex == rhs.secondPageIndex &&
        (lhs.secondPageImage != nil) == (rhs.secondPageImage != nil) &&
        lhs.readingDirection == rhs.readingDirection &&
        lhs.singlePageAlignment == rhs.singlePageAlignment &&
        lhs.firstPageRotation == rhs.firstPageRotation &&
        lhs.firstPageFlip == rhs.firstPageFlip &&
        lhs.secondPageRotation == rhs.secondPageRotation &&
        lhs.secondPageFlip == rhs.secondPageFlip &&
        lhs.fittingMode == rhs.fittingMode &&
        lhs.viewportSize == rhs.viewportSize &&
        lhs.zoomLevel == rhs.zoomLevel &&
        lhs.interpolation == rhs.interpolation &&
        lhs.copiedPageIndex == rhs.copiedPageIndex
    }
}
