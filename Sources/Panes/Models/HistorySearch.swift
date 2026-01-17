import Foundation

/// 検索対象の種別
enum SearchTargetType: String, CaseIterable {
    case all = "all"                    // すべて
    case archive = "archive"            // 書庫ファイルのみ
    case image = "image"                // 画像ファイルのみ
    case standalone = "standalone"      // 個別画像のみ
    case content = "content"            // 書庫/フォルダ内画像のみ
    case session = "session"            // セッションのみ
}

/// パース済みの検索クエリ
struct ParsedSearchQuery {
    /// 検索対象の種別
    let targetType: SearchTargetType
    /// 検索キーワード（メタキーワードを除いたテキスト）
    let keyword: String
    /// 元のクエリ文字列
    let originalQuery: String

    /// キーワードが空かどうか
    var hasKeyword: Bool {
        !keyword.isEmpty
    }

    /// 書庫を検索対象に含むか
    var includesArchives: Bool {
        switch targetType {
        case .all, .archive:
            return true
        case .image, .standalone, .content, .session:
            return false
        }
    }

    /// 画像を検索対象に含むか
    var includesImages: Bool {
        switch targetType {
        case .all, .image, .standalone, .content:
            return true
        case .archive, .session:
            return false
        }
    }

    /// 個別画像を検索対象に含むか
    var includesStandalone: Bool {
        switch targetType {
        case .all, .image, .standalone:
            return true
        case .archive, .content, .session:
            return false
        }
    }

    /// 書庫/フォルダ内画像を検索対象に含むか
    var includesArchiveContent: Bool {
        switch targetType {
        case .all, .image, .content:
            return true
        case .archive, .standalone, .session:
            return false
        }
    }

    /// セッションを検索対象に含むか
    var includesSessions: Bool {
        switch targetType {
        case .all, .session:
            return true
        case .archive, .image, .standalone, .content:
            return false
        }
    }
}

/// 履歴検索のユーティリティ
enum HistorySearchParser {
    /// メタキーワードのプレフィックス
    private static let typePrefix = "type:"

    /// サポートされるtype:の値
    private static let supportedTypes: [String: SearchTargetType] = [
        "all": .all,
        "archive": .archive,
        "archives": .archive,
        "image": .image,
        "images": .image,
        "standalone": .standalone,
        "content": .content,
        "archived": .content,
        "session": .session,
        "sessions": .session
    ]

    /// 検索クエリをパースする
    /// - Parameters:
    ///   - query: ユーザー入力のクエリ文字列
    ///   - defaultType: type:が指定されていない場合のデフォルトタイプ
    /// - Returns: パース済みの検索クエリ
    ///
    /// 引用符（シングル・ダブル）で囲まれた部分はフレーズとして扱われ、
    /// 空白を含むキーワードやメタキーワードのエスケープに使用できます。
    /// 例: `"My Comic"` → 「My Comic」を検索
    /// 例: `'type:archive'` → 「type:archive」という文字列を検索
    static func parse(_ query: String, defaultType: SearchTargetType = .archive) -> ParsedSearchQuery {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return ParsedSearchQuery(targetType: defaultType, keyword: "", originalQuery: query)
        }

        // 引用符を考慮してトークン化
        let tokens = tokenize(trimmed)

        // type:キーワードを探す
        var targetType: SearchTargetType = defaultType
        var keywordTokens: [String] = []

        for token in tokens {
            // 引用符で囲まれたトークンはメタキーワードとして解釈しない
            if token.isQuoted {
                keywordTokens.append(token.value)
            } else if token.value.lowercased().hasPrefix(typePrefix) {
                let typeValue = String(token.value.dropFirst(typePrefix.count)).lowercased()
                if let type = supportedTypes[typeValue] {
                    targetType = type
                    continue
                }
                // 無効なtype:はキーワードとして扱う
                keywordTokens.append(token.value)
            } else if !token.value.isEmpty {
                keywordTokens.append(token.value)
            }
        }

        let remainingKeyword = keywordTokens.joined(separator: " ")

        return ParsedSearchQuery(
            targetType: targetType,
            keyword: remainingKeyword,
            originalQuery: query
        )
    }

    /// トークンを表す構造体
    private struct Token {
        let value: String
        let isQuoted: Bool
    }

    /// クエリ文字列をトークン化（引用符・エスケープを考慮）
    /// - シングルクォート・ダブルクォートで囲まれた部分は1つのトークンとして扱う
    /// - バックスラッシュでエスケープ: \" \' \\ \  (空白)
    private static func tokenize(_ query: String) -> [Token] {
        var tokens: [Token] = []
        var currentToken = ""
        var inQuote: Character? = nil
        var isEscaped = false
        var iterator = query.makeIterator()

        while let char = iterator.next() {
            if isEscaped {
                // エスケープされた文字をそのまま追加
                currentToken.append(char)
                isEscaped = false
                continue
            }

            if char == "\\" {
                // エスケープ開始
                isEscaped = true
                continue
            }

            if inQuote != nil {
                // 引用符内
                if char == inQuote {
                    // 引用符の終わり
                    tokens.append(Token(value: currentToken, isQuoted: true))
                    currentToken = ""
                    inQuote = nil
                } else {
                    currentToken.append(char)
                }
            } else {
                // 引用符外
                if char == "\"" || char == "'" {
                    // 引用符の開始
                    if !currentToken.isEmpty {
                        tokens.append(Token(value: currentToken, isQuoted: false))
                        currentToken = ""
                    }
                    inQuote = char
                } else if char.isWhitespace {
                    // 空白区切り
                    if !currentToken.isEmpty {
                        tokens.append(Token(value: currentToken, isQuoted: false))
                        currentToken = ""
                    }
                } else {
                    currentToken.append(char)
                }
            }
        }

        // エスケープ文字が最後に残った場合はバックスラッシュとして追加
        if isEscaped {
            currentToken.append("\\")
        }

        // 残りのトークンを追加
        if !currentToken.isEmpty {
            // 閉じられていない引用符の場合も追加
            tokens.append(Token(value: currentToken, isQuoted: inQuote != nil))
        }

        return tokens
    }
}

