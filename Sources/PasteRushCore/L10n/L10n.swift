import Foundation

/// Localized strings from PasteRushCore resource bundle (EN development language, PL secondary).
public enum L10n {
    private static let resourceBundle: Bundle = {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "PasteRush_PasteRushCore", withExtension: "bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/PasteRush_PasteRushCore.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("PasteRush_PasteRushCore.bundle")
        ]
        for url in candidates {
            if let url, let bundle = Bundle(url: url) {
                return bundle
            }
        }
        // Fallback for `swift run` / SPM build directory via generated accessor
        return Bundle.module
    }()

    public static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: resourceBundle, value: key, comment: "")
    }

    public static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: args)
    }
}
