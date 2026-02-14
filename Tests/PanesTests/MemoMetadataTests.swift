import Testing
@testable import Panes

// MARK: - MemoMetadataParser Tests

@Suite("MemoMetadataParser Tests")
struct MemoMetadataParserTests {

    @Test("Parse @key:value attributes")
    func testParseAttributes() {
        let result = MemoMetadataParser.parse("@author:山田 面白い")
        #expect(result.attributes["author"] == "山田")
        #expect(result.plainText == "面白い")
    }

    @Test("Parse #tag tags")
    func testParseTags() {
        let result = MemoMetadataParser.parse("#comics 面白い")
        #expect(result.tags.contains("comics"))
        #expect(result.plainText == "面白い")
    }

    @Test("Parse mixed metadata and tags")
    func testParseMixed() {
        let result = MemoMetadataParser.parse("@author:山田 #comics 面白い @rating:8")
        #expect(result.attributes["author"] == "山田")
        #expect(result.attributes["rating"] == "8")
        #expect(result.tags.contains("comics"))
        #expect(result.plainText == "面白い")
    }

    @Test("Parse nil memo")
    func testParseNil() {
        let result = MemoMetadataParser.parse(nil)
        #expect(result.attributes.isEmpty)
        #expect(result.tags.isEmpty)
        #expect(result.plainText.isEmpty)
    }

    @Test("Parse empty memo")
    func testParseEmpty() {
        let result = MemoMetadataParser.parse("")
        #expect(result.attributes.isEmpty)
        #expect(result.tags.isEmpty)
        #expect(result.plainText.isEmpty)
    }

    @Test("Email addresses are not recognized as attributes")
    func testEmailNotRecognized() {
        let result = MemoMetadataParser.parse("user@host.com テスト")
        #expect(result.attributes.isEmpty)
        #expect(result.plainText == "user@host.com テスト")
    }

    @Test("Keys are lowercased")
    func testKeysLowercased() {
        let result = MemoMetadataParser.parse("@Author:山田 #Comics")
        #expect(result.attributes["author"] == "山田")
        #expect(result.tags.contains("comics"))
    }

    @Test("Multiple tags")
    func testMultipleTags() {
        let result = MemoMetadataParser.parse("#action #comedy #scifi")
        #expect(result.tags == Set(["action", "comedy", "scifi"]))
        #expect(result.plainText.isEmpty)
    }

    @Test("Only metadata, no plain text")
    func testOnlyMetadata() {
        let result = MemoMetadataParser.parse("@key:value")
        #expect(result.attributes["key"] == "value")
        #expect(result.plainText.isEmpty)
    }
}

// MARK: - MetadataIndex Tests

@Suite("MetadataIndex Tests")
struct MetadataIndexTests {

    @Test("Collect tags and keys from multiple memos")
    func testCollectIndex() {
        let memos: [String?] = [
            "@author:山田 #comics 面白い",
            "@rating:8 #action",
            "#comics @author:田中",  // 重複タグ・キーは1つにまとまる
        ]
        let index = MemoMetadataParser.collectIndex(from: memos)
        #expect(index.tags == Set(["comics", "action"]))
        #expect(index.keys == Set(["author", "rating"]))
    }

    @Test("Collect from nil and empty memos")
    func testCollectIndexNilEmpty() {
        let memos: [String?] = [nil, "", nil, "@key:val #tag"]
        let index = MemoMetadataParser.collectIndex(from: memos)
        #expect(index.tags == Set(["tag"]))
        #expect(index.keys == Set(["key"]))
    }

    @Test("Collect from empty array")
    func testCollectIndexEmpty() {
        let index = MemoMetadataParser.collectIndex(from: [])
        #expect(index.tags.isEmpty)
        #expect(index.keys.isEmpty)
        #expect(index.values.isEmpty)
    }

    @Test("Collect values per key from multiple memos")
    func testCollectValues() {
        let memos: [String?] = [
            "@author:山田 @rating:8",
            "@author:田中 @rating:5",
            "@author:山田",  // 重複値は1つにまとまる
        ]
        let index = MemoMetadataParser.collectIndex(from: memos)
        #expect(index.values["author"] == Set(["山田", "田中"]))
        #expect(index.values["rating"] == Set(["8", "5"]))
    }

