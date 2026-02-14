import Foundation

/// メモテキストから構造化メタデータを抽出するパーサー
enum MemoMetadataParser {
    /// パース結果
    struct MemoMetadata {
        /// @key:value 属性（キーは小文字正規化）
        let attributes: [String: String]
        /// #tag タグ（小文字正規化）
        let tags: Set<String>
        /// メタデータを除いた表示用テキスト
        let plainText: String
    }

    /// 空のメタデータ
    static let empty = MemoMetadata(attributes: [:], tags: [], plainText: "")

    // MARK: - Regex patterns

    /// @key:value パターン（行頭または空白の後）
    private static let attributeRegex = try! NSRegularExpression(
        pattern: #"(?:^|(?<=\s))@([a-zA-Z0-9_]+):(\S+)"#
    )

    /// #tagname パターン（行頭または空白の後）
    private static let tagRegex = try! NSRegularExpression(
        pattern: #"(?:^|(?<=\s))#([a-zA-Z0-9_]+)"#
    )

    /// メモテキストからメタデータを抽出する
    static func parse(_ memo: String?) -> MemoMetadata {
        guard let memo = memo, !memo.isEmpty else {
            return empty
        }

        let fullRange = NSRange(memo.startIndex..., in: memo)
        var attributes: [String: String] = [:]
        var tags: Set<String> = []
        var removalRanges: [Range<String.Index>] = []

        // @key:value を抽出
        let attrMatches = attributeRegex.matches(in: memo, range: fullRange)
        for match in attrMatches {
            guard let keyRange = Range(match.range(at: 1), in: memo),
                  let valueRange = Range(match.range(at: 2), in: memo),
                  let matchRange = Range(match.range, in: memo) else { continue }
            let key = String(memo[keyRange]).lowercased()
            let value = String(memo[valueRange])
            attributes[key] = value
            removalRanges.append(matchRange)
        }

        // #tagname を抽出
        let tagMatches = tagRegex.matches(in: memo, range: fullRange)
        for match in tagMatches {
            guard let tagRange = Range(match.range(at: 1), in: memo),
                  let matchRange = Range(match.range, in: memo) else { continue }
            tags.insert(String(memo[tagRange]).lowercased())
            removalRanges.append(matchRange)
        }

        // メタデータ部分を除去してプレーンテキストを生成
        let plainText = removeRanges(from: memo, ranges: removalRanges)

        return MemoMetadata(attributes: attributes, tags: tags, plainText: plainText)
    }

    // MARK: - Index collection

    /// メタデータインデックス（使用中のタグ・キー・値の集合）
    struct MetadataIndex {
        let tags: Set<String>
        let keys: Set<String>
        let values: [String: Set<String>]
    }

    /// 複数メモからタグ・キー・値を一括収集する
    static func collectIndex(from memos: [String?]) -> MetadataIndex {
        var tags = Set<String>()
        var keys = Set<String>()
        var values: [String: Set<String>] = [:]

        for memo in memos {
            guard let memo = memo, !memo.isEmpty else { continue }
            let parsed = parse(memo)
            tags.formUnion(parsed.tags)
            keys.formUnion(parsed.attributes.keys)
            for (key, value) in parsed.attributes {
                values[key, default: []].insert(value)
            }
        }

        return MetadataIndex(tags: tags, keys: keys, values: values)
    }

    // MARK: - Batch metadata operations

    /// メモテキストにタグ/メタデータトークンを追加・削除する
    static func applyMetadataChanges(
        to memo: String?,
        tagsToAdd: Set<String>,
        tagsToRemove: Set<String>,
        attrsToAdd: [String: String],
        attrsToRemove: Set<String>
    ) -> String? {
        let text = memo ?? ""
        var result = text

        // 削除: タグトークンを除去
        for tag in tagsToRemove {
            let pattern = #"(?:^|(?<=\s))#"# + NSRegularExpression.escapedPattern(for: tag) + #"(?=\s|$)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }

        // 削除: 属性トークンを除去
        for key in attrsToRemove {
            let pattern = #"(?:^|(?<=\s))@"# + NSRegularExpression.escapedPattern(for: key) + #":\S+"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }

        // 属性値の変更: 既存キーの値を更新
        for (key, value) in attrsToAdd {
            let pattern = #"(?:^|(?<=\s))@"# + NSRegularExpression.escapedPattern(for: key) + #":\S+"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) != nil {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: "@\(key):\(value)")
            }
        }

        // 連続する空白を整理
        result = result
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // 追加: 新規タグを末尾に追記
        for tag in tagsToAdd.sorted() {
            // 既に存在しないタグのみ追加
            let parsed = parse(result.isEmpty ? nil : result)
            if !parsed.tags.contains(tag.lowercased()) {
                result = result.isEmpty ? "#\(tag)" : "\(result) #\(tag)"
            }
        }

        // 追加: 新規属性を末尾に追記（既存キーの値変更は上で処理済み）
        for (key, value) in attrsToAdd.sorted(by: { $0.key < $1.key }) {
            let parsed = parse(result.isEmpty ? nil : result)
            if parsed.attributes[key.lowercased()] == nil {
                result = result.isEmpty ? "@\(key):\(value)" : "\(result) @\(key):\(value)"
            }
        }

        result = result.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }

    /// 指定範囲を除去して空白を整理
    private static func removeRanges(from text: String, ranges: [Range<String.Index>]) -> String {
        guard !ranges.isEmpty else { return text }

        // 降順にソートして後ろから除去（インデックスのずれを防ぐ）
        let sorted = ranges.sorted { $0.lowerBound > $1.lowerBound }
        var result = text
        for range in sorted {
            result.removeSubrange(range)
        }

        // 連続する空白を1つにまとめてトリム
        return result
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
