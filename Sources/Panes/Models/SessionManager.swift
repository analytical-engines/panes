import Foundation
import AppKit
import SwiftUI

/// セッション（ウィンドウ状態）の管理クラス
@MainActor
@Observable
class SessionManager {
    private let sessionKey = "windowSession"
    private let defaults = UserDefaults.standard

    /// 保存されたセッション
    private(set) var savedSession: [WindowSessionEntry] = []

    /// 復元待ちのエントリ
    private(set) var pendingRestorations: [WindowSessionEntry] = []

    /// 現在のアクティブなウィンドウ（追跡用）
    private(set) var activeWindows: [UUID: WindowSessionEntry] = [:]

    /// 現在読み込み中のウィンドウ数
    private(set) var currentLoadingCount: Int = 0

    /// 復元中かどうか
    private(set) var isRestoring: Bool = false

    /// 同時読み込み制限（AppSettingsから設定される）
    var concurrentLoadingLimit: Int = 1

    /// 新しいウィンドウで復元すべきエントリ（2つ目以降のウィンドウ用）
    var pendingRestoreEntry: WindowSessionEntry?

    /// 最初のウィンドウの復元が完了したかどうか
    private var isFirstWindowRestored: Bool = false

    /// 復元完了したウィンドウ数
    private var restoredWindowCount: Int = 0

    /// 復元対象のウィンドウ総数
    private var totalWindowsToRestore: Int = 0

    /// ローディングパネル
    private var loadingPanel: NSPanel?

    init() {
        loadSession()
    }

    // MARK: - Persistence

    /// 保存されたセッションを読み込む
    func loadSession() {
        guard let data = defaults.data(forKey: sessionKey),
              let decoded = try? JSONDecoder().decode([WindowSessionEntry].self, from: data) else {
            savedSession = []
            return
        }
        savedSession = decoded
        DebugLogger.log("📂 Session loaded: \(savedSession.count) windows", level: .normal)
    }

    /// セッションを保存する
    func saveSession(_ entries: [WindowSessionEntry]) {
        guard let encoded = try? JSONEncoder().encode(entries) else {
            DebugLogger.log("❌ Failed to encode session", level: .normal)
            return
        }
        defaults.set(encoded, forKey: sessionKey)
        savedSession = entries
        DebugLogger.log("💾 Session saved: \(entries.count) windows", level: .normal)
        for entry in entries {
            DebugLogger.log("💾   - \(entry.filePath) frame: \(entry.frame)", level: .normal)
        }
    }

    /// セッションをクリアする
    func clearSession() {
        defaults.removeObject(forKey: sessionKey)
        savedSession = []
        DebugLogger.log("🗑️ Session cleared", level: .normal)
    }

    // MARK: - Restoration Queue

    /// セッション復元を開始する
    func startRestoration() {
        guard !savedSession.isEmpty else {
            DebugLogger.log("📂 No session to restore", level: .normal)
            return
        }

        isRestoring = true
        pendingRestorations = savedSession
        totalWindowsToRestore = savedSession.count
        restoredWindowCount = 0
        DebugLogger.log("🔄 Starting session restoration: \(pendingRestorations.count) windows", level: .normal)

        // ローディングパネルを表示
        showLoadingPanel()

        // 復元キューを処理開始
        processNextPendingWindow()
    }

    /// 次の待機中ウィンドウを処理する
    func processNextPendingWindow() {
        guard isRestoring else { return }
        guard currentLoadingCount < concurrentLoadingLimit else {
            DebugLogger.log("⏳ Loading limit reached (\(currentLoadingCount)/\(concurrentLoadingLimit)), waiting...", level: .verbose)
            return
        }
        guard !pendingRestorations.isEmpty else {
            // すべてのウィンドウの読み込み開始が完了（読み込み自体はまだ進行中かもしれない）
            DebugLogger.log("📋 All windows queued for restoration", level: .verbose)
            return
        }

        let entry = pendingRestorations.removeFirst()
        currentLoadingCount += 1

        DebugLogger.log("🪟 Restoring window: \(entry.filePath) (\(currentLoadingCount)/\(concurrentLoadingLimit))", level: .normal)

        if !isFirstWindowRestored {
            // 最初のウィンドウ：起動時に作成されたウィンドウを使用
            isFirstWindowRestored = true
            NotificationCenter.default.post(
                name: .restoreWindow,
                object: nil,
                userInfo: ["entry": entry]
            )
        } else {
            // 2つ目以降のウィンドウ：新しいウィンドウを作成する必要がある
            pendingRestoreEntry = entry
            NotificationCenter.default.post(
                name: .needNewRestoreWindow,
                object: nil,
                userInfo: nil
            )
        }
    }

