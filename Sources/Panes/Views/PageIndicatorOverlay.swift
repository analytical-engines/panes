import SwiftUI

/// マウス移動を検知してオーバーレイを表示するためのモディファイア
struct PageIndicatorModifier: ViewModifier {
    let archiveName: String
    let currentPage: Int
    let totalPages: Int
    let isSpreadView: Bool
    let hasSecondPage: Bool
    let currentFileName: String
    let secondFileName: String?
    let isCurrentPageUserForcedSingle: Bool
    let isSecondPageUserForcedSingle: Bool
    let readingDirection: ReadingDirection
    let onJumpToPage: (Int) -> Void

    @State private var showOverlay = false
    @State private var hideTask: Task<Void, Never>?

    private let autoHideDelay: TimeInterval = 2.0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if totalPages > 0 {
                    PageIndicatorOverlayContent(
                        archiveName: archiveName,
                        currentPage: currentPage,
                        totalPages: totalPages,
                        isSpreadView: isSpreadView,
                        hasSecondPage: hasSecondPage,
                        currentFileName: currentFileName,
                        secondFileName: secondFileName,
                        isCurrentPageUserForcedSingle: isCurrentPageUserForcedSingle,
                        isSecondPageUserForcedSingle: isSecondPageUserForcedSingle,
                        readingDirection: readingDirection,
                        isVisible: $showOverlay,
                        onJumpToPage: onJumpToPage,
                        onHover: { showWithAutoHide() }
                    )
                    .padding(16)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    showWithAutoHide()
                case .ended:
                    break
                }
            }
    }

    private func showWithAutoHide() {
        hideTask?.cancel()
        showOverlay = true

        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoHideDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showOverlay = false
            }
        }
    }
}

/// オーバーレイの内容
struct PageIndicatorOverlayContent: View {
    let archiveName: String
    let currentPage: Int
    let totalPages: Int
    let isSpreadView: Bool
    let hasSecondPage: Bool
    let currentFileName: String
    let secondFileName: String?
    let isCurrentPageUserForcedSingle: Bool
    let isSecondPageUserForcedSingle: Bool
    let readingDirection: ReadingDirection
    @Binding var isVisible: Bool
    let onJumpToPage: (Int) -> Void
    let onHover: () -> Void

    @State private var hoverPosition: CGFloat?

    /// 右→左読みの場合、バーは右から左に進む
    private var isRightToLeft: Bool {
        readingDirection == .rightToLeft
    }

    /// プログレスバーの固定幅
    private let barFixedWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 書庫名
            Text(archiveName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: true, vertical: false)

