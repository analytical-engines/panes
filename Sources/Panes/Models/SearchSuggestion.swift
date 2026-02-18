import Foundation

// MARK: - SearchSuggestionProvider

/// 検索サジェストを提供するプロトコル
protocol SearchSuggestionProvider: Sendable {
    /// トリガーとなるプレフィックス（例: "type:", "is:"）
    var triggerPrefix: String { get }

    /// 指定されたトークンに対するサジェスト候補を返す
    /// - Parameter token: 現在入力中のトークン（例: "type:arc"）
    /// - Returns: マッチする候補のリスト（末尾にスペース付き）
    func suggestions(for token: String) -> [String]
}

// MARK: - TypeFilterSuggestionProvider

/// `type:` フィルターのサジェストプロバイダー
struct TypeFilterSuggestionProvider: SearchSuggestionProvider {
    let triggerPrefix = "type:"

    private let values = ["archive", "individual", "archived", "session"]

    func suggestions(for token: String) -> [String] {
        guard token.lowercased().hasPrefix(triggerPrefix) else { return [] }
        let partial = String(token.dropFirst(triggerPrefix.count))
        return SearchSuggestionEngine.prefixMatch(values, query: partial)
            .map { "\(triggerPrefix)\($0) " }
    }
}

// MARK: - IsFilterSuggestionProvider

/// `is:` フィルターのサジェストプロバイダー
struct IsFilterSuggestionProvider: SearchSuggestionProvider {
    let triggerPrefix = "is:"

    private let values = ["locked"]

    func suggestions(for token: String) -> [String] {
        guard token.lowercased().hasPrefix(triggerPrefix) else { return [] }
        let partial = String(token.dropFirst(triggerPrefix.count))
        return SearchSuggestionEngine.prefixMatch(values, query: partial)
            .map { "\(triggerPrefix)\($0) " }
    }
}

// MARK: - TagSuggestionProvider

/// `#tag` サジェストプロバイダー（動的：メモから収集したタグを候補にする）
struct TagSuggestionProvider: SearchSuggestionProvider {
    let triggerPrefix = "#"
    let availableTags: Set<String>

    func suggestions(for token: String) -> [String] {
        guard token.hasPrefix("#") else { return [] }
        let partial = String(token.dropFirst())
        return SearchSuggestionEngine.prefixMatch(availableTags, query: partial)
            .map { "#\($0) " }
    }
}

// MARK: - NegatedTagSuggestionProvider

/// `!#tag` サジェストプロバイダー（否定タグ検索）
struct NegatedTagSuggestionProvider: SearchSuggestionProvider {
    let triggerPrefix = "!#"
    let availableTags: Set<String>

    func suggestions(for token: String) -> [String] {
        guard token.hasPrefix("!#") else { return [] }
        let partial = String(token.dropFirst(2))
        return SearchSuggestionEngine.prefixMatch(availableTags, query: partial)
            .map { "!#\($0) " }
    }
}

// MARK: - NegatedMetadataKeySuggestionProvider

/// `!@key` サジェストプロバイダー（否定メタデータキー検索）
struct NegatedMetadataKeySuggestionProvider: SearchSuggestionProvider {
    let triggerPrefix = "!@"
    let availableKeys: Set<String>

    func suggestions(for token: String) -> [String] {
        guard token.hasPrefix("!@") else { return [] }
        let partial = String(token.dropFirst(2))
        return SearchSuggestionEngine.prefixMatch(availableKeys, query: partial)
            .map { "!@\($0) " }
    }
}

// MARK: - MetadataKeySuggestionProvider

/// `@key` サジェストプロバイダー（動的：メモから収集したキーを候補にする）
struct MetadataKeySuggestionProvider: SearchSuggestionProvider {
    let triggerPrefix = "@"
    let availableKeys: Set<String>

    func suggestions(for token: String) -> [String] {
        guard token.hasPrefix("@") else { return [] }
        let partial = String(token.dropFirst())
        return SearchSuggestionEngine.prefixMatch(availableKeys, query: partial)
            .map { "@\($0)=" }
    }
}

// MARK: - MetadataValueSuggestionProvider

/// `@key=value` サジェストプロバイダー（動的：メモから収集した値を候補にする）
struct MetadataValueSuggestionProvider: SearchSuggestionProvider {
    let key: String
    var triggerPrefix: String { "@\(key)=" }
    let availableValues: Set<String>

