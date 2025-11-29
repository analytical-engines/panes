import Foundation
import CoreGraphics

/// ウィンドウセッションのエントリ（1ウィンドウ分の状態）
struct WindowSessionEntry: Codable, Identifiable {
    let id: UUID
    let filePath: String
    let fileKey: String?
    let currentPage: Int
    let windowFrame: CodableCGRect
    let createdAt: Date

    /// ファイルがアクセス可能かどうか
    var isFileAccessible: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }

    init(
        id: UUID = UUID(),
        filePath: String,
        fileKey: String?,
        currentPage: Int,
        windowFrame: CGRect,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.fileKey = fileKey
        self.currentPage = currentPage
        self.windowFrame = CodableCGRect(rect: windowFrame)
        self.createdAt = createdAt
    }

    /// CGRectを取得
    var frame: CGRect {
        windowFrame.rect
    }
}

/// CGRectをCodableに対応させるラッパー
struct CodableCGRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
