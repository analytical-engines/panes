import Foundation

enum AppInfo {
    static let name = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Panes"
}
