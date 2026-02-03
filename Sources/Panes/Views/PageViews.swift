import SwiftUI
import AppKit

/// ステータスバー
struct StatusBarView: View {
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String

    var body: some View {
        HStack {
            Text(archiveFileName)
                .foregroundColor(.white)
            Spacer()
            Text(currentFileName)
                .foregroundColor(.gray)
            Spacer()
            HStack(spacing: 8) {
                if !singlePageIndicator.isEmpty {
                    Text(singlePageIndicator)
                        .foregroundColor(.orange)
                }
                Text(pageInfo)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
}

/// 単ページ表示ビュー
struct SinglePageView<ContextMenu: View>: View {
    let image: NSImage
    let pageIndex: Int
    let rotation: ImageRotation
    let flip: ImageFlip
    let fittingMode: FittingMode
    let zoomLevel: CGFloat
    let interpolation: InterpolationMode
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String
    let contextMenuBuilder: (Int) -> ContextMenu
    /// 左半分クリック時のコールバック
    var onTapLeft: (() -> Void)? = nil
    /// 右半分クリック時のコールバック
    var onTapRight: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                // ズームが適用されている場合、または等倍表示の場合はスクロール可能にする
                if zoomLevel != 1.0 || fittingMode == .originalSize {
                    ZoomableScrollView(viewportSize: geometry.size) {
                        ImageDisplayView(
                            image: image,
                            rotation: rotation,
                            flip: flip,
                            fittingMode: fittingMode,
                            viewportSize: geometry.size,
                            zoomLevel: zoomLevel,
                            interpolation: interpolation
                        )
                        .contextMenu { contextMenuBuilder(pageIndex) }
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height,
                            alignment: .center
                        )
                    }
                } else {
                    switch fittingMode {
                    case .window:
                        ImageDisplayView(image: image, rotation: rotation, flip: flip, fittingMode: fittingMode, interpolation: interpolation)
                            .contextMenu { contextMenuBuilder(pageIndex) }
                    case .height:
                        // 縦フィット: 横スクロール可能、横センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
                            ImageDisplayView(
                                image: image,
                                rotation: rotation,
                                flip: flip,
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation
                            )
                            .contextMenu { contextMenuBuilder(pageIndex) }
                            .frame(minWidth: geometry.size.width, alignment: .center)
                        }
                    case .width:
                        // 横フィット: 縦スクロール可能、縦センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
                            ImageDisplayView(
                                image: image,
                                rotation: rotation,
                                flip: flip,
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation
                            )
                            .contextMenu { contextMenuBuilder(pageIndex) }
                            .frame(minHeight: geometry.size.height, alignment: .center)
                        }
                    case .originalSize:
                        // このケースはzoomLevel != 1.0 || fittingMode == .originalSizeで処理される
                        EmptyView()
                    }
                }
            }
            // タップでページめくり（ズーム中・縦横フィット時は無効）
            .overlay {
                if zoomLevel == 1.0 && fittingMode == .window {
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .contextMenu { contextMenuBuilder(pageIndex) }
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        let isLeftHalf = value.location.x < geo.size.width / 2
                                        if isLeftHalf {
                                            onTapLeft?()
                                        } else {
                                            onTapRight?()
                                        }
                                    }
                            )
                    }
                }
            }

            if showStatusBar {
                StatusBarView(
                    archiveFileName: archiveFileName,
                    currentFileName: currentFileName,
                    singlePageIndicator: singlePageIndicator,
                    pageInfo: pageInfo
                )
            }
        }
    }
}