    @Test("Collect values from nil and empty memos")
    func testCollectValuesNilEmpty() {
        let memos: [String?] = [nil, "", "@key:val"]
        let index = MemoMetadataParser.collectIndex(from: memos)
        #expect(index.values["key"] == Set(["val"]))
    }
}

// MARK: - TagSuggestionProvider Tests

@Suite("TagSuggestionProvider Tests")
struct TagSuggestionProviderTests {

    @Test("# shows all tags")
    func testHashShowsAll() {
        let provider = TagSuggestionProvider(availableTags: ["comics", "action", "comedy"])
        let results = provider.suggestions(for: "#")
        #expect(results.count == 3)
        #expect(results == ["#action ", "#comedy ", "#comics "])
    }

    @Test("Prefix match")
    func testPrefixMatch() {
        let provider = TagSuggestionProvider(availableTags: ["comics", "comedy", "action"])
        let results = provider.suggestions(for: "#com")
        #expect(results == ["#comics ", "#comedy "])  // sorted
    }

    @Test("Case normalization")
    func testCaseNormalization() {
        let provider = TagSuggestionProvider(availableTags: ["comics"])
        let results = provider.suggestions(for: "#COM")
        #expect(results == ["#comics "])
    }

    @Test("No match")
    func testNoMatch() {
        let provider = TagSuggestionProvider(availableTags: ["comics"])
        let results = provider.suggestions(for: "#xyz")
        #expect(results.isEmpty)
    }

    @Test("Non-hash prefix returns empty")
    func testNonHashPrefix() {
        let provider = TagSuggestionProvider(availableTags: ["comics"])
        let results = provider.suggestions(for: "type:")
        #expect(results.isEmpty)
    }

    @Test("Max 8 suggestions")
    func testMaxSuggestions() {
        let tags = Set((1...20).map { "tag\($0)" })
        let provider = TagSuggestionProvider(availableTags: tags)
        let results = provider.suggestions(for: "#")
        #expect(results.count == 8)
    }
}

// MARK: - MetadataKeySuggestionProvider Tests

@Suite("MetadataKeySuggestionProvider Tests")
struct MetadataKeySuggestionProviderTests {

    @Test("@ shows all keys with = suffix")
    func testAtShowsAll() {
        let provider = MetadataKeySuggestionProvider(availableKeys: ["author", "rating"])
        let results = provider.suggestions(for: "@")
        #expect(results == ["@author=", "@rating="])
    }

    @Test("Prefix match")
    func testPrefixMatch() {
        let provider = MetadataKeySuggestionProvider(availableKeys: ["author", "artist", "rating"])
        let results = provider.suggestions(for: "@au")
        #expect(results == ["@author="])
    }

    @Test("Case normalization")
    func testCaseNormalization() {
        let provider = MetadataKeySuggestionProvider(availableKeys: ["author"])
        let results = provider.suggestions(for: "@AU")
        #expect(results == ["@author="])
    }

    @Test("Non-at prefix returns empty")
    func testNonAtPrefix() {
        let provider = MetadataKeySuggestionProvider(availableKeys: ["author"])
        let results = provider.suggestions(for: "#tag")
        #expect(results.isEmpty)
    }
}

// MARK: - MetadataValueSuggestionProvider Tests

@Suite("MetadataValueSuggestionProvider Tests")
struct MetadataValueSuggestionProviderTests {

    @Test("@key= shows all values for that key")
    func testShowsAllValues() {
        let provider = MetadataValueSuggestionProvider(key: "author", availableValues: ["山田", "田中", "鈴木"])
        let results = provider.suggestions(for: "@author=")
        #expect(results.count == 3)
        #expect(results == ["@author=山田 ", "@author=田中 ", "@author=鈴木 "])
    }

    @Test("Prefix match filters values")
    func testPrefixMatch() {
        let provider = MetadataValueSuggestionProvider(key: "author", availableValues: ["山田", "田中", "山本"])
        let results = provider.suggestions(for: "@author=山")
        #expect(results == ["@author=山本 ", "@author=山田 "])
    }

    @Test("Case-insensitive prefix match")
    func testCaseInsensitive() {
        let provider = MetadataValueSuggestionProvider(key: "genre", availableValues: ["Action", "Comedy"])
        let results = provider.suggestions(for: "@genre=act")
        #expect(results == ["@genre=Action "])
    }

