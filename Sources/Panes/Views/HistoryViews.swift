import SwiftUI
import AppKit

/// タブの種類
enum HistoryTab: String, CaseIterable {
    case archives
    case images
}

/// 初期画面で選択可能なアイテムの種類
enum SelectableHistoryItem: Equatable, Hashable {
    case archive(id: String, filePath: String)
    case standaloneImage(id: String, filePath: String)
    case archivedImage(id: String, parentPath: String, relativePath: String)
    case session(id: UUID)

    var id: String {
        switch self {
        case .archive(let id, _): return id
        case .standaloneImage(let id, _): return id
        case .archivedImage(let id, _, _): return id
        case .session(let id): return id.uuidString
        }
    }

    var sessionId: UUID? {
        if case .session(let id) = self { return id }
        return nil
    }
}

/// 初期画面（ファイル未選択時）
struct InitialScreenView: View {
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(AppSettings.self) private var appSettings

    let errorMessage: String?
    let historyState: HistoryUIState
    var isSearchFocused: FocusState<Bool>.Binding
    let onOpenFile: () -> Void
    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo) for archives
    let onEditImageMemo: (String, String?) -> Void  // (id, currentMemo) for image catalog
    let onOpenImageCatalogFile: (String, String?) -> Void  // (filePath, relativePath) for image catalog
    var onRestoreSession: ((SessionGroup) -> Void)? = nil
    var onExitSearch: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Text(AppInfo.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                Text(L("drop_files_hint"))
                    .foregroundColor(.gray)
            }

            Button(L("open_file")) {
                onOpenFile()
            }
            .buttonStyle(.borderedProminent)

            // 履歴表示
            HistoryListView(
                historyState: historyState,
                isSearchFocused: isSearchFocused,
                onOpenHistoryFile: onOpenHistoryFile,
                onOpenInNewWindow: onOpenInNewWindow,
                onEditMemo: onEditMemo,
                onEditImageMemo: onEditImageMemo,
                onOpenImageFile: onOpenImageCatalogFile,
                onRestoreSession: onRestoreSession,
                onExitSearch: onExitSearch
            )
        }
    }
}

/// 履歴リスト
struct HistoryListView: View {
    @Environment(FileHistoryManager.self) private var historyManager
    @Environment(ImageCatalogManager.self) private var imageCatalogManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(SessionGroupManager.self) private var sessionGroupManager

    let historyState: HistoryUIState
    var isSearchFocused: FocusState<Bool>.Binding

    @State private var dismissedError = false
    /// セクションの折りたたみ状態
    @State private var isArchivesSectionCollapsed = false
    @State private var isImagesSectionCollapsed = false
    @State private var isStandaloneSectionCollapsed = false
    @State private var isArchiveContentSectionCollapsed = false
    @State private var isSessionsSectionCollapsed = false