/// 見開き表示ビュー
struct SpreadPageView<ContextMenu: View>: View {
    let readingDirection: ReadingDirection
    let firstPageImage: NSImage
    let firstPageIndex: Int
    let secondPageImage: NSImage?
    let secondPageIndex: Int
    let singlePageAlignment: SinglePageAlignment
    let firstPageRotation: ImageRotation
    let firstPageFlip: ImageFlip
    let secondPageRotation: ImageRotation
    let secondPageFlip: ImageFlip
    let fittingMode: FittingMode
    let zoomLevel: CGFloat
    let interpolation: InterpolationMode
    let showStatusBar: Bool
    let archiveFileName: String
    let currentFileName: String
    let singlePageIndicator: String
    let pageInfo: String
    var copiedPageIndex: Int? = nil
    let contextMenuBuilder: (Int) -> ContextMenu
    /// 左半分クリック時のコールバック
    var onTapLeft: (() -> Void)? = nil
    /// 右半分クリック時のコールバック
    var onTapRight: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                // ズームが適用されている場合は常にスクロール可能にする
                if zoomLevel != 1.0 {
                    ZoomableScrollView(viewportSize: geometry.size) {
                        SpreadView(
                            readingDirection: readingDirection,
                            firstPageImage: firstPageImage,
                            firstPageIndex: firstPageIndex,
                            secondPageImage: secondPageImage,
                            secondPageIndex: secondPageIndex,
                            singlePageAlignment: singlePageAlignment,
                            firstPageRotation: firstPageRotation,
                            firstPageFlip: firstPageFlip,
                            secondPageRotation: secondPageRotation,
                            secondPageFlip: secondPageFlip,
                            fittingMode: fittingMode,
                            viewportSize: geometry.size,
                            zoomLevel: zoomLevel,
                            interpolation: interpolation,
                            copiedPageIndex: copiedPageIndex,
                            contextMenuBuilder: contextMenuBuilder
                        )
                        .equatable()
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height,
                            alignment: .center
                        )
                    }
                } else {
                    switch fittingMode {
                    case .window:
                        SpreadView(
                            readingDirection: readingDirection,
                            firstPageImage: firstPageImage,
                            firstPageIndex: firstPageIndex,
                            secondPageImage: secondPageImage,
                            secondPageIndex: secondPageIndex,
                            singlePageAlignment: singlePageAlignment,
                            firstPageRotation: firstPageRotation,
                            firstPageFlip: firstPageFlip,
                            secondPageRotation: secondPageRotation,
                            secondPageFlip: secondPageFlip,
                            fittingMode: fittingMode,
                            interpolation: interpolation,
                            copiedPageIndex: copiedPageIndex,
                            contextMenuBuilder: contextMenuBuilder
                        )
                        .equatable()
                    case .height:
                        // 縦フィット: 横スクロール可能、横センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
                            SpreadView(
                                readingDirection: readingDirection,
                                firstPageImage: firstPageImage,
                                firstPageIndex: firstPageIndex,
                                secondPageImage: secondPageImage,
                                secondPageIndex: secondPageIndex,
                                singlePageAlignment: singlePageAlignment,
                                firstPageRotation: firstPageRotation,
                                firstPageFlip: firstPageFlip,
                                secondPageRotation: secondPageRotation,
                                secondPageFlip: secondPageFlip,
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation,
                                copiedPageIndex: copiedPageIndex,
                                contextMenuBuilder: contextMenuBuilder
                            )
                            .equatable()
                            .frame(minWidth: geometry.size.width, alignment: .center)
                        }
                    case .width:
                        // 横フィット: 縦スクロール可能、縦センタリング
                        ZoomableScrollView(viewportSize: geometry.size) {
                            SpreadView(
                                readingDirection: readingDirection,
                                firstPageImage: firstPageImage,
                                firstPageIndex: firstPageIndex,
                                secondPageImage: secondPageImage,
                                secondPageIndex: secondPageIndex,
                                singlePageAlignment: singlePageAlignment,
                                firstPageRotation: firstPageRotation,
                                firstPageFlip: firstPageFlip,
                                secondPageRotation: secondPageRotation,
                                secondPageFlip: secondPageFlip,
                                fittingMode: fittingMode,
                                viewportSize: geometry.size,
                                interpolation: interpolation,
                                copiedPageIndex: copiedPageIndex,
                                contextMenuBuilder: contextMenuBuilder
                            )
                            .equatable()
                            .frame(minHeight: geometry.size.height, alignment: .center)
                        }
                    case .originalSize:
                        // 等倍表示は見開きでは未対応、ウィンドウフィットにフォールバック
                        SpreadView(
                            readingDirection: readingDirection,
                            firstPageImage: firstPageImage,
                            firstPageIndex: firstPageIndex,
                            secondPageImage: secondPageImage,
                            secondPageIndex: secondPageIndex,
                            singlePageAlignment: singlePageAlignment,
                            firstPageRotation: firstPageRotation,
                            firstPageFlip: firstPageFlip,
                            secondPageRotation: secondPageRotation,
                            secondPageFlip: secondPageFlip,
                            fittingMode: .window,
                            interpolation: interpolation,
                            copiedPageIndex: copiedPageIndex,
                            contextMenuBuilder: contextMenuBuilder
                        )
                        .equatable()
                    }
                }
            }
            // タップでページめくり（ズーム中・縦横フィット時は無効）
            .overlay {
                if zoomLevel == 1.0 && fittingMode == .window {
                    if secondPageImage != nil {
                        // 見開き表示: 左右で異なるページのコンテキストメニューを表示
                        // RTL: 左=secondPage, 右=firstPage / LTR: 左=firstPage, 右=secondPage
                        let leftPageIndex = readingDirection == .rightToLeft ? secondPageIndex : firstPageIndex
                        let rightPageIndex = readingDirection == .rightToLeft ? firstPageIndex : secondPageIndex
                        HStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .contextMenu { contextMenuBuilder(leftPageIndex) }
                                .onTapGesture { onTapLeft?() }
                            Color.clear
                                .contentShape(Rectangle())
                                .contextMenu { contextMenuBuilder(rightPageIndex) }
                                .onTapGesture { onTapRight?() }
                        }
                    } else {
                        // 単ページ表示（見開きモード中）: 画像がある領域のみコンテキストメニューを表示
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                switch singlePageAlignment {
                                case .left:
                                    // 左側に画像、右側は空
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .contextMenu { contextMenuBuilder(firstPageIndex) }
                                        .simultaneousGesture(
                                            SpatialTapGesture()
                                                .onEnded { value in
                                                    // 左半分全体がタップ領域
                                                    onTapLeft?()
                                                }
                                        )
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture { onTapRight?() }
                                        // 右側は画像がないのでコンテキストメニューなし
                                case .right:
                                    // 左側は空、右側に画像
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture { onTapLeft?() }
                                        // 左側は画像がないのでコンテキストメニューなし
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .contextMenu { contextMenuBuilder(firstPageIndex) }
                                        .simultaneousGesture(
                                            SpatialTapGesture()
                                                .onEnded { value in
                                                    // 右半分全体がタップ領域
                                                    onTapRight?()
                                                }
                                        )
                                case .center:
                                    // センター配置: 全体が1つの画像
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .contextMenu { contextMenuBuilder(firstPageIndex) }
                                        .simultaneousGesture(
                                            SpatialTapGesture()
                                                .onEnded { value in
                                                    let isLeftHalf = value.location.x < geo.size.width / 2
                                                    if isLeftHalf {
                                                        onTapLeft?()
                                                    } else {
                                                        onTapRight?()
                                                    }
                                                }
                                        )
                                }
                            }
                        }
                    }
                }
            }

            if showStatusBar {
                StatusBarView(
                    archiveFileName: archiveFileName,
                    currentFileName: currentFileName,
                    singlePageIndicator: singlePageIndicator,
                    pageInfo: pageInfo
                )
            }
        }
    }
}

