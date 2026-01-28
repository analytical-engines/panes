import Foundation
import CoreGraphics

/// セッショングループ（名前付きのウィンドウ状態のまとまり）
struct SessionGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var lastAccessedAt: Date
    var entries: [SessionGroupEntry]

    /// ワークスペースID（""=デフォルト、将来のworkspace機能で使用）
    var workspaceId: String = ""

    /// ファイル数
    var fileCount: Int {
        entries.count
    }

    /// アクセス可能なファイル数
    var accessibleFileCount: Int {
        entries.filter { $0.isFileAccessible }.count
    }

    init(
        id: UUID = UUID(),
        name: String,
        entries: [SessionGroupEntry],
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    /// 現在のウィンドウ状態から作成
    init(name: String, from windowEntries: [WindowSessionEntry]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.entries = windowEntries.map { SessionGroupEntry(from: $0) }
    }
}

/// セッショングループ内のエントリ（1ファイル分の情報）
struct SessionGroupEntry: Codable, Identifiable {
    let id: UUID
    let filePath: String
    let fileKey: String?
    let currentPage: Int
    let windowFrame: CodableCGRect?

    /// ファイルがアクセス可能かどうか
    var isFileAccessible: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    /// ファイル名
    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    init(
        id: UUID = UUID(),
        filePath: String,
        fileKey: String?,
        currentPage: Int,
        windowFrame: CGRect? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.fileKey = fileKey
        self.currentPage = currentPage
        self.windowFrame = windowFrame.map { CodableCGRect(rect: $0) }
    }

    /// WindowSessionEntryから作成
    init(from windowEntry: WindowSessionEntry) {
        self.id = UUID()
        self.filePath = windowEntry.filePath
        self.fileKey = windowEntry.fileKey
        self.currentPage = windowEntry.currentPage
        self.windowFrame = windowEntry.windowFrame
    }

    /// CGRectを取得
    var frame: CGRect? {
        windowFrame?.rect
    }

    /// PendingFileOpenに変換
    func toPendingFileOpen() -> PendingFileOpen {
        let entry = WindowSessionEntry(
            filePath: filePath,
            fileKey: fileKey,
            currentPage: currentPage,
            windowFrame: frame ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        )
        return PendingFileOpen(from: entry)
    }
}