    @Test("Case-insensitive key matching")
    func testCaseInsensitiveKey() {
        let provider = MetadataValueSuggestionProvider(key: "author", availableValues: ["山田"])
        let results = provider.suggestions(for: "@AUTHOR=")
        #expect(results == ["@author=山田 "])
    }

    @Test("Different key returns empty")
    func testDifferentKey() {
        let provider = MetadataValueSuggestionProvider(key: "author", availableValues: ["山田"])
        let results = provider.suggestions(for: "@rating=")
        #expect(results.isEmpty)
    }

    @Test("Non-@ prefix returns empty")
    func testNonAtPrefix() {
        let provider = MetadataValueSuggestionProvider(key: "author", availableValues: ["山田"])
        let results = provider.suggestions(for: "#tag")
        #expect(results.isEmpty)
    }

    @Test("Max 8 suggestions")
    func testMaxSuggestions() {
        let values = Set((1...20).map { "val\($0)" })
        let provider = MetadataValueSuggestionProvider(key: "k", availableValues: values)
        let results = provider.suggestions(for: "@k=")
        #expect(results.count == 8)
    }

    @Test("Key provider returns empty for @key= pattern, value provider takes over")
    func testKeyToValueTransition() {
        let keyProvider = MetadataKeySuggestionProvider(availableKeys: ["author", "rating"])
        let valueProvider = MetadataValueSuggestionProvider(key: "author", availableValues: ["山田", "田中"])

        // @au → key provider matches
        let keyResults = keyProvider.suggestions(for: "@au")
        #expect(keyResults == ["@author="])

        // @author= → key provider returns empty (no key starts with "author=")
        let keyResultsAfter = keyProvider.suggestions(for: "@author=")
        #expect(keyResultsAfter.isEmpty)

        // @author= → value provider matches
        let valueResults = valueProvider.suggestions(for: "@author=")
        #expect(valueResults == ["@author=山田 ", "@author=田中 "])
    }
}

// MARK: - HistorySearchParser Metadata Tests

@Suite("HistorySearchParser Metadata Tests")
struct HistorySearchParserMetadataTests {

    @Test("Parse #tag in search query")
    func testParseTag() {
        let result = HistorySearchParser.parse("#comics")
        #expect(result.tagConditions == ["comics"])
        #expect(result.keywords.isEmpty)
    }

    @Test("Parse @key=value in search query")
    func testParseMetadataEqual() {
        let result = HistorySearchParser.parse("@author=山田")
        #expect(result.metadataConditions.count == 1)
        #expect(result.metadataConditions[0].key == "author")
        #expect(result.metadataConditions[0].op == .equal)
        #expect(result.metadataConditions[0].value == "山田")
    }

    @Test("Parse comparison operators")
    func testParseComparisonOperators() {
        let cases: [(String, MetadataOperator)] = [
            ("@rating>=5", .greaterOrEqual),
            ("@rating<=5", .lessOrEqual),
            ("@rating!=5", .notEqual),
            ("@rating>5", .greaterThan),
            ("@rating<5", .lessThan),
        ]
        for (query, expectedOp) in cases {
            let result = HistorySearchParser.parse(query)
            #expect(result.metadataConditions.count == 1, "Failed for query: \(query)")
            #expect(result.metadataConditions[0].op == expectedOp, "Failed for query: \(query)")
            #expect(result.metadataConditions[0].value == "5", "Failed for query: \(query)")
        }
    }

    @Test("Invalid metadata token falls back to keyword")
    func testInvalidMetadataFallback() {
        // @alone without operator should be a keyword
        let result = HistorySearchParser.parse("@alone")
        #expect(result.metadataConditions.isEmpty)
        #expect(result.keywords == ["@alone"])
    }

    @Test("Mixed tags, metadata, and keywords")
    func testMixedParsing() {
        let result = HistorySearchParser.parse("#comics @author=山田 面白い")
        #expect(result.tagConditions == ["comics"])
        #expect(result.metadataConditions.count == 1)
        #expect(result.metadataConditions[0].key == "author")
        #expect(result.keywords == ["面白い"])
    }

    @Test("Tag with type filter")
    func testTagWithTypeFilter() {
        let result = HistorySearchParser.parse("type:archive #comics")
        #expect(result.targetType == .archive)
        #expect(result.tagConditions == ["comics"])
    }
}

// MARK: - UnifiedSearchFilter Metadata Tests