            // ページ情報テキスト（内容に応じて伸びる）
            pageInfoView
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)

            // プログレスバー（固定幅）
            ZStack(alignment: isRightToLeft ? .trailing : .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: barFixedWidth, height: 6)

                // 進捗
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: progressWidth(in: barFixedWidth), height: 6)
                    .frame(width: barFixedWidth, alignment: isRightToLeft ? .trailing : .leading)
            }
            .frame(width: barFixedWidth, height: 6)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverPosition = location.x
                    onHover()
                case .ended:
                    hoverPosition = nil
                }
            }
            .onTapGesture { location in
                let targetPage = pageForPosition(location.x)
                onJumpToPage(targetPage)
            }
            .overlay(alignment: .top) {
                // ホバー時のツールチップ
                if let hoverX = hoverPosition {
                    let targetPage = pageForPosition(hoverX)
                    Text(tooltipText(for: targetPage))
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                        .offset(x: hoverX - barFixedWidth / 2, y: -28)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .onContinuousHover { phase in
            if case .active = phase {
                onHover()
            }
        }
    }

    /// 見開き表示時のファイル名（画面左側）
    private var leftFileName: String {
        let fileNames = currentFileName.components(separatedBy: "  ")
        return fileNames.first ?? ""
    }

    /// 見開き表示時のファイル名（画面右側）
    private var rightFileName: String {
        let fileNames = currentFileName.components(separatedBy: "  ")
        return fileNames.count > 1 ? fileNames[1] : ""
    }

    /// 画面左側のファイルが単ページ属性か
    private var isLeftFileForcedSingle: Bool {
        // RTL時: 左=currentPage+1, 右=currentPage
        // LTR時: 左=currentPage, 右=currentPage+1
        // BookViewModelではRTL時に [second, first] の順で結合している
        if isRightToLeft {
            return isSecondPageUserForcedSingle
        } else {
            return isCurrentPageUserForcedSingle
        }
    }

    /// 画面右側のファイルが単ページ属性か
    private var isRightFileForcedSingle: Bool {
        if isRightToLeft {
            return isCurrentPageUserForcedSingle
        } else {
            return isSecondPageUserForcedSingle
        }
    }

    /// ページ情報表示（単ページ属性付きファイルは色を変える）
    @ViewBuilder
    private var pageInfoView: some View {
        if isSpreadView && hasSecondPage {
            // 見開き表示
            HStack(spacing: 0) {
                Text("#\(currentPage + 1)-\(currentPage + 2)/\(totalPages) (")
                    .foregroundColor(.white)
                Text(leftFileName)
                    .foregroundColor(isLeftFileForcedSingle ? .orange : .white)
                Text(" | ")
                    .foregroundColor(.white)
                Text(rightFileName)
                    .foregroundColor(isRightFileForcedSingle ? .orange : .white)
                Text(")")
                    .foregroundColor(.white)
            }
        } else {
            // 単ページ表示
            HStack(spacing: 0) {
                Text("#\(currentPage + 1)/\(totalPages) (")
                    .foregroundColor(.white)
                Text(currentFileName)
                    .foregroundColor(isCurrentPageUserForcedSingle ? .orange : .white)
                Text(")")
                    .foregroundColor(.white)
            }
        }
    }

    /// プログレスバーの幅を計算
    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard totalPages > 0 else { return 0 }
        let progress = CGFloat(currentPage + 1) / CGFloat(totalPages)
        return totalWidth * progress
    }

    /// 位置からページ番号を計算
    private func pageForPosition(_ x: CGFloat) -> Int {
        guard totalPages > 0 else { return 0 }

        // 右→左読みの場合、クリック位置の解釈を反転
        let adjustedX = isRightToLeft ? (barFixedWidth - x) : x
        let ratio = max(0, min(1, adjustedX / barFixedWidth))
        let page = Int(ratio * CGFloat(totalPages - 1))
        return max(0, min(totalPages - 1, page))
    }

    /// ツールチップのテキスト
    private func tooltipText(for page: Int) -> String {
        return "\(page + 1) / \(totalPages)"
    }
}

extension View {
    /// ページインジケーターオーバーレイを追加
    func pageIndicatorOverlay(
        archiveName: String,
        currentPage: Int,
        totalPages: Int,
        isSpreadView: Bool,
        hasSecondPage: Bool,
        currentFileName: String,
        secondFileName: String? = nil,
        isCurrentPageUserForcedSingle: Bool = false,
        isSecondPageUserForcedSingle: Bool = false,
        readingDirection: ReadingDirection,
        onJumpToPage: @escaping (Int) -> Void
    ) -> some View {
        modifier(PageIndicatorModifier(
            archiveName: archiveName,
            currentPage: currentPage,
            totalPages: totalPages,
            isSpreadView: isSpreadView,
            hasSecondPage: hasSecondPage,
            currentFileName: currentFileName,
            secondFileName: secondFileName,
            isCurrentPageUserForcedSingle: isCurrentPageUserForcedSingle,
            isSecondPageUserForcedSingle: isSecondPageUserForcedSingle,
            readingDirection: readingDirection,
            onJumpToPage: onJumpToPage
        ))
    }
}
