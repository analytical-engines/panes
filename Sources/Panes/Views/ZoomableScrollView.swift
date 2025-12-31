import SwiftUI
import AppKit

/// マウスカーソル位置を中心にズーム可能なScrollView
struct ZoomableScrollView<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: () -> Content
    let viewportSize: CGSize

    init(viewportSize: CGSize, @ViewBuilder content: @escaping () -> Content) {
        self.viewportSize = viewportSize
        self.content = content
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .allowed

        let hostingView = ZoomableHostingView(rootView: content())
        hostingView.scrollView = scrollView
        scrollView.documentView = hostingView

        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = context.coordinator.hostingView else { return }
        hostingView.rootView = content()

        // コンテンツサイズをフィッティング
        let fittingSize = hostingView.fittingSize
        if hostingView.frame.size != fittingSize {
            // ズーム時のスクロール位置調整は ZoomableHostingView 内で行う
            hostingView.frame.size = fittingSize
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var scrollView: NSScrollView?
        weak var hostingView: ZoomableHostingView<Content>?
    }
}

/// ズーム時にマウス位置を中心にスクロール位置を調整するHostingView
class ZoomableHostingView<Content: View>: NSHostingView<Content> {
    weak var scrollView: NSScrollView?
    private var lastContentSize: CGSize = .zero
    private var pendingZoomAnchor: NSPoint?

    override var frame: NSRect {
        didSet {
            if frame.size != lastContentSize {
                adjustScrollPositionForZoom(oldSize: lastContentSize, newSize: frame.size)
                lastContentSize = frame.size
            }
        }
    }

    /// マウスカーソル位置を中心にズームするようスクロール位置を調整
    private func adjustScrollPositionForZoom(oldSize: CGSize, newSize: CGSize) {
        guard let scrollView = scrollView,
              oldSize.width > 0, oldSize.height > 0 else {
            lastContentSize = newSize
            return
        }

        let visibleRect = scrollView.documentVisibleRect
        let viewportSize = scrollView.bounds.size

        // マウス位置を取得
        let mouseLocationInWindow = scrollView.window?.mouseLocationOutsideOfEventStream ?? .zero
        let mouseInScrollView = scrollView.convert(mouseLocationInWindow, from: nil)

        // マウスがスクロールビュー内にあるか確認
        let isMouseInView = scrollView.bounds.contains(mouseInScrollView)

        // アンカーポイントを決定（マウス位置、またはビューポートの中心）
        let anchorInViewport: CGPoint
        if isMouseInView {
            anchorInViewport = CGPoint(
                x: mouseInScrollView.x,
                y: viewportSize.height - mouseInScrollView.y  // Y軸反転
            )
        } else {
            anchorInViewport = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        }

        // アンカーポイントがコンテンツ上のどこを指しているか計算
        // (visibleRect.origin + anchorInViewport) / oldSize
        let anchorInContentX = (visibleRect.minX + anchorInViewport.x) / oldSize.width
        let anchorInContentY = (visibleRect.minY + (viewportSize.height - anchorInViewport.y)) / oldSize.height

        // 新しいスクロール位置を計算
        // アンカーポイントが同じ画面位置に来るように
        let newScrollX = anchorInContentX * newSize.width - anchorInViewport.x
        let newScrollY = anchorInContentY * newSize.height - (viewportSize.height - anchorInViewport.y)

        // スクロール範囲内にクランプ
        let maxScrollX = max(0, newSize.width - viewportSize.width)
        let maxScrollY = max(0, newSize.height - viewportSize.height)
        let clampedX = min(max(0, newScrollX), maxScrollX)
        let clampedY = min(max(0, newScrollY), maxScrollY)

        // スクロール位置を設定
        scroll(NSPoint(x: clampedX, y: clampedY))
    }
}
