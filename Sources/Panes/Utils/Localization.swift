import Foundation

/// リソースバンドルを取得（Swift Package Manager と Xcode プロジェクト両対応）
private var resourceBundle: Bundle {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle.main
    #endif
}

/// ローカライズ用バンドルを取得
private let localizedBundle: Bundle = {
    // ユーザーの優先言語を取得
    let preferredLanguages = Locale.preferredLanguages
    let supportedLanguages = ["ja", "en"]

    DebugLogger.log("🌐 Locale.preferredLanguages: \(preferredLanguages)", level: .verbose)

    // 優先言語から対応する言語を探す
    var selectedLanguage = "en" // デフォルト
    for lang in preferredLanguages {
        let langCode = lang.components(separatedBy: "-").first ?? lang
        if supportedLanguages.contains(langCode) {
            selectedLanguage = langCode
            break
        }
    }

    DebugLogger.log("🌐 Selected language: \(selectedLanguage)", level: .verbose)

    // 対応する.lprojバンドルを取得
    if let path = resourceBundle.path(forResource: selectedLanguage, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        DebugLogger.log("🌐 Localization bundle loaded: \(path)", level: .verbose)
        return bundle
    }

    DebugLogger.log("🌐 Localization bundle not found, using default", level: .normal)
    return resourceBundle
}()

/// ローカライズ文字列を取得するヘルパー関数
func L(_ key: String) -> String {
    return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
}

/// フォーマット付きローカライズ文字列を取得するヘルパー関数（1引数）
func L(_ key: String, _ arg1: any CVarArg) -> String {
    let format = localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    return String(format: format, arg1)
}

/// フォーマット付きローカライズ文字列を取得するヘルパー関数（2引数）
func L(_ key: String, _ arg1: any CVarArg, _ arg2: any CVarArg) -> String {
    let format = localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    return String(format: format, arg1, arg2)
}

/// フォーマット付きローカライズ文字列を取得するヘルパー関数（3引数）
func L(_ key: String, _ arg1: any CVarArg, _ arg2: any CVarArg, _ arg3: any CVarArg) -> String {
    let format = localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
    return String(format: format, arg1, arg2, arg3)
}
