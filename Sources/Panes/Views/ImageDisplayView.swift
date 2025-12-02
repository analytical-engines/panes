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

    var body: some View {
        GeometryReader { geometry in
            RotationAwareImageView(
                image: image,
                rotation: rotation,
                flip: flip,
                containerWidth: geometry.size.width,
                containerHeight: geometry.size.height
            )
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
        let scale = min(scaleX, scaleY)

        // フィット後のサイズ
        let fittedWidth = imageWidth * scale
        let fittedHeight = imageHeight * scale

        Image(nsImage: image)
            .resizable()
            .frame(width: fittedWidth, height: fittedHeight)
            .scaleEffect(
                x: flip.horizontal ? -1 : 1,
                y: flip.vertical ? -1 : 1
            )
            .rotationEffect(.degrees(Double(rotation.rawValue)))
            .frame(width: containerWidth, height: containerHeight, alignment: alignment)
    }
}
