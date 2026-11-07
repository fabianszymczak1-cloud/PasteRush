import AppKit

/// The Mac App Store build may not use Accessibility to auto-paste (guideline 2.4.5)
/// or link to outside payments (3.1.1). The store app sets these at launch.
public enum Distribution {
    public static var isAppStore = false
    public static var presentSupport: () -> Void = {
        NSWorkspace.shared.open(SupportLinks.buyMeACoffee)
    }

    static func tr(_ key: String) -> String {
        L10n.tr(isAppStore ? key + "_store" : key)
    }
}