/// グレー半透明スクロールバーのカスタムScrollView
struct CustomScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false

        // カスタムスクローラーを設定（システム設定に従う）
        let scroller = GrayScroller()
        scrollView.verticalScroller = scroller

        // SwiftUIコンテンツをホスト
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = hostingView

        // ドキュメントビューのサイズをスクロールビューの幅に合わせる
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            // コンテンツサイズが変わった時にスクロール領域を更新
            hostingView.invalidateIntrinsicContentSize()
            hostingView.layoutSubtreeIfNeeded()
        }
    }
}

/// グレー半透明のカスタムスクローラー
class GrayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // トラック背景を暗いグレーで描画（「常に表示」設定時用）
        let path = NSBezierPath(roundedRect: slotRect, xRadius: 4, yRadius: 4)
        NSColor.darkGray.withAlphaComponent(0.3).setFill()
        path.fill()
    }

    override func drawKnob() {
        let knobRect = self.rect(for: .knob).insetBy(dx: 2, dy: 2)
        guard !knobRect.isEmpty else { return }

        let path = NSBezierPath(roundedRect: knobRect, xRadius: 4, yRadius: 4)
        NSColor.gray.withAlphaComponent(0.6).setFill()
        path.fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        // トラックを描画（「常に表示」設定時）
        if self.scrollerStyle == .legacy {
            self.drawKnobSlot(in: self.rect(for: .knobSlot), highlight: false)
        }
        self.drawKnob()
    }
}
