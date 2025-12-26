import Foundation
import Security
import CryptoKit

/// アーカイブファイルのパスワードをKeychainに保存・取得するクラス
final class PasswordStorage: Sendable {
    static let shared = PasswordStorage()

    private let service = "com.panes.archive-passwords"

    private init() {}

    /// パスワードを保存
    /// - Parameters:
    ///   - password: 保存するパスワード
    ///   - path: アーカイブファイルのパス
    func savePassword(_ password: String, forArchive path: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw PasswordStorageError.encodingFailed
        }

        let account = hashPath(path)

        // 既存のパスワードを削除
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 新しいパスワードを追加
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PasswordStorageError.saveFailed(status)
        }
    }

    /// パスワードを取得
    /// - Parameter path: アーカイブファイルのパス
    /// - Returns: 保存されているパスワード、なければnil
    func getPassword(forArchive path: String) -> String? {
        let account = hashPath(path)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    /// パスワードを削除
    /// - Parameter path: アーカイブファイルのパス
    func deletePassword(forArchive path: String) throws {
        let account = hashPath(path)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasswordStorageError.deleteFailed(status)
        }
    }

    /// ファイルパスをハッシュ化してキーとして使用
    private func hashPath(_ path: String) -> String {
        // ファイルパスが長すぎる場合に備えてSHA256でハッシュ化
        guard let data = path.data(using: .utf8) else {
            return path
        }

        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

enum PasswordStorageError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode password"
        case .saveFailed(let status):
            return "Failed to save password: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete password: \(status)"
        }
    }
}