    /// ウィンドウの読み込み完了を通知する
    func windowDidFinishLoading(id: UUID) {
        currentLoadingCount = max(0, currentLoadingCount - 1)
        restoredWindowCount += 1
        DebugLogger.log("✅ Window finished loading: \(id) (\(restoredWindowCount)/\(totalWindowsToRestore))", level: .normal)

        // ローディングパネルの進捗を更新
        updateLoadingProgress()

        // 全ウィンドウの復元が完了したかチェック
        if restoredWindowCount >= totalWindowsToRestore && pendingRestorations.isEmpty {
            DebugLogger.log("🎉 All windows restored! Revealing windows...", level: .normal)
            finishRestoration()
        } else {
            // 次のウィンドウを処理
            processNextPendingWindow()
        }
    }

    /// 復元完了処理
    private func finishRestoration() {
        isRestoring = false
        isFirstWindowRestored = false
        restoredWindowCount = 0
        totalWindowsToRestore = 0

        // ローディングパネルを閉じる
        hideLoadingPanel()

        // 全ウィンドウを一斉に表示する通知
        NotificationCenter.default.post(name: .revealAllWindows, object: nil)

        DebugLogger.log("✅ Session restoration complete", level: .normal)
    }

    /// 復元エントリを取得する（ContentViewから呼ばれる）
    func getNextRestorationEntry() -> WindowSessionEntry? {
        // 最後にpostされたエントリを返す
        // （NotificationCenter経由で渡されるため、ここでは使用しない）
        return nil
    }

    // MARK: - Window Tracking

    /// ウィンドウを登録する
    func registerWindow(id: UUID, filePath: String, fileKey: String?, currentPage: Int, frame: CGRect) {
        let entry = WindowSessionEntry(
            id: id,
            filePath: filePath,
            fileKey: fileKey,
            currentPage: currentPage,
            windowFrame: frame
        )
        activeWindows[id] = entry
        DebugLogger.log("📝 Window registered: \(id) frame: \(frame)", level: .normal)
    }

    /// ウィンドウのフレームを更新する
    func updateWindowFrame(id: UUID, frame: CGRect) {
        guard let entry = activeWindows[id] else { return }
        let updated = WindowSessionEntry(
            id: entry.id,
            filePath: entry.filePath,
            fileKey: entry.fileKey,
            currentPage: entry.currentPage,
            windowFrame: frame,
            createdAt: entry.createdAt
        )
        activeWindows[id] = updated
    }

    /// ウィンドウの状態を更新する
    func updateWindowState(id: UUID, currentPage: Int) {
        guard let entry = activeWindows[id] else { return }
        let updated = WindowSessionEntry(
            id: entry.id,
            filePath: entry.filePath,
            fileKey: entry.fileKey,
            currentPage: currentPage,
            windowFrame: entry.frame,
            createdAt: entry.createdAt
        )
        activeWindows[id] = updated
    }

    /// ウィンドウを削除する
    func removeWindow(id: UUID) {
        activeWindows.removeValue(forKey: id)
        DebugLogger.log("🗑️ Window removed: \(id)", level: .verbose)
    }

    /// 現在のすべてのウィンドウ状態を取得する
    func collectCurrentWindowStates() -> [WindowSessionEntry] {
        return Array(activeWindows.values)
    }

    // MARK: - Loading Panel

    /// ローディングパネルを表示する
    private func showLoadingPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        // SwiftUIビューをホスト
        let hostingView = NSHostingView(rootView: LoadingPanelContent(
            restoredCount: restoredWindowCount,
            totalCount: totalWindowsToRestore
        ))
        panel.contentView = hostingView

        panel.center()
        panel.makeKeyAndOrderFront(nil)

        loadingPanel = panel
        DebugLogger.log("📋 Loading panel shown", level: .normal)
    }

    /// ローディングパネルを閉じる
    private func hideLoadingPanel() {
        loadingPanel?.close()
        loadingPanel = nil
        DebugLogger.log("📋 Loading panel hidden", level: .normal)
    }

    /// ローディングパネルの進捗を更新する
    func updateLoadingProgress() {
        if let panel = loadingPanel {
            let hostingView = NSHostingView(rootView: LoadingPanelContent(
                restoredCount: restoredWindowCount,
                totalCount: totalWindowsToRestore
            ))
            panel.contentView = hostingView
        }
    }
}

// MARK: - Loading Panel Content

/// ローディングパネルの内容
private struct LoadingPanelContent: View {
    let restoredCount: Int
    let totalCount: Int

    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            // スピナー
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.gray, lineWidth: 3)
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            VStack(spacing: 4) {
                Text(L("restoring_session"))
                    .font(.headline)
                Text("\(restoredCount) / \(totalCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 280, height: 120)
    }
}

// MARK: - Notification Names

extension NSNotification.Name {
    /// ウィンドウ復元通知
    static let restoreWindow = NSNotification.Name("RestoreWindowFromSession")

    /// 新しいウィンドウ作成リクエスト（2つ目以降のセッション復元用）
    static let needNewRestoreWindow = NSNotification.Name("NeedNewRestoreWindow")

    /// ウィンドウ状態収集通知
    static let collectWindowState = NSNotification.Name("CollectWindowStateForSession")

    /// 全ウィンドウ一斉表示通知
    static let revealAllWindows = NSNotification.Name("RevealAllWindowsAfterRestoration")
}
