import SwiftUI

/// モーダル表示状態を管理するクラス
/// ContentViewごとに独立したインスタンスを持つ（ウィンドウローカル）
@Observable
class ModalState {
    // MARK: - 画像情報モーダル

    var showImageInfo = false

    func toggleImageInfo() {
        showImageInfo.toggle()
    }

    // MARK: - メモ編集モーダル

    var showMemoEdit = false
    var editingMemoText = ""
    var editingMemoFileKey: String?
    var editingImageCatalogId: String?

    /// 履歴エントリのメモ編集を開く
    func openMemoEditForHistory(fileKey: String, memo: String?) {
        editingMemoFileKey = fileKey
        editingImageCatalogId = nil
        editingMemoText = memo ?? ""
        showMemoEdit = true
    }

    /// 画像カタログのメモ編集を開く
    func openMemoEditForCatalog(catalogId: String, memo: String?) {
        editingImageCatalogId = catalogId
        editingMemoFileKey = nil
        editingMemoText = memo ?? ""
        showMemoEdit = true
    }

    /// 現在開いているファイルのメモ編集を開く
    func openMemoEditForCurrentFile(fileKey: String?, memo: String?) {
        editingMemoFileKey = fileKey
        editingImageCatalogId = nil
        editingMemoText = memo ?? ""
        showMemoEdit = true
    }

    /// メモ編集を閉じる
    func closeMemoEdit() {
        showMemoEdit = false
        editingMemoFileKey = nil
        editingImageCatalogId = nil
    }

    /// 編集中のメモテキストを取得（空文字列の場合はnilを返す）
    var finalMemoText: String? {
        editingMemoText.isEmpty ? nil : editingMemoText
    }

    // MARK: - 一括メタデータ編集モーダル

    var showBatchMetadataEdit = false
    var batchMetadataText = ""
    var batchMetadataOriginal = ""
    var batchMetadataTargets: [(historyId: String?, catalogId: String?)] = []

    func openBatchMetadataEdit(commonMetadataText: String, targets: [(historyId: String?, catalogId: String?)]) {
        batchMetadataOriginal = commonMetadataText
        batchMetadataText = commonMetadataText
        batchMetadataTargets = targets
        showBatchMetadataEdit = true
    }

    func closeBatchMetadataEdit() {
        showBatchMetadataEdit = false
        batchMetadataTargets = []
    }

    // MARK: - 構造化メタデータ編集モーダル

    var showStructuredMetadataEdit = false
    /// 単一編集時のファイルキー
    var structuredEditFileKey: String?
    /// 単一編集時のカタログID
    var structuredEditCatalogId: String?
    /// 一括編集時のターゲット
    var structuredEditTargets: [(historyId: String?, catalogId: String?)] = []
    /// 編集中のタグ（全アイテム共通）
    var structuredEditTags: Set<String> = []
    /// 一部のアイテムのみに存在するタグ（一括時）
    var structuredEditPartialTags: Set<String> = []
    /// 編集中の属性（全アイテム共通）
    var structuredEditAttributes: [(key: String, value: String)] = []
    /// 一部のアイテムのみに存在する属性（一括時）
    var structuredEditPartialAttributes: [(key: String, value: String)] = []
    /// メモ本文（単一時のみ）
    var structuredEditPlainText: String = ""
    /// 元のタグ（差分計算用）
    var structuredEditOriginalTags: Set<String> = []
    /// 元の部分タグ（差分計算用）
    var structuredEditOriginalPartialTags: Set<String> = []
    /// 元の属性（差分計算用）
    var structuredEditOriginalAttributes: [(key: String, value: String)] = []
    /// 元の部分属性（差分計算用）
    var structuredEditOriginalPartialAttributes: [(key: String, value: String)] = []

    /// 単一アイテムの構造化編集を開く
    func openStructuredEditForSingle(fileKey: String?, catalogId: String?, memo: String?) {
        let parsed = MemoMetadataParser.parse(memo)
        structuredEditFileKey = fileKey
        structuredEditCatalogId = catalogId
        structuredEditTargets = []
        structuredEditTags = parsed.tags
        structuredEditPartialTags = []
        structuredEditAttributes = parsed.attributes.sorted(by: { $0.key < $1.key }).map { (key: $0.key, value: $0.value) }
        structuredEditPartialAttributes = []
        structuredEditPlainText = parsed.plainText
        structuredEditOriginalTags = parsed.tags
        structuredEditOriginalPartialTags = []
        structuredEditOriginalAttributes = structuredEditAttributes
        structuredEditOriginalPartialAttributes = []
        showStructuredMetadataEdit = true
    }

    /// 一括アイテムの構造化編集を開く
    func openStructuredEditForBatch(
        commonTags: Set<String>,
        partialTags: Set<String>,
        commonAttrs: [String: String],
        partialAttrs: [(key: String, value: String)],
        targets: [(historyId: String?, catalogId: String?)]
    ) {
        structuredEditFileKey = nil
        structuredEditCatalogId = nil
        structuredEditTargets = targets
        structuredEditTags = commonTags
        structuredEditPartialTags = partialTags
        structuredEditAttributes = commonAttrs.sorted(by: { $0.key < $1.key }).map { (key: $0.key, value: $0.value) }
        structuredEditPartialAttributes = partialAttrs
        structuredEditPlainText = ""
        structuredEditOriginalTags = commonTags
        structuredEditOriginalPartialTags = partialTags
        structuredEditOriginalAttributes = structuredEditAttributes
        structuredEditOriginalPartialAttributes = partialAttrs
        showStructuredMetadataEdit = true
    }

    /// 構造化メタデータ編集を閉じる
    func closeStructuredMetadataEdit() {
        showStructuredMetadataEdit = false
        structuredEditFileKey = nil
        structuredEditCatalogId = nil
        structuredEditTargets = []
    }

    /// 一括モードかどうか
    var isStructuredEditBatch: Bool {
        !structuredEditTargets.isEmpty
    }
}
