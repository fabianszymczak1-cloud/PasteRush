import AppKit
import ApplicationServices
import Foundation

public final class PreviousApplicationTracker {
    public private(set) var previousApp: NSRunningApplication?
    public private(set) var previousPID: pid_t?

    public init() {}

    public func capture() {
        let front = NSWorkspace.shared.frontmostApplication
        // Ignore ourselves
        if front?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        previousApp = front
        previousPID = front?.processIdentifier
    }

    @discardableResult
    public func activatePrevious() -> Bool {
        guard let app = previousApp, !app.isTerminated else { return false }
        return app.activate()
    }
}

public final class AccessibilityPermissionManager {
    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func promptIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    public func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}

@MainActor
public final class PasteCoordinator {
    public static let shared = PasteCoordinator()

    public let previousAppTracker = PreviousApplicationTracker()
    public let accessibility = AccessibilityPermissionManager()
    private let repository = ClipRepository()

    public var lastPasteMessage: String?

    public init() {}

    public func paste(clipId: String, plainTextOnly: Bool = false, copyOnly: Bool = false, transform: TextTransform? = nil) {
        guard let clip = repository.get(id: clipId) else { return }
        writeToPasteboard(clip: clip, plainTextOnly: plainTextOnly, transform: transform)

        if copyOnly {
            repository.markUsed(id: clipId)
            lastPasteMessage = "Skopiowano do schowka"
            return
        }

        let keepOpen = SettingsStore.shared.keepOpenAfterPaste
        if !keepOpen {
            NotificationCenter.default.post(name: .pasteRushHidePopup, object: nil)
        }

        let activated = previousAppTracker.activatePrevious()
        let delay: TimeInterval = activated ? 0.05 : 0.08

        if accessibility.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.sendCommandV()
                self.repository.markUsed(id: clipId)
            }
            lastPasteMessage = nil
        } else {
            repository.markUsed(id: clipId)
            lastPasteMessage = "Brak uprawnienia Dostępność — naciśnij ⌘V"
            NotificationCenter.default.post(name: .pasteRushNeedsPasteManual, object: lastPasteMessage)
        }
    }

    public func pastePlainText(_ text: String, copyOnly: Bool = false) {
        let pb = NSPasteboard.general
        let monitor = ClipboardMonitor.shared
        pb.clearContents()
        pb.setString(text, forType: .string)
        monitor.noteOwnChangeCount(pb.changeCount)
        monitor.ignoreNextPasteboardWrite(changeCount: pb.changeCount)

        if copyOnly { return }

        NotificationCenter.default.post(name: .pasteRushHidePopup, object: nil)
        _ = previousAppTracker.activatePrevious()
        if accessibility.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.sendCommandV()
            }
        } else {
            lastPasteMessage = "Brak uprawnienia Dostępność — naciśnij ⌘V"
            NotificationCenter.default.post(name: .pasteRushNeedsPasteManual, object: lastPasteMessage)
        }
    }

    public func writeToPasteboard(clip: ClipRecord, plainTextOnly: Bool = false, transform: TextTransform? = nil) {
        let pb = NSPasteboard.general
        let monitor = ClipboardMonitor.shared
        pb.clearContents()

        if plainTextOnly || transform != nil {
            var text = clip.formats.first(where: { $0.textContent != nil })?.textContent
                ?? clip.searchText
            if let transform {
                if transform == .textAsImage {
                    if let image = textToImage(text) {
                        pb.writeObjects([image])
                        monitor.noteOwnChangeCount(pb.changeCount)
                        monitor.ignoreNextPasteboardWrite(changeCount: pb.changeCount)
                        return
                    }
                } else if transform == .generateUUID {
                    text = TextTransform.generateUUID.apply(to: "")
                } else {
                    text = transform.apply(to: text)
                }
            }
            pb.setString(text, forType: .string)
        } else {
            var wrote = false
            for format in clip.formats {
                let data = format.inlineData ?? format.blobPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
                guard let data else { continue }
                let type = NSPasteboard.PasteboardType(format.uti)
                pb.setData(data, forType: type)
                wrote = true
                if let text = format.textContent {
                    pb.setString(text, forType: .string)
                }
            }
            if !wrote {
                pb.setString(clip.preview, forType: .string)
            }
        }

        monitor.noteOwnChangeCount(pb.changeCount)
        monitor.ignoreNextPasteboardWrite(changeCount: pb.changeCount)
    }

    public func pasteMultiple(ids: [String], mode: MultiJoinMode, customSeparator: String = " | ") {
        let clips = ids.compactMap { repository.get(id: $0) }
        if mode == .imagesVertical || mode == .imagesHorizontal {
            let images: [NSImage] = clips.compactMap { clip in
                guard let format = clip.formats.first(where: { $0.uti.contains("png") || $0.uti.contains("tiff") || $0.uti.contains("image") }) else { return nil }
                let data = format.inlineData ?? format.blobPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
                return data.flatMap { NSImage(data: $0) }
            }
            if let combined = TextTransforms.combineImages(images, vertical: mode == .imagesVertical) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([combined])
                ClipboardMonitor.shared.noteOwnChangeCount(pb.changeCount)
                ClipboardMonitor.shared.ignoreNextPasteboardWrite(changeCount: pb.changeCount)
                NotificationCenter.default.post(name: .pasteRushHidePopup, object: nil)
                _ = previousAppTracker.activatePrevious()
                if accessibility.isTrusted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.sendCommandV() }
                }
            }
            return
        }

        if mode == .sequential {
            // paste one after another with short delays
            NotificationCenter.default.post(name: .pasteRushHidePopup, object: nil)
            _ = previousAppTracker.activatePrevious()
            for (index, clip) in clips.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.15) {
                    self.writeToPasteboard(clip: clip)
                    if self.accessibility.isTrusted {
                        self.sendCommandV()
                    }
                    self.repository.markUsed(id: clip.id)
                }
            }
            return
        }

        let texts = clips.map { $0.formats.first(where: { $0.textContent != nil })?.textContent ?? $0.preview }
        let joined = TextTransforms.join(texts, mode: mode, customSeparator: customSeparator)
        pastePlainText(joined)
    }

    public func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    public func runPasteTest() -> String {
        let marker = "PasteRush-test-\(UUID().uuidString.prefix(8))"
        pastePlainText(marker, copyOnly: false)
        return marker
    }

    private func textToImage(_ text: String) -> NSImage? {
        let font = NSFont.systemFont(ofSize: 24)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 16
        let image = NSImage(size: NSSize(width: size.width + padding * 2, height: size.height + padding * 2))
        image.lockFocus()
        NSColor.textBackgroundColor.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: image.size))
        (text as NSString).draw(at: NSPoint(x: padding, y: padding), withAttributes: attrs)
        image.unlockFocus()
        return image
    }
}

public extension Notification.Name {
    static let pasteRushHidePopup = Notification.Name("PasteRushHidePopup")
    static let pasteRushNeedsPasteManual = Notification.Name("PasteRushNeedsPasteManual")
}
