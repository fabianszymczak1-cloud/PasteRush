import AppKit
import Foundation

public final class ClipboardMonitor: ObservableObject {
    public static let shared = ClipboardMonitor()

    @Published public private(set) var isPaused = false
    @Published public private(set) var privateModeUntil: Date?
    @Published public private(set) var lastClipId: String?

    private let reader = PasteboardReader()
    private let repository = ClipRepository()
    private let thumbnailService = ThumbnailService()
    private let ocrService = OCRService()
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var ignoreChangeCounts = Set<Int>()
    private var ownPasteActive = false
    private let workQueue = DispatchQueue(label: "com.pasterush.clipboard", qos: .utility)

    public init() {}

    public func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func setPaused(_ paused: Bool) {
        DispatchQueue.main.async {
            self.isPaused = paused
        }
        SettingsStore.shared.isMonitoringPaused = paused
    }

    public func togglePause() {
        setPaused(!isPaused)
    }

    public func enablePrivateMode(minutes: Int) {
        DispatchQueue.main.async {
            self.privateModeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        }
    }

    public func clearPrivateMode() {
        DispatchQueue.main.async { self.privateModeUntil = nil }
    }

    public var isPrivateModeActive: Bool {
        if let until = privateModeUntil, until > Date() { return true }
        return false
    }

    public func ignoreNextPasteboardWrite(changeCount: Int? = nil) {
        ownPasteActive = true
        if let changeCount {
            ignoreChangeCounts.insert(changeCount)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.ownPasteActive = false
        }
    }

    public func noteOwnChangeCount(_ count: Int) {
        ignoreChangeCounts.insert(count)
        lastChangeCount = count
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if ignoreChangeCounts.remove(count) != nil || ownPasteActive {
            return
        }

        let settings = SettingsStore.shared
        if isPaused || isPrivateModeActive || settings.isMonitoringPaused {
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleId = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName

        if let bundleId {
            if settings.excludedBundleIds.contains(bundleId) { return }
            if settings.allowedBundleIdsOnly, !settings.allowedBundleIds.contains(bundleId) { return }
            if settings.skipPasswordManagers, Self.passwordManagerBundles.contains(bundleId) { return }
        }

        let allowDuplicates = settings.allowDuplicates
        let bumpDuplicates = settings.bumpDuplicatesToTop
        let enableOCR = settings.enableOCR
        let excludeRegexes = settings.excludeRegexPatterns
        let reader = self.reader
        let repository = self.repository
        let thumbnailService = self.thumbnailService
        let ocrService = self.ocrService

        // Read pasteboard on background without capturing NSPasteboard across threads unsafely:
        // snapshot types/data first on this (main) thread.
        let snapshot = reader.read(pasteboard: pb)
        guard let snapshot else { return }

        workQueue.async { [weak self] in
            if let text = snapshot.plainText {
                for pattern in excludeRegexes {
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                        return
                    }
                }
            }

            var formats: [ClipFormat] = []
            let clipId = UUID().uuidString
            var total = 0

            for pair in snapshot.formats {
                let large = pair.data.count > 64_000
                var blobPath: String?
                var inline: Data?
                if large || snapshot.primaryType == .image {
                    let url = AppPaths.blobURL(clipId: clipId, uti: pair.uti)
                    try? pair.data.write(to: url, options: .atomic)
                    blobPath = url.path
                } else {
                    inline = pair.data
                }
                let textContent: String? = {
                    if pair.uti.contains("text") || pair.uti.contains("html") || pair.uti.contains("utf8") {
                        return String(data: pair.data, encoding: .utf8)
                    }
                    return nil
                }()
                formats.append(ClipFormat(uti: pair.uti, blobPath: blobPath, inlineData: inline, textContent: textContent, byteSize: pair.data.count))
                total += pair.data.count
            }

            let clip = ClipRecord(
                id: clipId,
                primaryType: snapshot.primaryType,
                searchText: snapshot.searchText,
                preview: snapshot.preview,
                contentHash: snapshot.contentHash,
                totalBytes: total,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                imageWidth: snapshot.imageSize.map { Int($0.width) },
                imageHeight: snapshot.imageSize.map { Int($0.height) },
                formats: formats
            )

            let saved = repository.insert(
                clip,
                bumpExistingDuplicates: bumpDuplicates,
                allowDuplicates: allowDuplicates
            )

            DispatchQueue.main.async {
                self?.lastClipId = saved.id
                NotificationCenter.default.post(name: .pasteRushHistoryDidChange, object: saved.id)
            }

            if snapshot.primaryType == .image, let data = snapshot.imageData {
                thumbnailService.generateThumbnail(clipId: saved.id, imageData: data) { path in
                    repository.dbUpdateThumbnail(id: saved.id, path: path)
                }
                if enableOCR {
                    ocrService.recognize(imageData: data) { text in
                        guard let text, !text.isEmpty else { return }
                        repository.updateOCR(id: saved.id, text: text)
                    }
                }
            }

            RetentionService(repository: repository, settings: SettingsStore.shared).enforceIfNeeded()
        }
    }

    private static let passwordManagerBundles: Set<String> = [
        "com.1password.1password",
        "com.1password.1password-launcher",
        "com.agilebits.onepassword7",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.keepassxc.keepassxc"
    ]
}

public extension Notification.Name {
    static let pasteRushHistoryDidChange = Notification.Name("PasteRushHistoryDidChange")
    static let pasteRushSettingsDidChange = Notification.Name("PasteRushSettingsDidChange")
    static let pasteRushShowPopup = Notification.Name("PasteRushShowPopup")
    static let pasteRushTogglePopup = Notification.Name("PasteRushTogglePopup")
}

extension ClipRepository {
    func dbUpdateThumbnail(id: String, path: String) {
        Database.shared.async {
            Database.shared.exec("UPDATE clips SET thumbnail_path = '\(path.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(id)';")
        }
    }
}
