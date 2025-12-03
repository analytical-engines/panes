import SwiftUI

/// 画像情報を表すデータ構造
struct ImageInfo {
    let fileName: String
    let width: Int
    let height: Int
    let fileSize: Int64
    let format: String
    let pageIndex: Int

    /// アスペクト比（幅/高さ）
    var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    /// フォーマット済みの解像度文字列
    var resolutionString: String {
        return "\(width) × \(height)"
    }

    /// フォーマット済みのファイルサイズ文字列
    var fileSizeString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// フォーマット済みのアスペクト比文字列
    var aspectRatioString: String {
        return String(format: "%.2f", aspectRatio)
    }
}

/// 画像情報モーダルビュー
struct ImageInfoView: View {
    let infos: [ImageInfo]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // ヘッダー
            HStack {
                Text(L("image_info_title"))
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.bottom, 8)

            // 画像情報
            if infos.count == 1 {
                // 単ページ
                singleImageInfo(infos[0])
            } else if infos.count == 2 {
                // 見開き
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading) {
                        Text(L("image_info_right_page"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        singleImageInfo(infos[0])
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    VStack(alignment: .leading) {
                        Text(L("image_info_left_page"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        singleImageInfo(infos[1])
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: infos.count == 2 ? 500 : 300, height: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
    }

    @ViewBuilder
    private func singleImageInfo(_ info: ImageInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(L("image_info_filename"), info.fileName)
            infoRow(L("image_info_page"), "\(info.pageIndex + 1)")
            infoRow(L("image_info_resolution"), info.resolutionString)
            infoRow(L("image_info_aspect_ratio"), info.aspectRatioString)
            infoRow(L("image_info_file_size"), info.fileSizeString)
            infoRow(L("image_info_format"), info.format)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(.body, design: .monospaced))
    }
}
