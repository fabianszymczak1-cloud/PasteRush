import AppKit
import PasteRushCore

/// Sample history for App Store screenshots and the review recording.
/// Runs only inside the sandboxed store build, so it cannot touch the GitHub app's database.
enum StoreDemo {
    static func run(openSettings: @escaping () -> Void) {
        let mode = CommandLine.arguments.drop(while: { $0 != "--store-demo" }).dropFirst().first ?? "tour"
        if mode == "restore" {
            NSWorkspace.shared.runningApplications.forEach { $0.unhide() }
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        let settings = SettingsStore.shared
        settings.hasCompletedOnboarding = true
        settings.showThumbnails = true
        settings.thumbnailSize = 72.0
        settings.popupWidth = 960
        settings.popupHeight = 560
        settings.popupOpacity = 1
        settings.listLineCount = 2
        settings.fontSize = 14.0
        settings.popupPositionMode = .lastPosition
        settings.closeOnFocusLoss = false
        settings.keepOpenAfterPaste = true
        settings.alwaysOnTop = true
        if let screen = NSScreen.main?.visibleFrame {
            settings.lastPopupOriginX = screen.midX - 480
            settings.lastPopupOriginY = screen.midY - 180
        }

        if mode == "live" {
            configureLivePopup()
        }

        let repo = ClipRepository()
        repo.deleteAll()
        if mode != "live" {
            seed(repo)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch mode {
            case "live":
                playLive()
            case "settings":
                openSettings()
            case "tips":
                Distribution.presentSupport()
            case "preview":
                PopupWindowController.shared.show()
                PopupWindowController.shared.setPinnedOpen(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    PopupWindowController.shared.demoPreviewFirstImage()
                }
            case "history":
                PopupWindowController.shared.show()
                PopupWindowController.shared.setPinnedOpen(true)
            default:
                playTour(openSettings: openSettings)
            }
        }
    }

    private static func configureLivePopup() {
        let settings = SettingsStore.shared
        settings.popupWidth = 860
        settings.popupHeight = 640
        settings.thumbnailSize = 84
        settings.fontSize = 16
        settings.listLineCount = 2
        if let screen = NSScreen.main?.visibleFrame {
            let width = floor(screen.width * 0.48)
            settings.popupWidth = width
            settings.popupHeight = screen.height - 8
            settings.lastPopupOriginX = screen.maxX - width
            settings.lastPopupOriginY = screen.minY + 4
        }
    }

    /// Copy from a note, paste into a different document, then do the same with a photo.
    private static func playLive() {
        let hidden = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        hidden.forEach { $0.hide() }

        let stage = DemoStage()
        stage.showNotes()
        let popup = PopupWindowController.shared
        popup.show()
        popup.setPinnedOpen(true)
        let repo = ClipRepository()
        let photo = coastImage()

        func at(_ delay: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        at(1.0) { stage.selectParagraph(0) }
        at(1.7) { stage.showEditMenu(highlight: "Copy") }
        at(2.5) {
            stage.hideEditMenu()
            copyText(repo, stage.paragraphs[0])
        }
        at(3.1) { stage.showEditMenu(highlight: "Paste", inReply: true) }
        at(3.8) {
            stage.hideEditMenu()
            stage.pasteText(stage.paragraphs[0])
        }
        at(5.0) { stage.selectParagraph(1) }
        at(5.6) { stage.showEditMenu(highlight: "Copy") }
        at(6.3) {
            stage.hideEditMenu()
            copyText(repo, stage.paragraphs[1])
        }
        at(6.9) { stage.showEditMenu(highlight: "Paste", inReply: true) }
        at(7.6) {
            stage.hideEditMenu()
            stage.pasteText(stage.paragraphs[1])
        }
        at(8.8) { stage.showPhoto(photo) }
        at(9.5) { stage.showEditMenu(highlight: "Copy", onPhoto: true) }
        at(10.2) {
            stage.hideEditMenu()
            copyImage(repo, photo)
        }
        at(11.2) { stage.hidePhoto() }
        let letters = ["c", "co", "coa", "coas", "coast"]
        for (index, text) in letters.enumerated() {
            at(11.6 + Double(index) * 0.26) { popup.demoSearch(text) }
        }
        at(13.4) { popup.demoPreviewFirstImage() }
        at(15.2) {
            popup.demoHidePreview()
            popup.demoSearch("coast")
        }
        at(15.8) { stage.showEditMenu(highlight: "Paste", inReply: true) }
        at(16.5) {
            stage.hideEditMenu()
            stage.pastePhoto(photo)
        }
        at(18.6) {
            Distribution.presentSupport()
            TipSupportWindowController.shared.window?.level = .modalPanel
        }
        at(22.4) {
            hidden.forEach { $0.unhide() }
            _ = stage
        }
    }

    private static func copyText(_ repo: ClipRepository, _ text: String) {
        let monitor = ClipboardMonitor.shared
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        monitor.noteOwnChangeCount(pb.changeCount)
        monitor.ignoreNextPasteboardWrite(changeCount: pb.changeCount)
        insertText(repo, text, preview: text, app: "Notes", copiedAt: Date())
        NotificationCenter.default.post(name: .pasteRushHistoryDidChange, object: nil)
    }

    private static func copyImage(_ repo: ClipRepository, _ image: NSImage) {
        let monitor = ClipboardMonitor.shared
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        monitor.noteOwnChangeCount(pb.changeCount)
        monitor.ignoreNextPasteboardWrite(changeCount: pb.changeCount)
        insertImage(repo, image: image, title: "Coast at sunset", app: "Preview", copiedAt: Date())
        NotificationCenter.default.post(name: .pasteRushHistoryDidChange, object: nil)
    }

    private static func playTour(openSettings: @escaping () -> Void) {
        let popup = PopupWindowController.shared
        popup.show()
        popup.setPinnedOpen(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            popup.demoSearch("screenshot")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.6) {
            popup.demoPreviewFirstImage()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.6) {
            popup.demoHidePreview()
            popup.hide()
            openSettings()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14.2) {
            NSApp.terminate(nil)
        }
    }

    private static func seed(_ repo: ClipRepository) {
        let now = Date()
        insertText(
            repo,
            """
            Studio Wi-Fi
            Name: Northlight
            Password stays on this Mac.
            """,
            preview: "Studio Wi-Fi — Northlight",
            app: "Notes",
            copiedAt: now.addingTimeInterval(-20),
            pinned: true
        )
        insertImage(repo, image: coastImage(), title: "Coast at sunset", app: "Preview", copiedAt: now.addingTimeInterval(-80))
        insertText(
            repo,
            """
            func searchHistory() {
                clips.filter { $0.kind == .image }
            }
            """,
            preview: "func searchHistory() { clips.filter { $0.kind == .image } }",
            app: "Xcode",
            copiedAt: now.addingTimeInterval(-140)
        )
        insertText(
            repo,
            "https://developer.apple.com/documentation/appkit",
            preview: "https://developer.apple.com/documentation/appkit",
            app: "Safari",
            copiedAt: now.addingTimeInterval(-200)
        )
        insertImage(repo, image: dashboardImage(), title: "Weekly report screenshot", app: "Safari", copiedAt: now.addingTimeInterval(-260))
        insertText(
            repo,
            """
            Ship notes
            PasteRush keeps screenshots, photos, files, and text.
            The Mac clipboard keeps one item. This list does not.
            """,
            preview: "Ship notes — screenshots, photos, files, and text",
            app: "Notes",
            copiedAt: now.addingTimeInterval(-320)
        )
    }

    private static func insertText(
        _ repo: ClipRepository,
        _ text: String,
        preview: String,
        app: String,
        copiedAt: Date,
        pinned: Bool = false
    ) {
        let data = Data(text.utf8)
        let clip = ClipRecord(
            copiedAt: copiedAt,
            lastUsedAt: copiedAt,
            primaryType: text.hasPrefix("http") ? .url : .text,
            searchText: PolishNormalizer.searchBlob(from: text),
            preview: preview,
            contentHash: ContentHasher.hashText(text),
            totalBytes: data.count,
            sourceAppName: app,
            isPinned: pinned,
            formats: [ClipFormat(uti: "public.utf8-plain-text", inlineData: data, textContent: text, byteSize: data.count)]
        )
        let saved = repo.insert(clip, allowDuplicates: true)
        if pinned {
            repo.setPinned(id: saved.id, pinned: true)
        }
    }

    private static func insertImage(_ repo: ClipRepository, image: NSImage, title: String, app: String, copiedAt: Date) {
        guard let png = pngData(image) else { return }
        let id = UUID().uuidString
        let blob = AppPaths.blobURL(clipId: id, uti: "public.png")
        try? png.write(to: blob, options: .atomic)
        let thumb = AppPaths.thumbnailURL(clipId: id)
        if let jpeg = jpegData(image, max: 160) {
            try? jpeg.write(to: thumb, options: .atomic)
        }
        let clip = ClipRecord(
            id: id,
            copiedAt: copiedAt,
            lastUsedAt: copiedAt,
            primaryType: .image,
            searchText: PolishNormalizer.searchBlob(from: title),
            preview: title,
            contentHash: ContentHasher.hash(formats: [("public.png", png)]),
            totalBytes: png.count,
            sourceAppName: app,
            thumbnailPath: thumb.path,
            imageWidth: Int(image.size.width),
            imageHeight: Int(image.size.height),
            formats: [ClipFormat(uti: "public.png", blobPath: blob.path, byteSize: png.count)]
        )
        _ = repo.insert(clip, allowDuplicates: true)
    }

    private static func dashboardImage() -> NSImage {
        let size = NSSize(width: 880, height: 520)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let card = NSRect(x: 36, y: 36, width: 808, height: 448)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill()
        let title = "Weekly report" as NSString
        title.draw(at: NSPoint(x: 64, y: 420), withAttributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ])
        let bars: [(CGFloat, NSColor)] = [
            (120, NSColor.systemBlue),
            (180, NSColor.systemTeal),
            (90, NSColor.systemIndigo),
            (210, NSColor.systemBlue),
            (150, NSColor.systemTeal),
            (240, NSColor.systemOrange)
        ]
        for (index, bar) in bars.enumerated() {
            let x = 80 + CGFloat(index) * 120
            let rect = NSRect(x: x, y: 90, width: 64, height: bar.0)
            bar.1.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        }
        image.unlockFocus()
        return image
    }

    private static func coastImage() -> NSImage {
        let size = NSSize(width: 880, height: 520)
        let image = NSImage(size: size)
        image.lockFocus()
        let sky = NSGradient(colors: [
            NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.32, alpha: 1),
            NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.62, alpha: 1)
        ])
        sky?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.34, alpha: 1).setFill()
        let sea = NSBezierPath()
        sea.move(to: NSPoint(x: 0, y: 180))
        sea.curve(to: NSPoint(x: 880, y: 150), controlPoint1: NSPoint(x: 280, y: 230), controlPoint2: NSPoint(x: 560, y: 90))
        sea.line(to: NSPoint(x: 880, y: 0))
        sea.line(to: NSPoint(x: 0, y: 0))
        sea.close()
        sea.fill()
        NSColor(calibratedRed: 1, green: 0.82, blue: 0.45, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 620, y: 340, width: 90, height: 90)).fill()
        image.unlockFocus()
        return image
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func jpegData(_ image: NSImage, max: CGFloat) -> Data? {
        let thumb = NSImage(size: NSSize(width: max, height: max))
        thumb.lockFocus()
        let ratio = min(max / image.size.width, max / image.size.height)
        let draw = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let origin = NSPoint(x: (max - draw.width) / 2, y: (max - draw.height) / 2)
        image.draw(in: NSRect(origin: origin, size: draw))
        thumb.unlockFocus()
        guard let tiff = thumb.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}

