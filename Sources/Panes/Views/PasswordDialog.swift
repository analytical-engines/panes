import SwiftUI

/// パスワード入力ダイアログ
struct PasswordDialog: View {
    let fileName: String
    let errorMessage: String?
    let onSubmit: (String, Bool) -> Void  // (password, shouldSave)
    let onCancel: () -> Void

    @State private var password: String = ""
    @State private var shouldSavePassword: Bool = true
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // タイトル
            Text(L("password_dialog_title"))
                .font(.headline)

            // 説明
            Text(L("password_dialog_message"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            // ファイル名
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                Text(fileName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // パスワード入力
            SecureField(L("password_dialog_placeholder"), text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    submitIfValid()
                }

            // エラーメッセージ
            if let errorMessage = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            // パスワード保存オプション
            Toggle(isOn: $shouldSavePassword) {
                Text(L("password_dialog_remember"))
            }
            .toggleStyle(.checkbox)

            Divider()

            // ボタン
            HStack {
                Spacer()
                Button(L("password_dialog_cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(L("password_dialog_open")) {
                    submitIfValid()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(password.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .colorScheme(.dark)  // ダークモードを強制してスタイル変化を防止
        .onAppear {
            isFocused = true
        }
    }

    private func submitIfValid() {
        guard !password.isEmpty else { return }
        onSubmit(password, shouldSavePassword)
    }
}
