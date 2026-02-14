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
