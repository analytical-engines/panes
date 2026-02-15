import SwiftUI
import AppKit

/// ローディング画面（独自アニメーション）
struct LoadingView: View {
    var phase: String?
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            // 独自のスピナー（円弧を回転）
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.gray, lineWidth: 3)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    // アニメーションを明示的に開始
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            Text(phase ?? L("loading"))
                .foregroundColor(.gray)
        }
    }
}

/// サジェスト付きテキストフィールド（メモ/メタデータ編集用）
struct SuggestingTextField: View {
    let placeholder: String
    @Binding var text: String
    let width: CGFloat
    let providers: [any SearchSuggestionProvider]
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @State private var suggestions: [SearchSuggestionItem] = []
    @State private var selectedIndex: Int = 0
    @State private var isShowingSuggestions: Bool = false
    @State private var isHoveringOverSuggestions: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    suggestions = SearchSuggestionEngine.computeSuggestions(for: newValue, providers: providers)
                    isShowingSuggestions = !suggestions.isEmpty
                    selectedIndex = 0
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused && !isHoveringOverSuggestions {
                        isShowingSuggestions = false
                    }
                }
                .onKeyPress(.tab) {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        applySuggestion(suggestions[selectedIndex])
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        selectedIndex = max(0, selectedIndex - 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        if selectedIndex < suggestions.count - 1 {
                            selectedIndex += 1
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    if isShowingSuggestions {
                        isShowingSuggestions = false
                        return .handled
                    }
                    return .ignored
                }
                .onSubmit {
                    if isShowingSuggestions && !suggestions.isEmpty {
                        applySuggestion(suggestions[selectedIndex])
                    } else {
                        onSubmit()
                    }
                }

            if isShowingSuggestions && !suggestions.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                                Text(suggestion.displayText)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(index == selectedIndex ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .contentShape(Rectangle())
                                    .id(index)
                                    .onTapGesture {
                                        applySuggestion(suggestion)
                                    }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .frame(width: width)
                .frame(maxHeight: 150)
                .background(Color.black.opacity(0.8))
                .cornerRadius(6)
                .onHover { hovering in
                    isHoveringOverSuggestions = hovering
                    if !hovering && !isFocused {
                        isShowingSuggestions = false
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    private func applySuggestion(_ suggestion: SearchSuggestionItem) {
        text = suggestion.fullText
        isShowingSuggestions = false
    }
}

/// メモ編集用のポップオーバー
struct MemoEditPopover: View {
    @Binding var memo: String
    let providers: [any SearchSuggestionProvider]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L("memo_edit_title"))
                .font(.headline)

            SuggestingTextField(
                placeholder: L("memo_placeholder"),
                text: $memo,
                width: 300,
                providers: providers,
                onSubmit: onSave
            )

            HStack {
                Button(L("cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(L("save")) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

/// 一括メタデータ編集用のポップオーバー
struct BatchMetadataEditPopover: View {
    let itemCount: Int
    @Binding var metadataText: String
    let providers: [any SearchSuggestionProvider]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L("batch_metadata_edit_title"))
                .font(.headline)
            Text(String(format: L("batch_metadata_edit_count"), itemCount))
                .font(.caption)
                .foregroundColor(.secondary)

            SuggestingTextField(
                placeholder: L("batch_metadata_placeholder"),
                text: $metadataText,
                width: 300,
                providers: providers,
                onSubmit: onSave
            )

            HStack {
                Button(L("cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(L("save")) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - Flow Layout

/// タグチップの折り返し配置用レイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: containerWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Tag Chip

/// タグのチップ表示
struct TagChip: View {
    let tag: String
    let isPartial: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.callout)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isPartial ? 0.15 : 0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    Color.accentColor.opacity(isPartial ? 0.5 : 0),
                    style: StrokeStyle(lineWidth: 1, dash: isPartial ? [4, 3] : [])
                )
        )
        .opacity(isPartial ? 0.7 : 1.0)
        .help(isPartial ? L("metadata_partial_tooltip") : "")
    }
}

// MARK: - Structured Metadata Editor

/// 構造化メタデータ編集の結果
struct MetadataEditResult {
    /// 単一: 再構築されたメモ文字列
    let memo: String?
    /// 一括: 差分
    let tagsToAdd: Set<String>
    let tagsToRemove: Set<String>
    let attrsToAdd: [String: String]
    let attrsToRemove: Set<String>
}

/// 構造化メタデータ編集ビュー
struct StructuredMetadataEditor: View {
    let isBatch: Bool
    let itemCount: Int
    let metadataIndex: MemoMetadataParser.MetadataIndex
    @Binding var tags: Set<String>
    @Binding var partialTags: Set<String>
    @Binding var attributes: [(key: String, value: String)]
    @Binding var partialAttributes: [(key: String, value: String)]
    @Binding var plainText: String
    let originalTags: Set<String>
    let originalPartialTags: Set<String>
    let originalAttributes: [(key: String, value: String)]
    let originalPartialAttributes: [(key: String, value: String)]
    let onSave: (MetadataEditResult) -> Void
    let onCancel: () -> Void

    enum Tab { case tags, metadata }
    @State private var selectedTab: Tab = .tags
    @State private var newTagText: String = ""
    @State private var newAttrKey: String = ""
    @State private var newAttrValue: String = ""
    @State private var editingAttrIndex: Int? = nil
    @State private var editingAttrValue: String = ""

    // サジェスト用
    @State private var tagSuggestions: [String] = []
    @State private var showTagSuggestions: Bool = false
    @State private var tagSuggestionIndex: Int = 0
    @State private var keySuggestions: [String] = []
    @State private var showKeySuggestions: Bool = false
    @State private var keySuggestionIndex: Int = 0
    @State private var valueSuggestions: [String] = []
    @State private var showValueSuggestions: Bool = false
    @State private var valueSuggestionIndex: Int = 0
    @State private var suppressKeySuggestions: Bool = false

    @FocusState private var isTagFieldFocused: Bool
    @FocusState private var isKeyFieldFocused: Bool
    @FocusState private var isValueFieldFocused: Bool
    @FocusState private var isPlainTextFocused: Bool

    private let editorWidth: CGFloat = 350

    var body: some View {
        VStack(spacing: 12) {
            // ヘッダー
            if isBatch {
                Text(String(format: L("metadata_batch_count"), itemCount))
                    .font(.headline)
            } else {
                Text(L("metadata_edit_title"))
                    .font(.headline)
            }

            // メモ本文（単一選択時のみ）
            if !isBatch {
                TextField(L("metadata_edit_title"), text: $plainText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: editorWidth)
                    .focused($isPlainTextFocused)
                    .padding(.bottom, 12)
            }

            // タブ
            Picker("", selection: $selectedTab) {
                Text(L("metadata_tab_tags")).tag(Tab.tags)
                Text(L("metadata_tab_metadata")).tag(Tab.metadata)
            }
            .pickerStyle(.segmented)
            .frame(width: editorWidth)

            // タブコンテンツ
            Group {
                switch selectedTab {
                case .tags:
                    tagsTabContent
                case .metadata:
                    metadataTabContent
                }
            }
            .frame(width: editorWidth)

            // ボタン
            HStack(spacing: 12) {
                Button(L("cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button(L("save")) {
                    performSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture { }  // エディタ内のタップが背景に伝播しないようにする
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTagFieldFocused = true
            }
        }
    }

    // MARK: - Tags Tab

    private var tagsTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 既存タグのチップ表示
            if !tags.isEmpty || !partialTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags.sorted(), id: \.self) { tag in
                        TagChip(tag: tag, isPartial: false) {
                            tags.remove(tag)
                        }
                    }
                    ForEach(partialTags.sorted(), id: \.self) { tag in
                        TagChip(tag: tag, isPartial: true) {
                            partialTags.remove(tag)
                        }
                    }
                }
            }

            // タグ追加フィールド
            TextField(L("metadata_add_tag_placeholder"), text: $newTagText)
                .textFieldStyle(.roundedBorder)
                .focused($isTagFieldFocused)
                .onChange(of: newTagText) { _, newValue in
                    updateTagSuggestions(newValue)
                }
                .onChange(of: isTagFieldFocused) { _, focused in
                    if !focused { showTagSuggestions = false }
                }
                .onKeyPress(.tab) {
                    if showTagSuggestions && !tagSuggestions.isEmpty {
                        applyTagSuggestion(tagSuggestions[tagSuggestionIndex])
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if showTagSuggestions && !tagSuggestions.isEmpty {
                        tagSuggestionIndex = max(0, tagSuggestionIndex - 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    if showTagSuggestions && !tagSuggestions.isEmpty {
                        if tagSuggestionIndex < tagSuggestions.count - 1 {
                            tagSuggestionIndex += 1
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    if showTagSuggestions {
                        showTagSuggestions = false
                        return .handled
                    }
                    return .ignored
                }
                .onSubmit {
                    if showTagSuggestions && !tagSuggestions.isEmpty {
                        applyTagSuggestion(tagSuggestions[tagSuggestionIndex])
                    } else {
                        addTag()
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showTagSuggestions && !tagSuggestions.isEmpty {
                        suggestionsList(items: tagSuggestions, selectedIndex: tagSuggestionIndex) { item in
                            applyTagSuggestion(item)
                        }
                        .offset(y: 28)
                    }
                }
        }
    }

    // MARK: - Metadata Tab

    private var metadataTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 共通属性の表示
            ForEach(Array(attributes.enumerated()), id: \.offset) { index, attr in
                attributeRow(key: attr.key, value: attr.value, isPartial: false, index: index)
            }

            // 部分一致属性の表示（一括時のみ）
            if isBatch {
                ForEach(Array(partialAttributes.enumerated()), id: \.offset) { index, attr in
                    attributeRow(key: attr.key, value: attr.value, isPartial: true, index: index)
                }
            }

            // 属性追加行
            HStack(spacing: 6) {
                TextField(L("metadata_attr_key_placeholder"), text: $newAttrKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($isKeyFieldFocused)
                    .onChange(of: newAttrKey) { _, newValue in
                        if suppressKeySuggestions {
                            suppressKeySuggestions = false
                        } else {
                            updateKeySuggestions(newValue)
                        }
                    }
                    .onChange(of: isKeyFieldFocused) { _, focused in
                        if !focused { showKeySuggestions = false }
                    }
                    .onKeyPress(.tab) {
                        if showKeySuggestions && !keySuggestions.isEmpty {
                            applyKeySuggestion(keySuggestions[keySuggestionIndex])
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if showKeySuggestions && !keySuggestions.isEmpty {
                            keySuggestionIndex = max(0, keySuggestionIndex - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if showKeySuggestions && !keySuggestions.isEmpty {
                            if keySuggestionIndex < keySuggestions.count - 1 {
                                keySuggestionIndex += 1
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if showKeySuggestions {
                            showKeySuggestions = false
                            return .handled
                        }
                        return .ignored
                    }
                    .onSubmit {
                        if showKeySuggestions && !keySuggestions.isEmpty {
                            applyKeySuggestion(keySuggestions[keySuggestionIndex])
                        } else {
                            isValueFieldFocused = true
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if showKeySuggestions && !keySuggestions.isEmpty {
                            suggestionsList(items: keySuggestions, selectedIndex: keySuggestionIndex) { item in
                                applyKeySuggestion(item)
                            }
                            .offset(y: 28)
                        }
                    }

                TextField(L("metadata_attr_value_placeholder"), text: $newAttrValue)
                    .textFieldStyle(.roundedBorder)
                    .focused($isValueFieldFocused)
                    .onChange(of: newAttrValue) { _, newValue in
                        updateValueSuggestions(newValue)
                    }
                    .onChange(of: isValueFieldFocused) { _, focused in
                        if !focused { showValueSuggestions = false }
                    }
                    .onKeyPress(.tab) {
                        if showValueSuggestions && !valueSuggestions.isEmpty {
                            applyValueSuggestion(valueSuggestions[valueSuggestionIndex])
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if showValueSuggestions && !valueSuggestions.isEmpty {
                            valueSuggestionIndex = max(0, valueSuggestionIndex - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if showValueSuggestions && !valueSuggestions.isEmpty {
                            if valueSuggestionIndex < valueSuggestions.count - 1 {
                                valueSuggestionIndex += 1
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if showValueSuggestions {
                            showValueSuggestions = false
                            return .handled
                        }
                        return .ignored
                    }
                    .onSubmit {
                        if showValueSuggestions && !valueSuggestions.isEmpty {
                            applyValueSuggestion(valueSuggestions[valueSuggestionIndex])
                        } else {
                            addAttribute()
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if showValueSuggestions && !valueSuggestions.isEmpty {
                            suggestionsList(items: valueSuggestions, selectedIndex: valueSuggestionIndex) { item in
                                applyValueSuggestion(item)
                            }
                            .offset(y: 28)
                        }
                    }

                Button(action: addAttribute) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(newAttrKey.trimmingCharacters(in: .whitespaces).isEmpty
                    || newAttrValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Suggestions List

    private func suggestionsList(items: [String], selectedIndex: Int, onSelect: @escaping (String) -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Text(item)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.3) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(item) }
                }
            }
        }
        .frame(maxHeight: 120)
        .background(Color.black.opacity(0.8))
        .cornerRadius(6)
    }

    // MARK: - Attribute Row

    /// 編集中の部分属性インデックス（共通属性のeditingAttrIndexと区別）
    @State private var editingPartialAttrIndex: Int? = nil

    private func attributeRow(key: String, value: String, isPartial: Bool, index: Int) -> some View {
        let isEditing = isPartial
            ? editingPartialAttrIndex == index
            : editingAttrIndex == index

        return HStack(spacing: 6) {
            Text(key)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            if isEditing {
                TextField(L("metadata_attr_value_placeholder"), text: $editingAttrValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        commitAttrEdit(isPartial: isPartial, index: index)
                    }
            } else {
                Text(value)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 編集ボタン
            Button(action: {
                if isEditing {
                    commitAttrEdit(isPartial: isPartial, index: index)
                } else {
                    editingAttrValue = value
                    if isPartial {
                        editingPartialAttrIndex = index
                        editingAttrIndex = nil
                    } else {
                        editingAttrIndex = index
                        editingPartialAttrIndex = nil
                    }
                }
            }) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            // 削除ボタン
            Button(action: {
                if isPartial {
                    if editingPartialAttrIndex == index { editingPartialAttrIndex = nil }
                    partialAttributes.remove(at: index)
                } else {
                    if editingAttrIndex == index { editingAttrIndex = nil }
                    attributes.remove(at: index)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isPartial ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            isPartial ?
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        Color.accentColor.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                : nil
        )
        .help(isPartial ? L("metadata_partial_tooltip") : "")
    }

    /// 属性編集の確定（共通属性はそのまま更新、部分属性は共通に昇格）
    private func commitAttrEdit(isPartial: Bool, index: Int) {
        let newValue = editingAttrValue.trimmingCharacters(in: .whitespaces)
        if isPartial {
            let key = partialAttributes[index].key
            partialAttributes.remove(at: index)
            editingPartialAttrIndex = nil
            if !newValue.isEmpty {
                // 共通属性に昇格
                if let existingIndex = attributes.firstIndex(where: { $0.key == key }) {
                    attributes[existingIndex].value = newValue
                } else {
                    attributes.append((key: key, value: newValue))
                }
            }
        } else {
            if !newValue.isEmpty {
                attributes[index].value = newValue
            }
            editingAttrIndex = nil
        }
    }

    // MARK: - Tag Operations

    private func addTag() {
        let tag = newTagText
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "^#+", with: "", options: .regularExpression)
        guard !tag.isEmpty else { return }
        // partialから共通に昇格
        partialTags.remove(tag)
        tags.insert(tag)
        newTagText = ""
        showTagSuggestions = false
    }

    private func updateTagSuggestions(_ text: String) {
        let query = text
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "^#+", with: "", options: .regularExpression)
        guard !query.isEmpty else {
            showTagSuggestions = false
            return
        }
        let existing = tags.union(partialTags)
        tagSuggestions = metadataIndex.tags
            .filter { $0.contains(query) && !existing.contains($0) }
            .sorted()
        showTagSuggestions = !tagSuggestions.isEmpty
        tagSuggestionIndex = 0
    }

    private func applyTagSuggestion(_ suggestion: String) {
        newTagText = suggestion
        showTagSuggestions = false
        addTag()
    }

    // MARK: - Attribute Operations

    private func addAttribute() {
        let key = newAttrKey.trimmingCharacters(in: .whitespaces).lowercased()
        let value = newAttrValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty && !value.isEmpty else { return }
        // 部分属性から共通属性に昇格
        if let partialIndex = partialAttributes.firstIndex(where: { $0.key == key }) {
            partialAttributes.remove(at: partialIndex)
        }
        // 既存キーがあれば値を更新
        if let existingIndex = attributes.firstIndex(where: { $0.key == key }) {
            attributes[existingIndex].value = value
        } else {
            attributes.append((key: key, value: value))
        }
        newAttrKey = ""
        newAttrValue = ""
        showKeySuggestions = false
        showValueSuggestions = false
        isKeyFieldFocused = true
    }

    private func updateKeySuggestions(_ text: String) {
        let query = text
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !query.isEmpty else {
            showKeySuggestions = false
            return
        }
        let existingKeys = Set(attributes.map(\.key))
        keySuggestions = metadataIndex.keys
            .filter { $0.contains(query) && !existingKeys.contains($0) }
            .sorted()
        showKeySuggestions = !keySuggestions.isEmpty
        keySuggestionIndex = 0
    }

    private func applyKeySuggestion(_ suggestion: String) {
        suppressKeySuggestions = true
        newAttrKey = suggestion
        showKeySuggestions = false
        isValueFieldFocused = true
    }

    private func updateValueSuggestions(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        let key = newAttrKey.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty, !key.isEmpty,
              let availableValues = metadataIndex.values[key] else {
            showValueSuggestions = false
            return
        }
        valueSuggestions = availableValues
            .filter { $0.lowercased().contains(query) }
            .sorted()
        showValueSuggestions = !valueSuggestions.isEmpty
        valueSuggestionIndex = 0
    }

    private func applyValueSuggestion(_ suggestion: String) {
        newAttrValue = suggestion
        showValueSuggestions = false
        addAttribute()
    }

    // MARK: - Save

    private func performSave() {
        if isBatch {
            // 一括: 差分を計算
            let tagsToAdd = tags.subtracting(originalTags)
            // 削除: 元の共通タグにあって今ないもの + 元の部分タグにあって今ないもの（＝明示的削除）
            let tagsToRemove = originalTags.subtracting(tags)
                .union(originalPartialTags.subtracting(tags).subtracting(partialTags))

            let originalDict = Dictionary(originalAttributes.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
            let originalPartialDict = Dictionary(originalPartialAttributes.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
            let currentDict = Dictionary(attributes.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
            let currentPartialDict = Dictionary(partialAttributes.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })

            // 新規追加: 共通属性に新しく追加されたもの + 共通属性で値が変わったもの
            var attrsToAdd = currentDict.filter { originalDict[$0.key] != $0.value }
            // 共通属性から削除されたキー
            var attrsToRemove = Set(originalDict.keys).subtracting(currentDict.keys)
            // 部分属性で削除されたキー（元の部分属性にあって今どこにもないもの）
            let removedPartialKeys = Set(originalPartialDict.keys)
                .subtracting(currentPartialDict.keys)
                .subtracting(currentDict.keys)
            attrsToRemove.formUnion(removedPartialKeys)

            onSave(MetadataEditResult(
                memo: nil,
                tagsToAdd: tagsToAdd,
                tagsToRemove: tagsToRemove,
                attrsToAdd: attrsToAdd,
                attrsToRemove: attrsToRemove
            ))
        } else {
            // 単一: メモ文字列を再構築
            let memo = MemoMetadataParser.reconstructMemo(
                plainText: plainText,
                tags: tags,
                attributes: attributes
            )
            onSave(MetadataEditResult(
                memo: memo,
                tagsToAdd: [],
                tagsToRemove: [],
                attrsToAdd: [:],
                attrsToRemove: []
            ))
        }
    }
}

// MARK: - Window Number Getter

/// ウィンドウ番号を取得し、タイトルバーの設定を行うヘルパー
struct WindowNumberGetter: NSViewRepresentable {
    @Binding var windowNumber: Int?

    func makeNSView(context: Context) -> NSView {
        let view = WindowNumberGetterView()
        view.onWindowAttached = { window in
            configureWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // ビューが既にウィンドウに追加されている場合は設定
        if let view = nsView as? WindowNumberGetterView {
            view.onWindowAttached = { window in
                configureWindow(window)
            }
            if let window = nsView.window {
                configureWindow(window)
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        let newWindowNumber = window.windowNumber

        // タイトルバーの文字色を白に設定
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)

        // macOSのState Restorationを無効化（独自のセッション復元を使用）
        window.isRestorable = false

        // SwiftUIのウィンドウフレーム自動保存を無効化
        window.setFrameAutosaveName("")

        // ビュー更新サイクル外でStateを変更（undefined behavior回避）
        if self.windowNumber != newWindowNumber {
            DispatchQueue.main.async {
                DebugLogger.log("🪟 WindowNumberGetter: captured \(newWindowNumber) (was: \(String(describing: self.windowNumber)))", level: .normal)
                self.windowNumber = newWindowNumber
            }
        }
    }
}

/// ウィンドウへの追加を検出するカスタムNSView
private class WindowNumberGetterView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            DebugLogger.log("🪟 WindowNumberGetterView: viewDidMoveToWindow called with window \(window.windowNumber)", level: .normal)
            onWindowAttached?(window)
        }
    }
}

