import SwiftUI
import AppKit

/// 画像変換用のView Modifier（フレームサイズ指定なし）
struct ImageTransformModifier: ViewModifier {
    let rotation: ImageRotation
    let flip: ImageFlip

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                x: flip.horizontal ? -1 : 1,
                y: flip.vertical ? -1 : 1
            )
            .rotationEffect(.degrees(Double(rotation.rawValue)))
    }
}

/// 画像変換用のView Modifier（フレームサイズ指定あり - 回転時のフィッティング補正付き）
struct ImageTransformWithFrameModifier: ViewModifier {
    let rotation: ImageRotation
    let flip: ImageFlip
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    func body(content: Content) -> some View {
        // 90°/270°回転時はフレームサイズを入れ替えてフィッティング計算
        let effectiveFrameWidth = rotation.swapsAspectRatio ? frameHeight : frameWidth
        let effectiveFrameHeight = rotation.swapsAspectRatio ? frameWidth : frameHeight

        content
            .frame(width: effectiveFrameWidth, height: effectiveFrameHeight)
            .scaleEffect(
                x: flip.horizontal ? -1 : 1,
                y: flip.vertical ? -1 : 1
            )
            .rotationEffect(.degrees(Double(rotation.rawValue)))
            .frame(width: frameWidth, height: frameHeight)
    }
}

extension View {
    /// 画像の回転・反転変換を適用
    func imageTransform(rotation: ImageRotation, flip: ImageFlip) -> some View {
        modifier(ImageTransformModifier(rotation: rotation, flip: flip))
    }

    /// 画像の回転・反転変換を適用（フレームサイズ指定 - 回転時のフィッティング補正付き）
    func imageTransform(rotation: ImageRotation, flip: ImageFlip, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        modifier(ImageTransformWithFrameModifier(rotation: rotation, flip: flip, frameWidth: frameWidth, frameHeight: frameHeight))
    }
}

/// 画像を表示するビュー（回転対応）
struct ImageDisplayView: View {
    let image: NSImage
    var rotation: ImageRotation = .none
    var flip: ImageFlip = .none
    var fittingMode: FittingMode = .window
    /// ScrollView内で使用する場合に外部から渡すビューポートサイズ
    var viewportSize: CGSize? = nil

    var body: some View {
        if let viewport = viewportSize {
            // ビューポートサイズが指定されている場合（ScrollView内）
            RotationAwareImageView(
                image: image,
                rotation: rotation,
                flip: flip,
                containerWidth: viewport.width,
                containerHeight: viewport.height,
                fittingMode: fittingMode
            )
        } else {
            // 通常の場合（GeometryReaderでサイズ取得）
            GeometryReader { geometry in
                RotationAwareImageView(
                    image: image,
                    rotation: rotation,
                    flip: flip,
                    containerWidth: geometry.size.width,
                    containerHeight: geometry.size.height,
                    fittingMode: fittingMode
                )
            }
        }
    }
}

/// 回転対応の画像ビュー（ウィンドウフィッティング対応）
/// 90°/270°回転時に正しくウィンドウにフィットする
struct RotationAwareImageView: View {
    let image: NSImage
    let rotation: ImageRotation
    let flip: ImageFlip
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    var alignment: Alignment = .center
    var fittingMode: FittingMode = .window

    var body: some View {
        // 回転後の実効コンテナサイズを計算
        let effectiveContainerWidth = rotation.swapsAspectRatio ? containerHeight : containerWidth
        let effectiveContainerHeight = rotation.swapsAspectRatio ? containerWidth : containerHeight

        // 画像のアスペクト比を計算
        let imageWidth = image.size.width
        let imageHeight = image.size.height

        // 実効コンテナにフィットするスケールを計算
        let scaleX = effectiveContainerWidth / imageWidth
        let scaleY = effectiveContainerHeight / imageHeight

        // フィッティングモードに応じてスケールを決定
        let scale: CGFloat = {
            switch fittingMode {
            case .window:
                return min(scaleX, scaleY)
            case .height:
                return scaleY
            case .width:
                return scaleX
            case .originalSize:
                return 1.0  // 等倍表示（1:1ピクセル）
            }
        }()

        // フィット後のサイズ
        let fittedWidth = imageWidth * scale
        let fittedHeight = imageHeight * scale

        // 回転後の視覚的なサイズ
        let visualWidth = rotation.swapsAspectRatio ? fittedHeight : fittedWidth
        let visualHeight = rotation.swapsAspectRatio ? fittedWidth : fittedHeight

        // フレームサイズ（フィッティングモードに応じて変更）
        let frameWidth: CGFloat = {
            switch fittingMode {
            case .window:
                return containerWidth
            case .height:
                // 縦フィット時は視覚的な幅をフレーム幅とする（はみ出し許可）
                return max(visualWidth, containerWidth)
            case .width:
                return containerWidth
            case .originalSize:
                // 等倍表示時は視覚的な幅をフレーム幅とする（はみ出し許可）
                return max(visualWidth, containerWidth)
            }
        }()

        let frameHeight: CGFloat = {
            switch fittingMode {
            case .window:
                return containerHeight
            case .height:
                return containerHeight
            case .width:
                // 横フィット時は視覚的な高さをフレーム高さとする（はみ出し許可）
                return max(visualHeight, containerHeight)
            case .originalSize:
                // 等倍表示時は視覚的な高さをフレーム高さとする（はみ出し許可）
                return max(visualHeight, containerHeight)
            }
        }()

        // 回転時のアライメント補正オフセット
        // 90°/270°回転すると視覚的な幅と高さが入れ替わるが、
        // SwiftUIのアライメントは回転前のフレームに基づくため補正が必要
        let alignmentOffsetX: CGFloat = {
            guard rotation.swapsAspectRatio else { return 0 }
            // 視覚的な幅 = fittedHeight（回転で入れ替わる）
            // レイアウト幅 = fittedWidth
            switch alignment {
            case .leading, .topLeading, .bottomLeading:
                // 視覚的な左端をコンテナ左端に合わせる
                return (fittedHeight - fittedWidth) / 2
            case .trailing, .topTrailing, .bottomTrailing:
                // 視覚的な右端をコンテナ右端に合わせる
                return (fittedWidth - fittedHeight) / 2
            default:
                return 0
            }
        }()

        Image(nsImage: image)
            .resizable()
            .frame(width: fittedWidth, height: fittedHeight)
            .scaleEffect(
                x: flip.horizontal ? -1 : 1,
                y: flip.vertical ? -1 : 1
            )
            .rotationEffect(.degrees(Double(rotation.rawValue)))
            .offset(x: alignmentOffsetX)
            .frame(width: frameWidth, height: frameHeight, alignment: alignment)
    }
}
