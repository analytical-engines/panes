import Foundation
import AppKit

/// GitHub Releasesを監視してアップデートを通知する
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "analytical-engines"
    private let repoName = "panes"

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
        }
    }

    /// 起動時にアップデートを確認（設定が有効な場合のみ、サイレント）
    func checkForUpdatesIfNeeded(settings: AppSettings) {
        #if DEBUG
        // DEBUGビルドではバージョンが開発中の値のためスキップ
        return
        #else
        guard settings.checkForUpdatesOnLaunch else { return }
        performCheck(silent: true)
        #endif
    }

    /// 手動でアップデートを確認（メニューから呼び出し用、結果を常に表示）
    func checkForUpdates() {
        performCheck(silent: false)
    }

    /// アップデート確認の実行
    /// - Parameter silent: trueの場合、最新版/エラー時はダイアログを表示しない
    private func performCheck(silent: Bool) {
        Task {
            do {
                let release = try await fetchLatestRelease()
                let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let current = AppInfo.version
                if compareVersions(latest, isNewerThan: current) {
                    showUpdateDialog(latestVersion: latest, releaseNotes: release.body, htmlURL: release.htmlURL)
                } else if !silent {
                    showUpToDateDialog()
                }
            } catch {
                if !silent {
                    showUpToDateDialog()
                }
            }
        }
    }

    // MARK: - Private

    /// GitHub Releases APIから最新リリースを取得
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// セマンティックバージョニングの比較（latest > current なら true）
    func compareVersions(_ latest: String, isNewerThan current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(latestParts.count, currentParts.count)
        for i in 0..<maxCount {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    /// アップデート通知ダイアログを表示
    private func showUpdateDialog(latestVersion: String, releaseNotes: String?, htmlURL: URL) {
        let alert = NSAlert()
        alert.messageText = L("update_available_title")
        alert.informativeText = L("update_available_message", latestVersion, AppInfo.version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("update_download"))
        alert.addButton(withTitle: L("update_later"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(htmlURL)
        }
    }

    /// 最新版を使用中のダイアログを表示
    private func showUpToDateDialog() {
        let alert = NSAlert()
        alert.messageText = L("update_up_to_date_title")
        alert.informativeText = L("update_up_to_date_message", AppInfo.version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("ok"))

        alert.runModal()
    }
}