/// 統合検索結果
struct UnifiedSearchResult {
    /// マッチした書庫エントリ
    let archives: [FileHistoryEntry]
    /// マッチした画像エントリ
    let images: [ImageCatalogEntry]
    /// マッチしたセッショングループ
    let sessions: [SessionGroup]
    /// 検索に使用したクエリ
    let query: ParsedSearchQuery

    /// 総件数
    var totalCount: Int {
        archives.count + images.count + sessions.count
    }

    /// 結果が空かどうか
    var isEmpty: Bool {
        archives.isEmpty && images.isEmpty && sessions.isEmpty
    }
}

/// 統合検索フィルター
enum UnifiedSearchFilter {
    /// 書庫エントリがクエリにマッチするかチェック
    static func matches(_ entry: FileHistoryEntry, query: ParsedSearchQuery) -> Bool {
        guard query.includesArchives else { return false }
        guard query.hasKeyword else { return true }

        return matchesKeyword(entry.fileName, keyword: query.keyword) ||
               matchesKeyword(entry.memo, keyword: query.keyword)
    }

    /// 画像カタログエントリがクエリにマッチするかチェック
    /// - Parameters:
    ///   - entry: 画像カタログエントリ
    ///   - query: パース済みクエリ
    ///   - parentArchive: 書庫内画像の場合、親書庫のエントリ（親書庫名・メモも検索対象にする）
    static func matches(_ entry: ImageCatalogEntry, query: ParsedSearchQuery, parentArchive: FileHistoryEntry? = nil) -> Bool {
        guard query.includesImages else { return false }

        // 画像種別でフィルタ
        switch entry.catalogType {
        case .standalone:
            guard query.includesStandalone else { return false }
        case .archiveContent:
            guard query.includesArchiveContent else { return false }
        }

        guard query.hasKeyword else { return true }

        // 画像自体のファイル名・メモで検索
        if matchesKeyword(entry.fileName, keyword: query.keyword) ||
           matchesKeyword(entry.memo, keyword: query.keyword) {
            return true
        }

        // 書庫内画像の場合、親書庫の情報も検索対象
        if entry.catalogType == .archiveContent {
            // 親書庫のファイル名（filePathから取得）
            let parentFileName = (entry.filePath as NSString).lastPathComponent
            if matchesKeyword(parentFileName, keyword: query.keyword) {
                return true
            }

            // 親書庫のメモ（FileHistoryEntryから取得）
            if let parent = parentArchive {
                if matchesKeyword(parent.memo, keyword: query.keyword) {
                    return true
                }
            }
        }

        return false
    }

    /// キーワードマッチング（ワイルドカード対応）
    private static func matchesKeyword(_ text: String?, keyword: String) -> Bool {
        guard let text = text, !text.isEmpty else { return false }

        // ワイルドカード文字が含まれている場合は正規表現として処理
        if keyword.contains("*") || keyword.contains("?") {
            let regexPattern = wildcardToRegex(keyword)
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
        }

        // 通常の部分一致検索
        return text.localizedCaseInsensitiveContains(keyword)
    }

    /// ワイルドカードパターンを正規表現に変換
    private static func wildcardToRegex(_ pattern: String) -> String {
        var result = NSRegularExpression.escapedPattern(for: pattern)
        result = result.replacingOccurrences(of: "\\*", with: ".*")
        result = result.replacingOccurrences(of: "\\?", with: ".")
        return result
    }

    /// セッショングループがクエリにマッチするかチェック
    static func matches(_ group: SessionGroup, query: ParsedSearchQuery) -> Bool {
        guard query.includesSessions else { return false }
        guard query.hasKeyword else { return true }

        // セッション名で検索
        if matchesKeyword(group.name, keyword: query.keyword) {
            return true
        }

        // ファイル名で検索
        for entry in group.entries {
            if matchesKeyword(entry.fileName, keyword: query.keyword) {
                return true
            }
        }

        return false
    }

    /// 統合検索を実行
    static func search(
        query: ParsedSearchQuery,
        archives: [FileHistoryEntry],
        images: [ImageCatalogEntry],
        sessions: [SessionGroup] = []
    ) -> UnifiedSearchResult {
        // 書庫パスからFileHistoryEntryへのマッピングを作成（高速検索用）
        // 重複キーがある場合は最初のエントリを使用
        let archivesByPath = Dictionary(archives.map { ($0.filePath, $0) }, uniquingKeysWith: { first, _ in first })

        let filteredArchives = archives.filter { matches($0, query: query) }
        let filteredImages = images.filter { entry in
            // 書庫内画像の場合、親書庫のエントリを取得
            let parentArchive: FileHistoryEntry? = entry.catalogType == .archiveContent
                ? archivesByPath[entry.filePath]
                : nil
            return matches(entry, query: query, parentArchive: parentArchive)
        }
        let filteredSessions = sessions.filter { matches($0, query: query) }

        return UnifiedSearchResult(
            archives: filteredArchives,
            images: filteredImages,
            sessions: filteredSessions,
            query: query
        )
    }
}