/// Source note, empty reply document, and the Kopiuj / Wklej menu shown in the recording.
final class DemoStage: NSObject {
    let paragraphs = [
        "Ship the photo library today.",
        "Meeting link: notes.northlight.studio"
    ]
    private let coverWindow: NSWindow
    private let notesWindow: NSWindow
    private let textView: NSTextView
    private let replyWindow: NSWindow
    private let replyView: NSTextView
    private let photoWindow: NSWindow
    private let menuWindow: NSWindow
    private let ranges: [NSRange]

    override init() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 80, width: 1800, height: 1000)
        let full = NSScreen.main?.frame ?? screen
        coverWindow = NSWindow(contentRect: full, styleMask: .borderless, backing: .buffered, defer: false)
        coverWindow.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        coverWindow.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        coverWindow.isOpaque = true
        coverWindow.hasShadow = false
        coverWindow.ignoresMouseEvents = true
        coverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        coverWindow.isReleasedWhenClosed = false

        let column = ceil(screen.width * 0.52)
        let notesFrame = NSRect(x: screen.minX, y: screen.midY + 6, width: column, height: screen.maxY - screen.midY - 6)
        let replyFrame = NSRect(x: screen.minX, y: screen.minY, width: column, height: screen.midY - screen.minY - 6)

        notesWindow = DemoStage.documentWindow(frame: notesFrame, title: "Notes")
        replyWindow = DemoStage.documentWindow(frame: replyFrame, title: "Reply")

        let body = paragraphs.joined(separator: "\n\n") + "\n\n"
        textView = DemoStage.editor(in: notesWindow, editable: false)
        textView.string = body
        let ns = body as NSString
        var start = 0
        ranges = paragraphs.map { paragraph in
            let found = ns.range(of: paragraph, range: NSRange(location: start, length: ns.length - start))
            start = found.location + found.length
            return found
        }

        replyView = DemoStage.editor(in: replyWindow, editable: true)
        replyView.string = ""

        photoWindow = NSWindow(contentRect: notesFrame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        photoWindow.title = "Coast at sunset.png"
        photoWindow.isReleasedWhenClosed = false
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: notesFrame.size))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        photoWindow.contentView = imageView

        menuWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 96),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        menuWindow.level = .popUpMenu
        menuWindow.isOpaque = false
        menuWindow.backgroundColor = .clear
        menuWindow.hasShadow = true
        menuWindow.isReleasedWhenClosed = false
        super.init()
    }

    func showNotes() {
        coverWindow.orderFrontRegardless()
        for window in [notesWindow, replyWindow, photoWindow] {
            window.level = .floating
        }
        replyWindow.makeKeyAndOrderFront(nil)
        notesWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectParagraph(_ index: Int) {
        guard ranges.indices.contains(index) else { return }
        notesWindow.makeKeyAndOrderFront(nil)
        let full = ranges[index]
        let steps = 7
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.045) { [textView] in
                let length = max(1, full.length * step / steps)
                textView.setSelectedRange(NSRange(location: full.location, length: length))
            }
        }
    }

    func showEditMenu(highlight: String, inReply: Bool = false, onPhoto: Bool = false) {
        let host: NSWindow
        if onPhoto {
            host = photoWindow
        } else if inReply {
            host = replyWindow
        } else {
            host = notesWindow
        }
        host.makeKeyAndOrderFront(nil)
        let anchor = menuAnchor(inReply: inReply, onPhoto: onPhoto)
        let rows = [("Cut", "⌘X"), ("Copy", "⌘C"), ("Paste", "⌘V")]
        let view = EditMenuView(rows: rows, highlight: highlight)
        menuWindow.contentView = view
        menuWindow.setFrame(NSRect(x: anchor.x, y: anchor.y - 96, width: 230, height: 96), display: true)
        menuWindow.orderFrontRegardless()
    }

    func hideEditMenu() {
        menuWindow.orderOut(nil)
    }

    func showPhoto(_ image: NSImage) {
        (photoWindow.contentView as? NSImageView)?.image = image
        photoWindow.setFrame(notesWindow.frame, display: true)
        photoWindow.makeKeyAndOrderFront(nil)
    }

    func hidePhoto() {
        photoWindow.orderOut(nil)
        notesWindow.makeKeyAndOrderFront(nil)
    }

    func pasteText(_ text: String) {
        replyWindow.makeKeyAndOrderFront(nil)
        let attr = NSAttributedString(string: text + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        replyView.textStorage?.append(attr)
        let end = NSRange(location: (replyView.string as NSString).length, length: 0)
        replyView.setSelectedRange(end)
        replyView.scrollRangeToVisible(end)
    }

    func pastePhoto(_ image: NSImage) {
        let scaled = NSImage(size: NSSize(width: 420, height: 248))
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaled.size))
        scaled.unlockFocus()
        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: scaled)
        replyView.textStorage?.append(NSAttributedString(string: "\n"))
        replyView.textStorage?.append(NSAttributedString(attachment: attachment))
        replyWindow.makeKeyAndOrderFront(nil)
    }

    private func menuAnchor(inReply: Bool, onPhoto: Bool) -> NSPoint {
        if onPhoto {
            let frame = photoWindow.frame
            return NSPoint(x: frame.midX - 40, y: frame.midY)
        }
        let view = inReply ? replyView : textView
        let range = view.selectedRange()
        if range.location != NSNotFound, range.length > 0 || inReply {
            let rect = view.firstRect(forCharacterRange: NSRange(location: range.location, length: max(range.length, 1)), actualRange: nil)
            if rect.width > 1 || rect.height > 1 {
                return NSPoint(x: rect.minX + 24, y: rect.minY)
            }
        }
        let frame = (inReply ? replyWindow : notesWindow).frame
        return NSPoint(x: frame.minX + 80, y: frame.midY)
    }

    private static func documentWindow(frame: NSRect, title: String) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    private static func editor(in window: NSWindow, editable: Bool) -> NSTextView {
        let text = NSTextView(frame: window.contentView?.bounds ?? .zero)
        text.isEditable = editable
        text.isSelectable = true
        text.isRichText = true
        text.drawsBackground = true
        text.backgroundColor = .textBackgroundColor
        text.font = .systemFont(ofSize: 28, weight: .medium)
        text.textContainerInset = NSSize(width: 28, height: 22)
        text.autoresizingMask = [.width, .height]
        window.contentView = text
        return text
    }
}

private final class EditMenuView: NSView {
    let rows: [(String, String)]
    let highlight: String

    init(rows: [(String, String)], highlight: String) {
        self.rows = rows
        self.highlight = highlight
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 96))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSColor(calibratedWhite: 0.16, alpha: 0.98)
        background.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        let rowHeight = bounds.height / CGFloat(rows.count)
        for (index, row) in rows.enumerated() {
            let rect = NSRect(x: 6, y: bounds.height - rowHeight * CGFloat(index + 1) + 3, width: bounds.width - 12, height: rowHeight - 6)
            if row.0 == highlight {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let color: NSColor = row.0 == highlight ? .white : .labelColor
            let title = NSAttributedString(string: row.0, attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: color
            ])
            let keys = NSAttributedString(string: row.1, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: color.withAlphaComponent(0.85)
            ])
            title.draw(at: NSPoint(x: rect.minX + 12, y: rect.midY - 8))
            keys.draw(at: NSPoint(x: rect.maxX - 36, y: rect.midY - 8))
        }
    }
}