    /// 入力補完用
    @State private var selectedSuggestionIndex: Int = 0
    @State private var suggestions: [String] = []

    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo) for archives
    let onEditImageMemo: (String, String?) -> Void  // (id, currentMemo) for image catalog
    let onOpenImageFile: (String, String?) -> Void  // (filePath, relativePath) - 画像ファイルを開く
    var onRestoreSession: ((SessionGroup) -> Void)? = nil
    var onExitSearch: (() -> Void)? = nil

    var body: some View {
        Group {
            // SwiftData初期化エラーの表示
            if let error = historyManager.initializationError, !dismissedError {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(L("history_database_error"))
                            .font(.headline)
                            .foregroundColor(.red)
                    }

                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)

                    Text(L("history_database_error_description"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button(action: {
                            showResetDatabaseConfirmation()
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(L("history_database_reset"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button(action: {
                            dismissedError = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle")
                                Text(L("history_database_continue"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)

                        Button(action: {
                            NSApplication.shared.terminate(nil)
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text(L("history_database_quit"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.top, 20)
            }

            // バージョントリガーを監視することで、配列更新時に再描画される
            // (history/catalogは@ObservationIgnoredなので直接監視されない)
            let _ = historyManager.historyVersion
            let _ = imageCatalogManager.catalogVersion
            // scrollTrigger監視：フォーカス時にそのウィンドウだけ再描画するため
            let _ = historyState.scrollTrigger

            let recentHistory = historyManager.getRecentHistory(limit: appSettings.maxHistoryCount)
            let imageCatalog = imageCatalogManager.catalog
            let sessionGroups = sessionGroupManager.sessionGroups

            // 検索クエリをパース（デフォルトタイプはAppSettingsから取得）
            let parsedQuery = HistorySearchParser.parse(historyState.filterText, defaultType: appSettings.defaultHistorySearchType)
            // 統合検索を実行
            let searchResult = UnifiedSearchFilter.search(
                query: parsedQuery,
                archives: recentHistory,
                images: imageCatalog,
                sessions: sessionGroups
            )

            // 履歴表示が有効で、書庫または画像またはセッションがある場合
            if historyState.showHistory && (!recentHistory.isEmpty || !imageCatalog.isEmpty || !sessionGroups.isEmpty) {
                VStack(alignment: .leading, spacing: 8) {
                    // 検索フィールド（常に表示、⌘+Fでフォーカス）
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            // インライン補完付きテキストフィールド
                            ZStack(alignment: .leading) {
                                // インライン補完テキスト（グレー表示）
                                if let completion = getInlineCompletion(for: historyState.filterText), isSearchFocused.wrappedValue {
                                    HStack(spacing: 0) {
                                        Text(historyState.filterText)
                                            .foregroundColor(.clear)
                                        Text(completion)
                                            .foregroundColor(.gray.opacity(0.6))
                                    }
                                }
                                TextField(
                                    L("unified_search_placeholder"),
                                    text: Binding<String>(
                                        get: { historyState.filterText },
                                        set: { historyState.filterText = $0 }
                                    )
                                )
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .focused(isSearchFocused)
                                .onExitCommand {
                                    historyState.isShowingSuggestions = false
                                    isSearchFocused.wrappedValue = false
                                    onExitSearch?()
                                }
                                .onChange(of: historyState.filterText) { _, newValue in
                                    // 候補を更新
                                    suggestions = computeSuggestions(from: searchResult, query: newValue)
                                    historyState.isShowingSuggestions = !suggestions.isEmpty && isSearchFocused.wrappedValue
                                    selectedSuggestionIndex = 0
                                }
                                .onKeyPress(.tab) {
                                    // Tabで補完を適用
                                    if historyState.isShowingSuggestions && !suggestions.isEmpty {
                                        applySuggestion(suggestions[selectedSuggestionIndex])
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.upArrow) {
                                    // 候補リスト内で上に移動
                                    if historyState.isShowingSuggestions && !suggestions.isEmpty {
                                        selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.downArrow) {
                                    // 候補リスト内で下に移動
                                    if historyState.isShowingSuggestions && !suggestions.isEmpty {
                                        if selectedSuggestionIndex < suggestions.count - 1 {
                                            selectedSuggestionIndex += 1
                                        }
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.escape) {
                                    // Escapeで候補リストを閉じる → 履歴を閉じる
                                    if historyState.isShowingSuggestions {
                                        historyState.isShowingSuggestions = false
                                        return .handled
                                    }
                                    // 候補がない場合は履歴を閉じる
                                    historyState.showHistory = false
                                    isSearchFocused.wrappedValue = false
                                    return .handled
                                }
                                // 注: ⌘F（履歴トグル）はメニューショートカットで処理
                            }
                            // 検索種別インジケーター
                            if !historyState.filterText.isEmpty && parsedQuery.targetType != .all {
                                Text(searchTargetLabel(parsedQuery.targetType))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.3))
                                    .cornerRadius(4)
                                    .foregroundColor(.white)
                            }
                            // クリアボタン
                            if !historyState.filterText.isEmpty {
                                Button(action: {
                                    historyState.filterText = ""
                                    historyState.isShowingSuggestions = false
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                            }
                            // フィルタードロップダウンメニュー
                            Menu {
                                Button(action: { insertSearchFilter("type:archive ") }) {
                                    Label(L("search_type_archive"), systemImage: "archivebox")
                                }
                                Button(action: { insertSearchFilter("type:individual ") }) {
                                    Label(L("search_type_individual"), systemImage: "photo")
                                }
                                Button(action: { insertSearchFilter("type:archived ") }) {
                                    Label(L("search_type_archived"), systemImage: "photo.on.rectangle")
                                }
                                Button(action: { insertSearchFilter("type:session ") }) {
                                    Label(L("search_type_session"), systemImage: "square.stack.3d.up")
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .foregroundColor(.gray)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)

                        // ドロップダウン候補リスト
                        if historyState.isShowingSuggestions && !suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                    HStack {
                                        Text(suggestion)
                                            .foregroundColor(.white)
                                        Spacer()
                                        if index == selectedSuggestionIndex {
                                            Text("Tab")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(3)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(index == selectedSuggestionIndex ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .onTapGesture {
                                        applySuggestion(suggestion)
                                    }
                                }
                            }
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(6)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.top, 20)

                    // 検索結果のセクション表示
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                // 書庫セクション
                                if parsedQuery.includesArchives && !searchResult.archives.isEmpty {
                                    archivesSectionView(
                                        archives: searchResult.archives,
                                        totalCount: recentHistory.count,
                                        isFiltering: parsedQuery.hasKeyword
                                    )
                                }

                                // 画像セクション
                                if parsedQuery.includesImages && !searchResult.images.isEmpty {
                                    imagesSectionView(
                                        images: searchResult.images,
                                        totalCount: imageCatalog.count,
                                        isFiltering: parsedQuery.hasKeyword
                                    )
                                }

                            // セッションセクション
                            if parsedQuery.includesSessions && !searchResult.sessions.isEmpty {
                                sessionsSectionView(
                                    sessions: searchResult.sessions,
                                    totalCount: sessionGroups.count,
                                    isFiltering: parsedQuery.hasKeyword
                                )
                            }

                            // 検索結果が空の場合
                            if parsedQuery.hasKeyword && searchResult.isEmpty {
                                Text(L("search_no_results"))
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.visible)
                    .preferredColorScheme(.dark)
                    .frame(maxHeight: 400)
                    .focusable()
                    // 注: ⌘F（履歴トグル）はメニューショートカットで処理
                    .onKeyPress(.escape) {
                        // Escape: 履歴を閉じる
                        historyState.closeHistory()
                        isSearchFocused.wrappedValue = false
                        return .handled
                    }
                    .onChange(of: historyState.selectedItem?.id) { _, newId in
                        if let id = newId {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    }
                }
                .frame(maxWidth: 500)
                .padding(.horizontal, 20)
                .onChange(of: searchResult.archives.count) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: searchResult.images.count) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: searchResult.sessions.map { $0.id }) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isArchivesSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isImagesSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isStandaloneSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isArchiveContentSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: isSessionsSectionCollapsed) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: historyState.scrollTrigger) { _, _ in
                    // ウィンドウフォーカス時などにvisibleItemsを再構築
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onAppear {
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
            }
        }
    }

    /// 表示中のアイテムリストを更新
    private func updateVisibleItems(archives: [FileHistoryEntry], images: [ImageCatalogEntry], sessions: [SessionGroup], parsedQuery: ParsedSearchQuery) {
        var items: [SelectableHistoryItem] = []

        // 書庫セクション
        if parsedQuery.includesArchives && !archives.isEmpty && !isArchivesSectionCollapsed {
            for entry in archives {
                items.append(.archive(id: entry.id, filePath: entry.filePath))
            }
        }

        // 画像セクション
        if parsedQuery.includesImages && !images.isEmpty && !isImagesSectionCollapsed {
            let standaloneImages = images.filter { $0.catalogType == .individual }
            let archiveContentImages = images.filter { $0.catalogType == .archived }

            // 個別画像
            if !standaloneImages.isEmpty && !isStandaloneSectionCollapsed {
                for entry in standaloneImages {
                    items.append(.standaloneImage(id: entry.id, filePath: entry.filePath))
                }
            }

            // 書庫内画像
            if !archiveContentImages.isEmpty && !isArchiveContentSectionCollapsed {
                for entry in archiveContentImages {
                    items.append(.archivedImage(id: entry.id, parentPath: entry.filePath, relativePath: entry.relativePath ?? ""))
                }
            }
        }

        // セッションセクション
        if parsedQuery.includesSessions && !sessions.isEmpty && !isSessionsSectionCollapsed {
            for session in sessions {
                items.append(.session(id: session.id))
            }
        }

        historyState.visibleItems = items
    }

    /// 検索対象種別のラベル
    private func searchTargetLabel(_ type: SearchTargetType) -> String {
        switch type {
        case .all:
            return ""
        case .archive:
            return L("search_type_archive")
        case .individual:
            return L("search_type_individual")
        case .archived:
            return L("search_type_archived")
        case .session:
            return L("search_type_session")
        }
    }

    /// 検索フィルターを挿入/置換する
    private func insertSearchFilter(_ filter: String) {
        // 既存のtype:プレフィックスを削除
        let typePattern = /^type:\w+\s*/
        let cleanedText = historyState.filterText.replacing(typePattern, with: "")

        if filter.isEmpty {
            // 「すべて」が選択された場合はtype:を削除するだけ
            historyState.filterText = cleanedText
        } else {
            // 新しいフィルターを先頭に追加
            historyState.filterText = filter + cleanedText
        }
    }

    /// type:プレフィックスの候補リスト
    private let typeFilterSuggestions = [
        "type:archive ",
        "type:individual ",
        "type:archived ",
        "type:session "
    ]

    /// 入力補完候補を計算する（type:プレフィックス用）
    private func computeSuggestions(
        from searchResult: UnifiedSearchResult,
        query: String
    ) -> [String] {
        guard !query.isEmpty else { return [] }

        let lowercaseQuery = query.lowercased()

        // 既にtype:プレフィックスが完成している場合は候補なし
        if lowercaseQuery.hasPrefix("type:") && lowercaseQuery.contains(" ") {
            return []
        }

        // "t", "ty", "typ", "type", "type:" などで始まる場合にtype:候補を表示
        let typePrefix = "type:"
        if typePrefix.hasPrefix(lowercaseQuery) || lowercaseQuery.hasPrefix("type:") {
            // type:の後の部分でフィルタリング
            if lowercaseQuery.hasPrefix("type:") {
                let afterType = String(lowercaseQuery.dropFirst(5))  // "type:" の後
                return typeFilterSuggestions.filter {
                    let suggestionAfterType = String($0.dropFirst(5).dropLast())  // "type:" と末尾スペースを除去
                    return suggestionAfterType.hasPrefix(afterType)
                }
            } else {
                // "t", "ty", "typ", "type" の場合は全候補
                return typeFilterSuggestions
            }
        }

        return []
    }

    /// インライン補完テキストを取得（最初の候補の残り部分）
    private func getInlineCompletion(for query: String) -> String? {
        guard !query.isEmpty, !suggestions.isEmpty else { return nil }

        let firstSuggestion = suggestions[selectedSuggestionIndex]
        let lowercaseQuery = query.lowercased()

        // 大文字小文字を無視して先頭一致を確認
        if firstSuggestion.lowercased().hasPrefix(lowercaseQuery) {
            // 元の候補から残りの部分を返す
            return String(firstSuggestion.dropFirst(query.count))
        }

        return nil
    }

    /// 補完を適用する
    private func applySuggestion(_ suggestion: String) {
        historyState.filterText = suggestion
        historyState.isShowingSuggestions = false
    }

    /// 書庫セクションビュー
    @ViewBuilder
    private func archivesSectionView(archives: [FileHistoryEntry], totalCount: Int, isFiltering: Bool) -> some View {
        // セクションヘッダー
        HStack {
            Button(action: { isArchivesSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isArchivesSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                    Image(systemName: "archivebox")
                    Text(L("tab_archives"))
                        .font(.subheadline.bold())
                    Text("(\(archives.count))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Spacer()

            if isFiltering {
                Text(L("history_filter_result_format", archives.count, totalCount))
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("[\(archives.count)/\(appSettings.maxHistoryCount)]")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 4)

        if !isArchivesSectionCollapsed {
            ForEach(Array(archives.enumerated()), id: \.element.id) { index, entry in
                HistoryEntryRow(
                    entry: entry,
                    onOpenHistoryFile: { filePath in
                        if index > 0 {
                            historyState.lastOpenedArchiveId = archives[index - 1].id
                        } else if index + 1 < archives.count {
                            historyState.lastOpenedArchiveId = archives[index + 1].id
                        } else {
                            historyState.lastOpenedArchiveId = nil
                        }
                        onOpenHistoryFile(filePath)
                    },
                    onOpenInNewWindow: onOpenInNewWindow,
                    onEditMemo: onEditMemo
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(historyState.selectedItem?.id == entry.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(entry.id)
            }
        }
    }

    /// 画像セクションビュー
    @ViewBuilder
    private func imagesSectionView(images: [ImageCatalogEntry], totalCount: Int, isFiltering: Bool) -> some View {
        let standaloneImages = images.filter { $0.catalogType == .individual }
        let archiveContentImages = images.filter { $0.catalogType == .archived }

        // セクションヘッダー
        HStack {
            Button(action: { isImagesSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isImagesSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                    Image(systemName: "photo")
                    Text(L("tab_images"))
                        .font(.subheadline.bold())
                    Text("(\(images.count))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Spacer()

            if isFiltering {
                Text(L("history_filter_result_format", images.count, totalCount))
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("[\(standaloneImages.count)/\(appSettings.maxStandaloneImageCount) + \(archiveContentImages.count)/\(appSettings.maxArchiveContentImageCount)]")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 4)

        if !isImagesSectionCollapsed {
            // 個別画像サブセクション
            if !standaloneImages.isEmpty {
                standaloneSubsectionView(
                    images: standaloneImages,
                    isFiltering: isFiltering
                )
            }

            // 書庫/フォルダ内画像サブセクション
            if !archiveContentImages.isEmpty {
                archiveContentSubsectionView(
                    images: archiveContentImages,
                    isFiltering: isFiltering
                )
            }
        }
    }

    /// 個別画像サブセクションビュー
    @ViewBuilder
    private func standaloneSubsectionView(images: [ImageCatalogEntry], isFiltering: Bool) -> some View {
        HStack {
            Button(action: { isStandaloneSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isStandaloneSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                    Image(systemName: "doc.richtext")
                        .font(.caption)
                    Text(L("search_type_standalone"))
                        .font(.caption.bold())
                    Text("(\(images.count))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))

            Spacer()

            if !isFiltering {
                Text("[\(images.count)/\(appSettings.maxStandaloneImageCount)]")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.leading, 16)
        .padding(.horizontal, 4)
        .padding(.top, 4)

        if !isStandaloneSectionCollapsed {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, entry in
                ImageCatalogEntryRow(
                    entry: entry,
                    onOpenImageFile: { filePath, relativePath in
                        if index > 0 {
                            historyState.lastOpenedImageId = images[index - 1].id
                        } else if index + 1 < images.count {
                            historyState.lastOpenedImageId = images[index + 1].id
                        } else {
                            historyState.lastOpenedImageId = nil
                        }
                        onOpenImageFile(filePath, relativePath)
                    },
                    onEditMemo: onEditImageMemo
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(historyState.selectedItem?.id == entry.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(entry.id)
            }
        }
    }

    /// 書庫/フォルダ内画像サブセクションビュー
    @ViewBuilder
    private func archiveContentSubsectionView(images: [ImageCatalogEntry], isFiltering: Bool) -> some View {
        HStack {
            Button(action: { isArchiveContentSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isArchiveContentSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                    Image(systemName: "doc.zipper")
                        .font(.caption)
                    Text(L("search_type_archived"))
                        .font(.caption.bold())
                    Text("(\(images.count))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))

            Spacer()

            if !isFiltering {
                Text("[\(images.count)/\(appSettings.maxArchiveContentImageCount)]")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.leading, 16)
        .padding(.horizontal, 4)
        .padding(.top, 4)

        if !isArchiveContentSectionCollapsed {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, entry in
                ImageCatalogEntryRow(
                    entry: entry,
                    onOpenImageFile: { filePath, relativePath in
                        if index > 0 {
                            historyState.lastOpenedImageId = images[index - 1].id
                        } else if index + 1 < images.count {
                            historyState.lastOpenedImageId = images[index + 1].id
                        } else {
                            historyState.lastOpenedImageId = nil
                        }
                        onOpenImageFile(filePath, relativePath)
                    },
                    onEditMemo: onEditImageMemo
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(historyState.selectedItem?.id == entry.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(entry.id)
            }
        }
    }

    /// セッションセクションビュー
    @ViewBuilder
    private func sessionsSectionView(sessions: [SessionGroup], totalCount: Int, isFiltering: Bool) -> some View {
        // セクションヘッダー
        HStack {
            Button(action: { isSessionsSectionCollapsed.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: isSessionsSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                    Image(systemName: "square.stack.3d.up")
                    Text(L("tab_sessions"))
                        .font(.subheadline.bold())
                    Text("(\(sessions.count))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)

            Spacer()

            if isFiltering {
                Text(L("history_filter_result_format", sessions.count, totalCount))
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("[\(sessions.count)/\(sessionGroupManager.maxSessionGroupCount)]")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 4)

        if !isSessionsSectionCollapsed {
            ForEach(sessions) { session in
                SessionGroupRow(
                    session: session,
                    onRestore: {
                        onRestoreSession?(session)
                    },
                    onRename: { newName in
                        sessionGroupManager.renameSessionGroup(id: session.id, newName: newName)
                    },
                    onDelete: {
                        sessionGroupManager.deleteSessionGroup(id: session.id)
                    }
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(historyState.selectedItem?.sessionId == session.id ? Color.accentColor.opacity(0.3) : Color.clear)
                .cornerRadius(4)
                .id(session.id.uuidString)
            }
        }
    }

    /// データベースリセットの確認ダイアログを表示
    private func showResetDatabaseConfirmation() {
        let alert = NSAlert()
        alert.messageText = L("history_database_reset_confirm_title")
        alert.informativeText = L("history_database_reset_confirm_message")
        alert.alertStyle = .critical
        alert.addButton(withTitle: L("history_database_reset"))
        alert.addButton(withTitle: L("cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            historyManager.resetDatabase()
        }
    }
}

/// セッショングループの行
struct SessionGroupRow: View {
    let session: SessionGroup
    let onRestore: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onRestore) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        Text(String(format: L("session_group_files_format"), session.fileCount))
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(formatDate(session.lastAccessedAt))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                // アクセス可能なファイル数
                if session.accessibleFileCount < session.fileCount {
                    Text("\(session.accessibleFileCount)/\(session.fileCount)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(isHovering ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(action: onRestore) {
                Label(L("session_group_restore"), systemImage: "arrow.uturn.backward")
            }
            Divider()
            Button(action: {
                showRenameDialog()
            }) {
                Label(L("session_group_rename"), systemImage: "pencil")
            }
            Button(role: .destructive, action: {
                showDeleteConfirmation()
            }) {
                Label(L("session_group_delete"), systemImage: "trash")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func showRenameDialog() {
        let alert = NSAlert()
        alert.messageText = L("session_rename_title")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("save"))
        alert.addButton(withTitle: L("cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = session.name
        textField.placeholderString = L("session_rename_placeholder")
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = textField.stringValue
            if !newName.isEmpty {
                onRename(newName)
            }
        }
    }

    private func showDeleteConfirmation() {
        let alert = NSAlert()
        alert.messageText = L("session_delete_confirm_title")
        alert.informativeText = String(format: L("session_delete_confirm_message"), session.name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("session_group_delete"))
        alert.addButton(withTitle: L("cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            onDelete()
        }
    }
}

/// 画像カタログエントリの行
struct ImageCatalogEntryRow: View {
    @Environment(ImageCatalogManager.self) private var catalogManager

    let entry: ImageCatalogEntry
    let onOpenImageFile: (String, String?) -> Void  // (filePath, relativePath)
    let onEditMemo: (String, String?) -> Void  // (id, currentMemo)

    // ツールチップ用（一度だけ生成してキャッシュ）
    @State private var cachedTooltip: String?

    var body: some View {
        let isAccessible = catalogManager.isAccessible(for: entry)

        HStack(spacing: 0) {
            Button(action: {
                if isAccessible {
                    onOpenImageFile(entry.filePath, entry.relativePath)
                }
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.fileName)
                            .foregroundColor(isAccessible ? .white : .gray)
                        Spacer()
                        // 解像度があれば表示
                        if let resolution = entry.resolutionString {
                            Text(resolution)
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    // 親（書庫/フォルダ）名を表示
                    if let parentName = entry.parentName {
                        Text(parentName)
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.8))
                            .lineLimit(1)
                    }
                    // メモがある場合は表示
                    if let memo = entry.memo, !memo.isEmpty {
                        Text(memo)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isAccessible)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 削除ボタン
            Button(action: {
                catalogManager.removeEntry(withId: entry.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
                    .opacity(0.6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .background(Color.white.opacity(isAccessible ? 0.1 : 0.05))
        .cornerRadius(4)
        .help(Text(cachedTooltip ?? ""))
        .onAppear {
            // 表示時に一度だけツールチップを生成してキャッシュ
            if cachedTooltip == nil {
                cachedTooltip = generateTooltip()
            }
        }
        .contextMenu {
            Button(action: {
                onOpenImageFile(entry.filePath, entry.relativePath)
            }) {
                Label(L("menu_open_in_new_window"), systemImage: "rectangle.badge.plus")
            }
            .disabled(!isAccessible)

            Divider()

            Button(action: {
                onEditMemo(entry.id, entry.memo)
            }) {
                Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
            }

            Divider()

            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.filePath)])
            }) {
                Label(L("menu_reveal_in_finder"), systemImage: "folder")
            }
            .disabled(!isAccessible)
        }
    }

    /// ツールチップ用のテキストを生成
    private func generateTooltip() -> String {
        var lines: [String] = []

        // ファイルパス（書庫/フォルダ内の場合は親パス + 相対パス）
        if entry.catalogType == .archived, let relativePath = entry.relativePath {
            lines.append(entry.filePath)
            lines.append("  → " + relativePath)
        } else {
            lines.append(entry.filePath)
        }

        // 画像フォーマット
        if let format = entry.imageFormat {
            lines.append(L("tooltip_archive_type") + ": " + format)
        }

        // 解像度
        if let resolution = entry.resolutionString {
            lines.append(L("tooltip_resolution") + ": " + resolution)
        }

        // ファイルサイズ
        if let sizeStr = entry.fileSizeString {
            lines.append(L("tooltip_file_size") + ": " + sizeStr)
        }

        // 最終アクセス日時
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append(L("tooltip_last_access") + ": " + formatter.string(from: entry.lastAccessDate))

        return lines.joined(separator: "\n")
    }
}

/// 履歴エントリの行
struct HistoryEntryRow: View {
    @Environment(FileHistoryManager.self) private var historyManager

    let entry: FileHistoryEntry
    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo)

    // ツールチップ用（一度だけ生成してキャッシュ）
    @State private var cachedTooltip: String?

    var body: some View {
        // FileHistoryManagerのキャッシュを使用（一度チェックしたらセッション中保持）
        let isAccessible = historyManager.isAccessible(for: entry)

        HStack(spacing: 0) {
            Button(action: {
                if isAccessible {
                    onOpenHistoryFile(entry.filePath)
                }
            }) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.fileName)
                            .foregroundColor(isAccessible ? .white : .gray)
                        Spacer()
                        Text(L("access_count_format", entry.accessCount))
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    // メモがある場合は表示
                    if let memo = entry.memo, !memo.isEmpty {
                        Text(memo)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isAccessible)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button(action: {
                historyManager.removeEntry(withId: entry.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
                    .opacity(0.6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .background(Color.white.opacity(isAccessible ? 0.1 : 0.05))
        .cornerRadius(4)
        .help(Text(cachedTooltip ?? ""))
        .onAppear {
            // 表示時に一度だけツールチップを生成してキャッシュ
            if cachedTooltip == nil {
                cachedTooltip = generateTooltip()
            }
        }
        .contextMenu {
            Button(action: {
                onOpenInNewWindow(entry.filePath)
            }) {
                Label(L("menu_open_in_new_window"), systemImage: "macwindow.badge.plus")
            }
            .disabled(!isAccessible)

            Divider()

            Button(action: {
                onEditMemo(entry.id, entry.memo)
            }) {
                Label(L("menu_edit_memo"), systemImage: "square.and.pencil")
            }

            Divider()

            Button(action: {
                revealInFinder()
            }) {
                Label(L("menu_reveal_in_finder"), systemImage: "folder")
            }
            .disabled(!isAccessible)
        }
    }

    /// ツールチップ用のテキストを生成（ファイルアクセスなし）
    private func generateTooltip() -> String {
        var lines: [String] = []

        // ファイルパス
        lines.append(entry.filePath)

        // 書庫の種類（拡張子から判断、ファイルアクセス不要）
        let ext = URL(fileURLWithPath: entry.filePath).pathExtension.lowercased()
        let archiveType = archiveTypeDescription(for: ext)
        if !archiveType.isEmpty {
            lines.append(L("tooltip_archive_type") + ": " + archiveType)
        }

        // ファイルサイズ（fileKeyから取得、ファイルアクセス不要）
        if let sizeStr = entry.fileSizeString {
            lines.append(L("tooltip_file_size") + ": " + sizeStr)
        }

        // 最終アクセス日時（履歴データから、ファイルアクセス不要）
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        lines.append(L("tooltip_last_access") + ": " + formatter.string(from: entry.lastAccessDate))

        return lines.joined(separator: "\n")
    }

    /// 拡張子から書庫の種類を取得
    private func archiveTypeDescription(for ext: String) -> String {
        switch ext {
        case "zip":
            return "ZIP"
        case "cbz":
            return "CBZ (Comic Book ZIP)"
        case "rar":
            return "RAR"
        case "cbr":
            return "CBR (Comic Book RAR)"
        case "7z":
            return "7-Zip"
        case "tar":
            return "TAR"
        case "gz", "gzip":
            return "GZIP"
        case "jpg", "jpeg":
            return "JPEG"
        case "png":
            return "PNG"
        case "gif":
            return "GIF"
        case "webp":
            return "WebP"
        default:
            return ext.uppercased()
        }
    }

    /// Finderでファイルを表示
    private func revealInFinder() {
        let url = URL(fileURLWithPath: entry.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
