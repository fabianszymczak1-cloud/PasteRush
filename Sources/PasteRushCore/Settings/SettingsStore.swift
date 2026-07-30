import Foundation
import Combine

public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let prefix = "PasteRush."

    @Published public var hasCompletedOnboarding: Bool {
        didSet { set("hasCompletedOnboarding", hasCompletedOnboarding) }
    }
    @Published public var openHotkeyKeyCode: UInt32 {
        didSet { set("openHotkeyKeyCode", Int(openHotkeyKeyCode)) }
    }
    @Published public var openHotkeyModifiers: UInt32 {
        didSet { set("openHotkeyModifiers", Int(openHotkeyModifiers)) }
    }
    @Published public var popupPositionMode: PopupPositionMode {
        didSet { set("popupPositionMode", popupPositionMode.rawValue) }
    }
    @Published public var rememberPopupFrame: Bool {
        didSet { set("rememberPopupFrame", rememberPopupFrame) }
    }
    @Published public var popupWidth: Double {
        didSet { set("popupWidth", popupWidth) }
    }
    @Published public var popupHeight: Double {
        didSet { set("popupHeight", popupHeight) }
    }
    @Published public var popupOpacity: Double {
        didSet { set("popupOpacity", popupOpacity) }
    }
    @Published public var alwaysOnTop: Bool {
        didSet { set("alwaysOnTop", alwaysOnTop) }
    }
    @Published public var keepOpenAfterPaste: Bool {
        didSet { set("keepOpenAfterPaste", keepOpenAfterPaste) }
    }
    @Published public var closeOnFocusLoss: Bool {
        didSet { set("closeOnFocusLoss", closeOnFocusLoss) }
    }
    @Published public var listLineCount: Int {
        didSet { set("listLineCount", listLineCount) }
    }
    @Published public var showThumbnails: Bool {
        didSet { set("showThumbnails", showThumbnails) }
    }
    @Published public var thumbnailSize: Double {
        didSet { set("thumbnailSize", thumbnailSize) }
    }
    @Published public var listDensity: Double {
        didSet { set("listDensity", listDensity) }
    }
    @Published public var fontSize: Double {
        didSet { set("fontSize", fontSize) }
    }
    @Published public var showUseCount: Bool {
        didSet { set("showUseCount", showUseCount) }
    }
    @Published public var allowDuplicates: Bool {
        didSet { set("allowDuplicates", allowDuplicates) }
    }
    @Published public var bumpDuplicatesToTop: Bool {
        didSet { set("bumpDuplicatesToTop", bumpDuplicatesToTop) }
    }
    @Published public var maxEntries: Int {
        didSet { set("maxEntries", maxEntries) }
    }
    @Published public var maxDatabaseBytes: Int {
        didSet { set("maxDatabaseBytes", maxDatabaseBytes) }
    }
    @Published public var maxAgeDays: Int {
        didSet { set("maxAgeDays", maxAgeDays) }
    }
    @Published public var maxImageEntries: Int {
        didSet { set("maxImageEntries", maxImageEntries) }
    }
    @Published public var warnLowDiskBytes: Int {
        didSet { set("warnLowDiskBytes", warnLowDiskBytes) }
    }
    @Published public var isMonitoringPaused: Bool {
        didSet { set("isMonitoringPaused", isMonitoringPaused) }
    }
    @Published public var excludedBundleIds: [String] {
        didSet { set("excludedBundleIds", excludedBundleIds) }
    }
    @Published public var allowedBundleIds: [String] {
        didSet { set("allowedBundleIds", allowedBundleIds) }
    }
    @Published public var allowedBundleIdsOnly: Bool {
        didSet { set("allowedBundleIdsOnly", allowedBundleIdsOnly) }
    }
    @Published public var excludeRegexPatterns: [String] {
        didSet { set("excludeRegexPatterns", excludeRegexPatterns) }
    }
    @Published public var skipPasswordManagers: Bool {
        didSet { set("skipPasswordManagers", skipPasswordManagers) }
    }
    @Published public var launchAtLogin: Bool {
        didSet { set("launchAtLogin", launchAtLogin) }
    }
    @Published public var enableOCR: Bool {
        didSet { set("enableOCR", enableOCR) }
    }
    @Published public var hideGroupedFromMain: Bool {
        didSet { set("hideGroupedFromMain", hideGroupedFromMain) }
    }
    @Published public var lastPopupOriginX: Double {
        didSet { set("lastPopupOriginX", lastPopupOriginX) }
    }
    @Published public var lastPopupOriginY: Double {
        didSet { set("lastPopupOriginY", lastPopupOriginY) }
    }
    @Published public var autoBackupEnabled: Bool {
        didSet { set("autoBackupEnabled", autoBackupEnabled) }
    }
    @Published public var backupDirectoryPath: String {
        didSet { set("backupDirectoryPath", backupDirectoryPath) }
    }
    @Published public var captureText: Bool {
        didSet { set("captureText", captureText) }
    }
    @Published public var captureImages: Bool {
        didSet { set("captureImages", captureImages) }
    }
    @Published public var captureFiles: Bool {
        didSet { set("captureFiles", captureFiles) }
    }
    @Published public var advancedRegexSearch: Bool {
        didSet { set("advancedRegexSearch", advancedRegexSearch) }
    }

    public init() {
        // Default hotkey: Control + backtick (keyCode 50)
        hasCompletedOnboarding = defaults.object(forKey: prefix + "hasCompletedOnboarding") as? Bool ?? false
        openHotkeyKeyCode = UInt32(defaults.object(forKey: prefix + "openHotkeyKeyCode") as? Int ?? 50)
        openHotkeyModifiers = UInt32(defaults.object(forKey: prefix + "openHotkeyModifiers") as? Int ?? Int(controlKey))
        popupPositionMode = PopupPositionMode(rawValue: defaults.string(forKey: prefix + "popupPositionMode") ?? "") ?? .mouseCursor
        rememberPopupFrame = defaults.object(forKey: prefix + "rememberPopupFrame") as? Bool ?? true
        popupWidth = defaults.object(forKey: prefix + "popupWidth") as? Double ?? 520
        popupHeight = defaults.object(forKey: prefix + "popupHeight") as? Double ?? 420
        popupOpacity = defaults.object(forKey: prefix + "popupOpacity") as? Double ?? 0.97
        alwaysOnTop = defaults.object(forKey: prefix + "alwaysOnTop") as? Bool ?? true
        keepOpenAfterPaste = defaults.object(forKey: prefix + "keepOpenAfterPaste") as? Bool ?? false
        closeOnFocusLoss = defaults.object(forKey: prefix + "closeOnFocusLoss") as? Bool ?? true
        listLineCount = defaults.object(forKey: prefix + "listLineCount") as? Int ?? 2
        showThumbnails = defaults.object(forKey: prefix + "showThumbnails") as? Bool ?? true
        thumbnailSize = defaults.object(forKey: prefix + "thumbnailSize") as? Double ?? 36
        listDensity = defaults.object(forKey: prefix + "listDensity") as? Double ?? 1.0
        fontSize = defaults.object(forKey: prefix + "fontSize") as? Double ?? 13
        showUseCount = defaults.object(forKey: prefix + "showUseCount") as? Bool ?? false
        allowDuplicates = defaults.object(forKey: prefix + "allowDuplicates") as? Bool ?? false
        bumpDuplicatesToTop = defaults.object(forKey: prefix + "bumpDuplicatesToTop") as? Bool ?? true
        maxEntries = defaults.object(forKey: prefix + "maxEntries") as? Int ?? 0
        maxDatabaseBytes = defaults.object(forKey: prefix + "maxDatabaseBytes") as? Int ?? 0
        maxAgeDays = defaults.object(forKey: prefix + "maxAgeDays") as? Int ?? 0
        maxImageEntries = defaults.object(forKey: prefix + "maxImageEntries") as? Int ?? 0
        warnLowDiskBytes = defaults.object(forKey: prefix + "warnLowDiskBytes") as? Int ?? 1_000_000_000
        isMonitoringPaused = defaults.object(forKey: prefix + "isMonitoringPaused") as? Bool ?? false
        excludedBundleIds = defaults.stringArray(forKey: prefix + "excludedBundleIds") ?? []
        allowedBundleIds = defaults.stringArray(forKey: prefix + "allowedBundleIds") ?? []
        allowedBundleIdsOnly = defaults.object(forKey: prefix + "allowedBundleIdsOnly") as? Bool ?? false
        excludeRegexPatterns = defaults.stringArray(forKey: prefix + "excludeRegexPatterns") ?? []
        skipPasswordManagers = defaults.object(forKey: prefix + "skipPasswordManagers") as? Bool ?? true
        launchAtLogin = defaults.object(forKey: prefix + "launchAtLogin") as? Bool ?? false
        enableOCR = defaults.object(forKey: prefix + "enableOCR") as? Bool ?? true
        hideGroupedFromMain = defaults.object(forKey: prefix + "hideGroupedFromMain") as? Bool ?? false
        lastPopupOriginX = defaults.object(forKey: prefix + "lastPopupOriginX") as? Double ?? -1
        lastPopupOriginY = defaults.object(forKey: prefix + "lastPopupOriginY") as? Double ?? -1
        autoBackupEnabled = defaults.object(forKey: prefix + "autoBackupEnabled") as? Bool ?? false
        backupDirectoryPath = defaults.string(forKey: prefix + "backupDirectoryPath") ?? AppPaths.backupsDirectory.path
        captureText = defaults.object(forKey: prefix + "captureText") as? Bool ?? true
        captureImages = defaults.object(forKey: prefix + "captureImages") as? Bool ?? true
        captureFiles = defaults.object(forKey: prefix + "captureFiles") as? Bool ?? true
        advancedRegexSearch = defaults.object(forKey: prefix + "advancedRegexSearch") as? Bool ?? false
    }

    private func set<T>(_ key: String, _ value: T) {
        defaults.set(value, forKey: prefix + key)
        NotificationCenter.default.post(name: .pasteRushSettingsDidChange, object: nil)
    }
}

public enum PopupPositionMode: String, CaseIterable, Identifiable, Sendable {
    case mouseCursor
    case activeTextField
    case lastPosition

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mouseCursor: return L10n.tr("popup.position.mouse")
        case .activeTextField: return L10n.tr("popup.position.text_field")
        case .lastPosition: return L10n.tr("popup.position.last")
        }
    }
}

// Carbon controlKey constant value
private let controlKey: Int = 4096
