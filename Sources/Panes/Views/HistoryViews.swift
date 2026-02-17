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

    /// 背景画像を読み込む
    private var backgroundImage: NSImage? {
        let path = appSettings.initialScreenBackgroundImagePath
        guard !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    /// 背景画像モード（背景画像あり + 履歴非表示）
    private var isBackgroundImageOnlyMode: Bool {
        backgroundImage != nil && !historyState.showHistory
    }

    var body: some View {
        ZStack {
            // 背景画像（設定されている場合）
            if let image = backgroundImage {
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            }

            // 背景画像モードではUIを非表示
            if !isBackgroundImageOnlyMode {
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
                        onRestoreSession: onRestoreSession
                    )
                }
                .padding()
                .background {
                    // 背景画像がある場合のみ半透明背景を追加
                    if backgroundImage != nil {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.7))
                    }
                }
            }
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

    /// 入力補完用
    @State private var selectedSuggestionIndex: Int = 0
    @State private var suggestions: [SearchSuggestionItem] = []
    @State private var searchBarHeight: CGFloat = 0
    @State private var isHoveringOverSuggestions: Bool = false

    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo) for archives
    let onEditImageMemo: (String, String?) -> Void  // (id, currentMemo) for image catalog
    let onOpenImageFile: (String, String?) -> Void  // (filePath, relativePath) - 画像ファイルを開く
    var onRestoreSession: ((SessionGroup) -> Void)? = nil

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
                                    // フォーカス離脱はFocusSyncModifier経由でContentViewに通知される
                                }
                                .onChange(of: historyState.filterText) { _, newValue in
                                    // メモからメタデータインデックスを収集（サジェスト用、入力時のみ）
                                    let metadataIndex = MemoMetadataParser.collectIndex(
                                        from: recentHistory.map(\.memo) + imageCatalog.map(\.memo)
                                    )
                                    // 動的プロバイダーを含めて候補を更新
                                    let providers: [any SearchSuggestionProvider] = [
                                        TypeFilterSuggestionProvider(),
                                        IsFilterSuggestionProvider(),
                                        NegatedTagSuggestionProvider(availableTags: metadataIndex.tags),
                                        NegatedMetadataKeySuggestionProvider(availableKeys: metadataIndex.keys),
                                        TagSuggestionProvider(availableTags: metadataIndex.tags),
                                    ]
                                    + metadataIndex.values.map { key, values in
                                        MetadataValueSuggestionProvider(key: key, availableValues: values)
                                            as any SearchSuggestionProvider
                                    }
                                    + [
                                        MetadataKeySuggestionProvider(availableKeys: metadataIndex.keys),
                                    ]
                                    suggestions = SearchSuggestionEngine.computeSuggestions(for: newValue, providers: providers)
                                    historyState.isShowingSuggestions = !suggestions.isEmpty
                                    selectedSuggestionIndex = 0
                                }
                                .onChange(of: isSearchFocused.wrappedValue) { _, focused in
                                    if focused {
                                        // フォーカス復帰時にサジェストを再計算
                                        if !historyState.filterText.isEmpty {
                                            let text = historyState.filterText
                                            let metadataIndex = MemoMetadataParser.collectIndex(
                                                from: recentHistory.map(\.memo) + imageCatalog.map(\.memo)
                                            )
                                            let providers: [any SearchSuggestionProvider] = [
                                                TypeFilterSuggestionProvider(),
                                                IsFilterSuggestionProvider(),
                                                TagSuggestionProvider(availableTags: metadataIndex.tags),
                                            ]
                                            + metadataIndex.values.map { key, values in
                                                MetadataValueSuggestionProvider(key: key, availableValues: values)
                                                    as any SearchSuggestionProvider
                                            }
                                            + [
                                                MetadataKeySuggestionProvider(availableKeys: metadataIndex.keys),
                                            ]
                                            suggestions = SearchSuggestionEngine.computeSuggestions(for: text, providers: providers)
                                            historyState.isShowingSuggestions = !suggestions.isEmpty
                                            selectedSuggestionIndex = 0
                                        }
                                    } else if !isHoveringOverSuggestions {
                                        historyState.isShowingSuggestions = false
                                    }
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
                                Divider()
                                Button(action: { insertSearchFilter("is:locked ") }) {
                                    Label(L("search_filter_locked"), systemImage: "lock.fill")
                                }
                                Divider()
                                Button(action: { insertSearchFilter("#") }) {
                                    Label(L("search_filter_tag"), systemImage: "tag")
                                }
                                Button(action: { insertSearchFilter("@") }) {
                                    Label(L("search_filter_metadata"), systemImage: "at")
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
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear { searchBarHeight = geo.size.height }
                            }
                        )
                        .overlay(alignment: .topLeading) {
                            // ドロップダウン候補リスト（検索バー直下にオーバーレイ表示）
                            if historyState.isShowingSuggestions && !suggestions.isEmpty {
                                suggestionDropdownView()
                                    .offset(y: searchBarHeight + 2)
                            }
                        }

                    }
                    .padding(.top, 20)
                    .zIndex(1)

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
                // 順序変更も検出するためIDリストを監視（countだけだと順序変更時にvisibleItemsが更新されない）
                .onChange(of: searchResult.archives.map { $0.id }) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: searchResult.images.map { $0.id }) { _, _ in
                    updateVisibleItems(archives: searchResult.archives, images: searchResult.images, sessions: searchResult.sessions, parsedQuery: parsedQuery)
                }
                .onChange(of: searchResult.sessions.map { $0.id }) { _, _ in
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
        if parsedQuery.includesArchives {
            for entry in archives {
                items.append(.archive(id: entry.id, filePath: entry.filePath))
            }
        }

        // 画像セクション
        if parsedQuery.includesImages {
            for entry in images {
                if entry.catalogType == .individual {
                    items.append(.standaloneImage(id: entry.id, filePath: entry.filePath))
                } else {
                    items.append(.archivedImage(id: entry.id, parentPath: entry.filePath, relativePath: entry.relativePath ?? ""))
                }
            }
        }

        // セッションセクション
        if parsedQuery.includesSessions {
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

        // 先にフォーカスを確立してからテキストを更新する
        // （onChangeでisSearchFocused=trueを参照できるようにするため）
        isSearchFocused.wrappedValue = true
        DispatchQueue.main.async {
            if filter.isEmpty {
                historyState.filterText = cleanedText
            } else if !cleanedText.isEmpty && !filter.contains(":") {
                // タグ(#)やメタデータ(@)は既存テキストの後ろに追記
                let separator = cleanedText.hasSuffix(" ") ? "" : " "
                historyState.filterText = cleanedText + separator + filter
            } else {
                historyState.filterText = filter + cleanedText
            }
        }
    }

    /// サジェストドロップダウンビュー（カーソル位置直下に表示）
    @ViewBuilder
    private func suggestionDropdownView() -> some View {
        let alignmentPrefix = suggestions.first?.alignmentPrefix ?? ""
        // 検索バーの内部レイアウトを非表示で複製し、テキスト位置を正確に合わせる
        HStack {
            // 🔍アイコンと同じ幅を確保（HStackのデフォルトスペーシングも再現）
            Image(systemName: "magnifyingglass").hidden()
            HStack(spacing: 0) {
                // "あ type:" 等の幅を確保（同じフォントレンダリングなので正確）
                Text(alignmentPrefix)
                    .foregroundColor(.clear)
                    .allowsHitTesting(false)
                ScrollViewReader { suggestionProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                HStack(spacing: 8) {
                                    Text(suggestion.displayText)
                                        .foregroundColor(.white)
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == selectedSuggestionIndex ? Color.accentColor.opacity(0.3) : Color.clear)
                                .contentShape(Rectangle())
                                .id(index)
                                .onTapGesture {
                                    applySuggestion(suggestion)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedSuggestionIndex) { _, newIndex in
                        suggestionProxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .frame(height: min(CGFloat(suggestions.count) * 30, 200))
                .background(Color.black.opacity(0.8))
                .cornerRadius(6)
                .onHover { hovering in
                    isHoveringOverSuggestions = hovering
                    // ホバー解除時、検索フィールドにフォーカスがなければ候補を閉じる
                    if !hovering && !isSearchFocused.wrappedValue {
                        historyState.isShowingSuggestions = false
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)  // 検索バーの.padding(8)に合わせる
        .padding(.top, 2)
    }

    /// インライン補完テキストを取得
    private func getInlineCompletion(for query: String) -> String? {
        guard !suggestions.isEmpty else { return nil }
        return SearchSuggestionEngine.inlineCompletion(
            for: query, suggestion: suggestions[selectedSuggestionIndex]
        )
    }

    /// 補完を適用する
    private func applySuggestion(_ suggestion: SearchSuggestionItem) {
        historyState.filterText = suggestion.fullText
        historyState.isShowingSuggestions = false
    }

    /// 書庫セクションビュー
    @ViewBuilder
    private func archivesSectionView(archives: [FileHistoryEntry], totalCount: Int, isFiltering: Bool) -> some View {
        // セクションヘッダー
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "archivebox")
                Text(L("tab_archives"))
                    .font(.subheadline.bold())
                Text("(\(archives.count))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
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

        ForEach(Array(archives.enumerated()), id: \.element.id) { index, entry in
                HistoryEntryRow(
                    entry: entry,
                    isExpanded: historyState.isExpanded(entry.id),
                    onToggleExpand: { shiftHeld in
                        if shiftHeld {
                            historyState.toggleExpandKeeping(entry.id)
                        } else {
                            historyState.toggleExpand(entry.id)
                        }
                    },
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
                .background(historyState.isSelected(.archive(id: entry.id, filePath: entry.filePath)) ? Color.accentColor.opacity(0.3) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .opacity(historyState.isCursorOnly(.archive(id: entry.id, filePath: entry.filePath)) ? 1 : 0)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    let item = SelectableHistoryItem.archive(id: entry.id, filePath: entry.filePath)
                    if NSEvent.modifierFlags.contains(.command) {
                        historyState.toggleSelection(item)
                    } else if NSEvent.modifierFlags.contains(.shift) {
                        historyState.extendSelection(to: item)
                    } else {
                        historyState.select(item)
                    }
                }
                .cornerRadius(4)
                .id(entry.id)
            }
    }

    /// 画像セクションビュー
    @ViewBuilder
    private func imagesSectionView(images: [ImageCatalogEntry], totalCount: Int, isFiltering: Bool) -> some View {
        let standaloneCount = images.filter { $0.catalogType == .individual }.count
        let archivedCount = images.filter { $0.catalogType == .archived }.count

        // セクションヘッダー
        HStack {
            HStack(spacing: 4) {
                if standaloneCount > 0 && archivedCount > 0 {
                    Image(systemName: "photo")
                    Text(L("tab_images"))
                        .font(.subheadline.bold())
                } else if standaloneCount > 0 {
                    Image(systemName: "doc.richtext")
                    Text(L("search_type_individual"))
                        .font(.subheadline.bold())
                } else {
                    Image(systemName: "doc.zipper")
                    Text(L("search_type_archived"))
                        .font(.subheadline.bold())
                }
                Text("(\(images.count))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .foregroundColor(.white)

            Spacer()

            HStack(spacing: 8) {
                if standaloneCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.richtext")
                            .font(.caption2)
                        Text("[\(standaloneCount)/\(appSettings.maxStandaloneImageCount)]")
                    }
                }
                if archivedCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "doc.zipper")
                            .font(.caption2)
                        Text("[\(archivedCount)/\(appSettings.maxArchiveContentImageCount)]")
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding(.horizontal, 4)

        ForEach(Array(images.enumerated()), id: \.element.id) { index, entry in
                let selectableItem: SelectableHistoryItem = entry.catalogType == .individual
                    ? .standaloneImage(id: entry.id, filePath: entry.filePath)
                    : .archivedImage(id: entry.id, parentPath: entry.filePath, relativePath: entry.relativePath ?? "")

                ImageCatalogEntryRow(
                    entry: entry,
                    isExpanded: historyState.isExpanded(entry.id),
                    onToggleExpand: { shiftHeld in
                        if shiftHeld {
                            historyState.toggleExpandKeeping(entry.id)
                        } else {
                            historyState.toggleExpand(entry.id)
                        }
                    },
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
                .background(historyState.isSelected(selectableItem) ? Color.accentColor.opacity(0.3) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .opacity(historyState.isCursorOnly(selectableItem) ? 1 : 0)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) {
                        historyState.toggleSelection(selectableItem)
                    } else if NSEvent.modifierFlags.contains(.shift) {
                        historyState.extendSelection(to: selectableItem)
                    } else {
                        historyState.select(selectableItem)
                    }
                }
                .cornerRadius(4)
                .id(entry.id)
            }
    }

    /// セッションセクションビュー
    @ViewBuilder
    private func sessionsSectionView(sessions: [SessionGroup], totalCount: Int, isFiltering: Bool) -> some View {
        // セクションヘッダー
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up")
                Text(L("tab_sessions"))
                    .font(.subheadline.bold())
                Text("(\(sessions.count))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
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
                .background(historyState.isSelected(.session(id: session.id)) ? Color.accentColor.opacity(0.3) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .opacity(historyState.isCursorOnly(.session(id: session.id)) ? 1 : 0)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    let item = SelectableHistoryItem.session(id: session.id)
                    if NSEvent.modifierFlags.contains(.command) {
                        historyState.toggleSelection(item)
                    } else if NSEvent.modifierFlags.contains(.shift) {
                        historyState.extendSelection(to: item)
                    } else {
                        historyState.select(item)
                    }
                }
                .cornerRadius(4)
                .id(session.id.uuidString)
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
    var isExpanded: Bool = false
    var onToggleExpand: ((Bool) -> Void)? = nil  // (shiftHeld) -> Void
    let onOpenImageFile: (String, String?) -> Void  // (filePath, relativePath)
    let onEditMemo: (String, String?) -> Void  // (id, currentMemo)

    var body: some View {
        let isAccessible = catalogManager.isAccessible(for: entry)

        VStack(alignment: .leading, spacing: 0) {
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
                .padding(.trailing, 4)

                // トグルアイコン
                Button {
                    let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                    onToggleExpand?(shiftHeld)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.gray)
                        .opacity(0.6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            // 展開詳細
            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    CoverThumbnailView(source: entry.catalogType == .individual
                        ? .imageThumbnail(id: entry.id, filePath: entry.filePath)
                        : .archivedImageThumbnail(
                            id: entry.id,
                            archivePath: entry.filePath,
                            relativePath: entry.relativePath ?? ""
                        )
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        // パス
                        if entry.catalogType == .archived, let relativePath = entry.relativePath {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.filePath)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                Text("  → " + relativePath)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text(entry.filePath)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 12) {
                            if let format = entry.imageFormat {
                                Text(L("tooltip_archive_type") + ": " + format)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if let resolution = entry.resolutionString {
                                Text(L("tooltip_resolution") + ": " + resolution)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if let size = entry.fileSizeString {
                                Text(L("tooltip_file_size") + ": " + size)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }

                        Text(L("tooltip_last_access") + ": " + formattedDate(entry.lastAccessDate))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .background(Color.white.opacity(isAccessible ? 0.1 : 0.05))
        .cornerRadius(4)
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

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// 履歴エントリの行
struct HistoryEntryRow: View {
    @Environment(FileHistoryManager.self) private var historyManager

    let entry: FileHistoryEntry
    var isExpanded: Bool = false
    var onToggleExpand: ((Bool) -> Void)? = nil  // (shiftHeld) -> Void
    let onOpenHistoryFile: (String) -> Void
    let onOpenInNewWindow: (String) -> Void  // filePath
    let onEditMemo: (String, String?) -> Void  // (fileKey, currentMemo)

    var body: some View {
        // FileHistoryManagerのキャッシュを使用（一度チェックしたらセッション中保持）
        let isAccessible = historyManager.isAccessible(for: entry)

        VStack(alignment: .leading, spacing: 0) {
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
                            // パスワード保護マーク
                            if entry.isPasswordProtected == true {
                                Text("🔒")
                                    .font(.caption)
                            }
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
                .padding(.trailing, 4)

                // トグルアイコン
                Button {
                    let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                    onToggleExpand?(shiftHeld)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.gray)
                        .opacity(0.6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            // 展開詳細
            if isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    CoverThumbnailView(source: .archiveCover(
                        id: entry.id,
                        filePath: entry.filePath,
                        isPasswordProtected: entry.isPasswordProtected == true
                    ))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.filePath)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            let ext = URL(fileURLWithPath: entry.filePath).pathExtension.lowercased()
                            let archiveType = archiveTypeDescription(for: ext)
                            if !archiveType.isEmpty {
                                Text(L("tooltip_archive_type") + ": " + archiveType)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            if let size = entry.fileSizeString {
                                Text(L("tooltip_file_size") + ": " + size)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }

                        Text(L("tooltip_last_access") + ": " + formattedDate(entry.lastAccessDate))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .background(Color.white.opacity(isAccessible ? 0.1 : 0.05))
        .cornerRadius(4)
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

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

/// カバー画像サムネイルビュー
private struct CoverThumbnailView: View {
    enum Source {
        case archiveCover(id: String, filePath: String, isPasswordProtected: Bool)
        case imageThumbnail(id: String, filePath: String)
        case archivedImageThumbnail(id: String, archivePath: String, relativePath: String)
    }

    let source: Source

    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 80, height: 120)
        .task {
            image = await loadImage()
            isLoading = false
        }
    }

    private func loadImage() async -> NSImage? {
        switch source {
        case .archiveCover(let id, let filePath, let isPasswordProtected):
            let password: String? = isPasswordProtected
                ? PasswordStorage.shared.getPassword(forArchive: filePath)
                : nil
            return await CoverImageLoader.shared.loadArchiveCover(
                id: id, filePath: filePath, password: password
            )
        case .imageThumbnail(let id, let filePath):
            return await CoverImageLoader.shared.loadImageThumbnail(
                id: id, filePath: filePath
            )
        case .archivedImageThumbnail(let id, let archivePath, let relativePath):
            let password = PasswordStorage.shared.getPassword(forArchive: archivePath)
            return await CoverImageLoader.shared.loadArchivedImageThumbnail(
                id: id, archivePath: archivePath, relativePath: relativePath, password: password
            )
        }
    }
}
