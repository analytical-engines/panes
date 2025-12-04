import Foundation
import AppKit
import SwiftUI

/// ウィンドウで開くファイルの情報
struct PendingFileOpen {
    let filePath: String
    let fileKey: String?
    let currentPage: Int
    let frame: CGRect?
    let isSessionRestore: Bool  // セッション復元かどうか

    /// 「このアプリケーションで開く」用の初期化
    init(url: URL) {
        self.filePath = url.path
        self.fileKey = nil
        self.currentPage = 0
        self.frame = nil
        self.isSessionRestore = false
    }

    /// セッション復元用の初期化
    init(from entry: WindowSessionEntry) {
        self.filePath = entry.filePath
        self.fileKey = entry.fileKey
        self.currentPage = entry.currentPage
        self.frame = entry.frame
        self.isSessionRestore = true
    }
}

/// セッション（ウィンドウ状態）の管理クラス
@MainActor
@Observable
class SessionManager {
    private let sessionKey = "windowSession"
    private let defaults = UserDefaults.standard

    /// 保存されたセッション
    private(set) var savedSession: [WindowSessionEntry] = []

    /// 開くべきファイルのキュー（セッション復元 + 「このアプリケーションで開く」を統合）
    private(set) var pendingFileOpens: [PendingFileOpen] = []

    /// 現在のアクティブなウィンドウ（追跡用）
    private(set) var activeWindows: [UUID: WindowSessionEntry] = [:]

    /// 現在読み込み中のウィンドウ数
    private(set) var currentLoadingCount: Int = 0

    /// ファイルオープン処理中かどうか
    private(set) var isProcessing: Bool = false

    /// 同時読み込み制限（AppSettingsから設定される）
    var concurrentLoadingLimit: Int = 1

    /// 次に開くべきファイル情報（ウィンドウに渡す用）
    var pendingFileOpen: PendingFileOpen?

    /// 最初のウィンドウを使ったかどうか
    private var isFirstWindowUsed: Bool = false

    /// 処理完了したウィンドウ数
    private var processedWindowCount: Int = 0

    /// 処理対象のウィンドウ総数
    private var totalWindowsToProcess: Int = 0

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

    // MARK: - File Open Queue

    /// 「このアプリケーションで開く」からファイルをキューに追加
    func addFilesToOpen(urls: [URL]) {
        let items = urls.map { PendingFileOpen(url: $0) }
        addToQueue(items)
    }

    /// セッション復元を開始する
    func startRestoration() {
        guard !savedSession.isEmpty else {
            DebugLogger.log("📂 No session to restore", level: .normal)
            return
        }
        let items = savedSession.map { PendingFileOpen(from: $0) }
        addToQueue(items)
    }

    /// キューにアイテムを追加（統合メソッド）
    private func addToQueue(_ items: [PendingFileOpen]) {
        pendingFileOpens.append(contentsOf: items)
        DebugLogger.log("📂 Added \(items.count) files to queue (total: \(pendingFileOpens.count))", level: .normal)

        if isProcessing {
            // 処理中：totalを更新してダイアログ表示
            let newTotal = processedWindowCount + pendingFileOpens.count + currentLoadingCount
            if newTotal > totalWindowsToProcess {
                totalWindowsToProcess = newTotal
                DebugLogger.log("📂 Updated total to \(totalWindowsToProcess)", level: .normal)

                if totalWindowsToProcess > 1 && loadingPanel == nil {
                    showLoadingPanel()
                } else {
                    updateLoadingProgress()
                }
            }
        } else {
            // 未処理：処理開始をスケジュール
            scheduleProcessingIfNeeded()
        }
    }

    /// 処理開始をスケジュール
    private var processingScheduled = false

    private func scheduleProcessingIfNeeded() {
        guard !processingScheduled else { return }
        processingScheduled = true

        // 少し待ってから処理（複数ソースからの追加を待つ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.processingScheduled = false
            if !self.isProcessing && !self.pendingFileOpens.isEmpty {
                self.startProcessing()
            }
        }
    }

    /// ファイルオープン処理を開始
    private func startProcessing() {
        guard !pendingFileOpens.isEmpty else { return }

        isProcessing = true
        isFirstWindowUsed = false
        processedWindowCount = 0
        totalWindowsToProcess = pendingFileOpens.count

        DebugLogger.log("🔄 Starting file open processing: \(totalWindowsToProcess) files", level: .normal)

        // 複数ファイルの場合はローディングパネルを表示
        if totalWindowsToProcess > 1 {
            showLoadingPanel()
        }

        // 処理開始
        processNextFile()
    }

    /// 次のファイルを処理する
    func processNextFile() {
        guard isProcessing else { return }
        guard currentLoadingCount < concurrentLoadingLimit else {
            DebugLogger.log("⏳ Loading limit reached (\(currentLoadingCount)/\(concurrentLoadingLimit)), waiting...", level: .verbose)
            return
        }
        guard !pendingFileOpens.isEmpty else {
            DebugLogger.log("📋 All files queued for opening", level: .verbose)
            return
        }

        let fileOpen = pendingFileOpens.removeFirst()
        currentLoadingCount += 1

        DebugLogger.log("🪟 Opening file: \(fileOpen.filePath) (\(currentLoadingCount)/\(concurrentLoadingLimit))", level: .normal)

        pendingFileOpen = fileOpen

        if !isFirstWindowUsed {
            // 最初のファイル：起動時に作成されたウィンドウを使用
            isFirstWindowUsed = true
            NotificationCenter.default.post(
                name: .openFileInFirstWindow,
                object: nil,
                userInfo: nil
            )
        } else {
            // 2つ目以降のファイル：新しいウィンドウを作成
            NotificationCenter.default.post(
                name: .needNewWindow,
                object: nil,
                userInfo: nil
            )
        }
    }

    /// ウィンドウの読み込み完了を通知する
    func windowDidFinishLoading(id: UUID) {
        currentLoadingCount = max(0, currentLoadingCount - 1)
        processedWindowCount += 1
        DebugLogger.log("✅ Window finished loading: \(id) (\(processedWindowCount)/\(totalWindowsToProcess))", level: .normal)

        // ローディングパネルの進捗を更新
        updateLoadingProgress()

        // 全ウィンドウの処理が完了したかチェック
        if processedWindowCount >= totalWindowsToProcess && pendingFileOpens.isEmpty {
            DebugLogger.log("🎉 All files opened!", level: .normal)
            finishProcessing()
        } else {
            // 次のファイルを処理
            processNextFile()
        }
    }

    /// 処理完了
    private func finishProcessing() {
        isProcessing = false
        isFirstWindowUsed = false
        processedWindowCount = 0
        totalWindowsToProcess = 0

        // ローディングパネルを閉じる
        hideLoadingPanel()

        // 全ウィンドウを一斉に表示する通知（セッション復元の場合）
        NotificationCenter.default.post(name: .revealAllWindows, object: nil)

        DebugLogger.log("✅ File open processing complete", level: .normal)
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
            restoredCount: processedWindowCount,
            totalCount: totalWindowsToProcess
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
                restoredCount: processedWindowCount,
                totalCount: totalWindowsToProcess
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
                Text(L("opening_windows"))
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
    /// 最初のウィンドウでファイルを開く通知
    static let openFileInFirstWindow = NSNotification.Name("OpenFileInFirstWindow")

    /// 新しいウィンドウ作成リクエスト（2つ目以降のファイル用）
    static let needNewWindow = NSNotification.Name("NeedNewWindow")

    /// 全ウィンドウ一斉表示通知
    static let revealAllWindows = NSNotification.Name("RevealAllWindowsAfterRestoration")
}
