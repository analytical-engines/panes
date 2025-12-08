import SwiftUI

/// ファイル同一性確認ダイアログ
struct FileIdentityDialog: View {
    let existingFileName: String
    let newFileName: String
    let onChoice: (FileIdentityChoice?) -> Void  // nil = キャンセル

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // タイトル
            Text(L("file_identity_title"))
                .font(.headline)

            // 説明
            Text(L("file_identity_message"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            // ファイル名の比較
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(L("file_identity_existing_file"))
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .trailing)
                    Text(existingFileName)
                        .fontWeight(.medium)
                }

                HStack(alignment: .top) {
                    Text(L("file_identity_new_file"))
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .trailing)
                    Text(newFileName)
                        .fontWeight(.medium)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Divider()

            // 選択肢
            VStack(spacing: 8) {
                ChoiceButton(
                    title: L("file_identity_treat_as_same"),
                    description: L("file_identity_treat_as_same_description"),
                    action: { onChoice(.treatAsSame) }
                )

                ChoiceButton(
                    title: L("file_identity_copy_settings"),
                    description: L("file_identity_copy_settings_description"),
                    action: { onChoice(.copySettings) }
                )

                ChoiceButton(
                    title: L("file_identity_treat_as_different"),
                    description: L("file_identity_treat_as_different_description"),
                    action: { onChoice(.treatAsDifferent) }
                )
            }

            Divider()

            // キャンセルボタン
            HStack {
                Spacer()
                Button(L("cancel")) {
                    onChoice(nil)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

/// 選択肢ボタン
private struct ChoiceButton: View {
    let title: String
    let description: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isHovering ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
