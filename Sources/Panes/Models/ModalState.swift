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
}