@Suite("UnifiedSearchFilter Metadata Tests")
struct UnifiedSearchFilterMetadataTests {

    private func makeArchiveEntry(memo: String?) -> FileHistoryEntry {
        FileHistoryEntry(
            id: "test-id",
            fileKey: "test-key",
            pageSettingsRef: nil,
            filePath: "/tmp/test.cbz",
            fileName: "test.cbz",
            lastAccessDate: .now,
            accessCount: 1,
            memo: memo
        )
    }

    @Test("Tag match")
    func testTagMatch() {
        let entry = makeArchiveEntry(memo: "#comics 面白い")
        let query = HistorySearchParser.parse("#comics")
        #expect(UnifiedSearchFilter.matches(entry, query: query))
    }

    @Test("Tag non-match")
    func testTagNonMatch() {
        let entry = makeArchiveEntry(memo: "#comics 面白い")
        let query = HistorySearchParser.parse("#other")
        #expect(!UnifiedSearchFilter.matches(entry, query: query))
    }

    @Test("Metadata attribute match")
    func testMetadataMatch() {
        let entry = makeArchiveEntry(memo: "@author:山田 #comics")
        let query = HistorySearchParser.parse("@author=山田")
        #expect(UnifiedSearchFilter.matches(entry, query: query))
    }

    @Test("Metadata attribute non-match")
    func testMetadataNonMatch() {
        let entry = makeArchiveEntry(memo: "@author:山田 #comics")
        let query = HistorySearchParser.parse("@author=田中")
        #expect(!UnifiedSearchFilter.matches(entry, query: query))
    }

    @Test("Numeric comparison >=")
    func testNumericGreaterOrEqual() {
        let entry = makeArchiveEntry(memo: "@rating:8")
        let queryGte = HistorySearchParser.parse("@rating>=5")
        #expect(UnifiedSearchFilter.matches(entry, query: queryGte))
        let queryLt = HistorySearchParser.parse("@rating<5")
        #expect(!UnifiedSearchFilter.matches(entry, query: queryLt))
    }

    @Test("Numeric comparison exact boundary")
    func testNumericBoundary() {
        let entry = makeArchiveEntry(memo: "@rating:5")
        let queryGte = HistorySearchParser.parse("@rating>=5")
        #expect(UnifiedSearchFilter.matches(entry, query: queryGte))
        let queryGt = HistorySearchParser.parse("@rating>5")
        #expect(!UnifiedSearchFilter.matches(entry, query: queryGt))
    }

    @Test("Combined keyword and metadata")
    func testCombinedKeywordAndMetadata() {
        let entry = makeArchiveEntry(memo: "@author:山田 #comics 面白い")
        // Both keyword and tag must match
        let query = HistorySearchParser.parse("面白い #comics")
        #expect(UnifiedSearchFilter.matches(entry, query: query))
    }

    @Test("Combined keyword non-match with metadata match")
    func testKeywordNonMatchWithMetadataMatch() {
        let entry = makeArchiveEntry(memo: "@author:山田 #comics 面白い")
        // Tag matches but keyword doesn't
        let query = HistorySearchParser.parse("つまらない #comics")
        #expect(!UnifiedSearchFilter.matches(entry, query: query))
    }

    @Test("Entry without memo fails metadata filter")
    func testNoMemoFailsMetadata() {
        let entry = makeArchiveEntry(memo: nil)
        let query = HistorySearchParser.parse("#comics")
        #expect(!UnifiedSearchFilter.matches(entry, query: query))
    }

    @Test("Session excluded when metadata filter present")
    func testSessionExcludedWithMetadata() {
        let session = SessionGroup(
            id: .init(),
            name: "Test Session",
            entries: [],
            createdAt: .now,
            lastAccessedAt: .now
        )
        let query = HistorySearchParser.parse("#comics", defaultType: .all)
        #expect(!UnifiedSearchFilter.matches(session, query: query))
    }

    @Test("Not-equal operator")
    func testNotEqual() {
        let entry = makeArchiveEntry(memo: "@author:山田")
        let query = HistorySearchParser.parse("@author!=田中")
        #expect(UnifiedSearchFilter.matches(entry, query: query))
        let query2 = HistorySearchParser.parse("@author!=山田")
        #expect(!UnifiedSearchFilter.matches(entry, query: query2))
    }
}