    func suggestions(for token: String) -> [String] {
        let prefix = "@\(key)="
        guard token.lowercased().hasPrefix(prefix) else { return [] }
        let partial = String(token.dropFirst(prefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return SearchSuggestionEngine.prefixMatch(availableValues, query: partial)
            .map { $0.contains(" ") ? "@\(key)=\"\($0)\" " : "@\(key)=\($0) " }
    }
}

// MARK: - Memo-specific providers (colon separator)

/// メモ用 `@key:` サジェストプロバイダー
struct MemoMetadataKeySuggestionProvider: SearchSuggestionProvider {
    let triggerPrefix = "@"
    let availableKeys: Set<String>

    func suggestions(for token: String) -> [String] {
        guard token.hasPrefix("@") else { return [] }
        let partial = String(token.dropFirst())
        return SearchSuggestionEngine.prefixMatch(availableKeys, query: partial)
            .map { "@\($0):" }
    }
}

/// メモ用 `@key:value` サジェストプロバイダー
struct MemoMetadataValueSuggestionProvider: SearchSuggestionProvider {
    let key: String
    var triggerPrefix: String { "@\(key):" }
    let availableValues: Set<String>

    func suggestions(for token: String) -> [String] {
        let prefix = "@\(key):"
        guard token.lowercased().hasPrefix(prefix) else { return [] }
        let partial = String(token.dropFirst(prefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return SearchSuggestionEngine.prefixMatch(availableValues, query: partial)
            .map { $0.contains(" ") ? "@\(key):\"\($0)\" " : "@\(key):\($0) " }
    }
}

// MARK: - SearchSuggestionItem

/// サジェスト候補（表示テキストと適用テキストを分離）
struct SearchSuggestionItem: Equatable {
    /// ドロップダウンに表示するテキスト（例: "archive"）
    let displayText: String
    /// 選択時にクエリに適用する完全な文字列（例: "ある type:archive "）
    let fullText: String
    /// ドロップダウン位置合わせ用のスペーサーテキスト（例: "ある type:"）
    let alignmentPrefix: String
}

// MARK: - SearchSuggestionEngine

/// 検索サジェストエンジン（静的メソッド群）
enum SearchSuggestionEngine {

    /// 前方一致フィルタ＋ソート（全プロバイダー・構造化エディタ共通）
    static func prefixMatch(_ candidates: some Collection<String>, query: String) -> [String] {
        let q = query.lowercased()
        return candidates
            .filter { q.isEmpty || $0.lowercased().hasPrefix(q) }
            .sorted()
    }

    /// デフォルトのプロバイダー一覧
    private static let defaultProviders: [any SearchSuggestionProvider] = [
        TypeFilterSuggestionProvider(),
        IsFilterSuggestionProvider()
    ]

    /// クエリを「前半 + 現在入力中トークン」に分割する
    /// 最後のスペースで分割し、それ以降を現在のトークンとする
    /// - Parameter query: 検索クエリ全体
    /// - Returns: (prefix: スペース含む前半部分, currentToken: 現在入力中のトークン)
    static func splitAtCurrentToken(_ query: String) -> (prefix: String, currentToken: String) {
        guard let lastSpaceIndex = query.lastIndex(of: " ") else {
            return (prefix: "", currentToken: query)
        }
        let afterSpace = query.index(after: lastSpaceIndex)
        let prefix = String(query[...lastSpaceIndex])
        let currentToken = String(query[afterSpace...])
        return (prefix: prefix, currentToken: currentToken)
    }

    /// 現在のクエリに対するサジェスト候補を計算する（デフォルトプロバイダー使用）
    static func computeSuggestions(for query: String) -> [SearchSuggestionItem] {
        computeSuggestions(for: query, providers: defaultProviders)
    }

    /// 現在のクエリに対するサジェスト候補を計算する
    static func computeSuggestions(
        for query: String,
        providers: [any SearchSuggestionProvider]
    ) -> [SearchSuggestionItem] {
        guard !query.isEmpty else { return [] }

        let (prefix, currentToken) = splitAtCurrentToken(query)
        guard !currentToken.isEmpty else { return [] }

        for provider in providers {
            let results = provider.suggestions(for: currentToken)
            if !results.isEmpty {
                let triggerPrefix = provider.triggerPrefix
                return results.map { tokenSuggestion in
                    // "type:archive " → "archive", '@key="John Doe" ' → "John Doe"
                    let value = tokenSuggestion
                        .trimmingSuffix(" ")
                        .removingPrefix(triggerPrefix)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return SearchSuggestionItem(
                        displayText: value,
                        fullText: prefix + tokenSuggestion,
                        alignmentPrefix: prefix + triggerPrefix
                    )
                }
            }
        }

        return []
    }

    /// ゴーストテキスト用のインライン補完文字列を取得する
    static func inlineCompletion(for query: String, suggestion: SearchSuggestionItem) -> String? {
        guard !query.isEmpty else { return nil }

        let fullText = suggestion.fullText
        if fullText.lowercased().hasPrefix(query.lowercased()) {
            let remaining = String(fullText.dropFirst(query.count))
            return remaining.isEmpty ? nil : remaining
        }

        return nil
    }
}

// MARK: - String helpers

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(dropLast(suffix.count))
        }
        return self
    }

    func removingPrefix(_ prefix: String) -> String {
        if lowercased().hasPrefix(prefix.lowercased()) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}
